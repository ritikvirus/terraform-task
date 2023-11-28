import six
from time import sleep
from collections import defaultdict

from .. import utils
from .base import ECSDeployCheckerBase


class ECSDeployLoadbalancerChecker(ECSDeployCheckerBase):
    def run(self):
        """
        Execute check for loadbalancer healthchecks, validating that they are
        passing for the deployed service.

        Returns:
            A tuple pair of boolean and string, where the boolean indicates
            whether or not the check passed, and the string represents an error
            reason if it failed.
        """
        utils.logger.info('Checking whether or not task is returning a healthy status')
        passed = self.check_until_consecutive_successes(self.check_task_is_healthy)
        if not passed:
            utils.logger.info('ECS deployment check timedout waiting for task to be healthy')
            return False, 'Timedout waiting for task to be healthy'

        utils.logger.info('Passed loadbalancer check')
        return True, ''

    def check_task_is_healthy(self):
        """
        Verify that the deployed task is passing loadbalancer health checks on
        all targets. Passing the health checks involves:
        - Making sure the task is registered on the LB target group
        - Making sure the task is reporting healthy by the LB
        """
        service = self.get_service()
        if self.check_service_is_fargate(service):
            return self.__check_task_is_healthy_fargate(service)
        else:
            return self.__check_task_is_healthy_ec2(service)

    @staticmethod
    def check_service_is_fargate(service):
        """
        Verify the given service is Fargate type.
        """
        if service.get('launchType', None) == 'FARGATE':
            return True

        for strategy in service.get('capacityProviderStrategy', []):
            if 'FARGATE' in strategy.get('capacityProvider', []):
                return True

        return False

    def check_loadbalancer_target(self, loadbalancer, task_target_info):
        """
        Verify the given loadbalancer target is passing all healthchecks.
        """
        target_group_arn = loadbalancer['targetGroupArn']
        container_name = loadbalancer['containerName']
        container_port = loadbalancer['containerPort']

        utils.logger.info(
            'Checking LoadBalancer target group {} for container {} port {}'
            .format(target_group_arn, container_name, container_port)
        )

        resp = self.elb_client.describe_target_health(TargetGroupArn=target_group_arn)
        targets = resp['TargetHealthDescriptions']
        utils.logger.info(
            'Found {} targets for target group {}'.format(len(targets), target_group_arn))

        utils.logger.info('Checking if expected targets from task are registered')
        expected_targets = task_target_info[(container_name, container_port)]
        utils.logger.info('Expecting {} targets to be registered in LB'.format(len(expected_targets)))
        if len(expected_targets) < self.min_active_task_count:
            utils.logger.warn(
                'Not enough expected targets found: expected {} targets from tasks, found {} targets'
                .format(len(expected_targets), self.min_active_task_count)
            )
            return False

        for expected_target in expected_targets:
            if not self.__targets_contain_expected_target(expected_target, targets):
                utils.logger.warn('Target {} is not registered'.format(expected_target))
                return False

        utils.logger.info('Checking if all targets healthy')
        return all(
            state['TargetHealth']['State'] == 'healthy'
            for state in targets)

    def __check_task_is_healthy_fargate(self, service):
        """
        Verify that the deployed task is passing loadbalancer health checks for Fargate based ECS service.

        Fargate based ECS service ALBs are bound via the network interface associated with the task, so we need special
        logic to resolve to the network interface of the deployed tasks.
        """
        loadbalancers = service['loadBalancers']
        utils.logger.info(
            'Found {} loadbalancers for service {}'.format(len(loadbalancers), self.ecs_service_arn))
        task_target_info = self.__get_awsvpc_targets_from_tasks(loadbalancers)
        return all(
            self.check_loadbalancer_target(loadbalancer, task_target_info)
            for loadbalancer in loadbalancers
        )

    def __check_task_is_healthy_ec2(self, service):
        """
        Verify that the deployed task is passing loadbalancer health checks for EC2 based ECS service.

        When using awsvpc networking mode, there is no indirection on the host instances to map to the containers.
        However, if the EC2 based ECS service are not using awsvpc networking mode, the ALBs are implemented by binding
        a high numbered port to the docker containers' port, so we need special logic to map the container port to the
        host port before we can check the ALB.
        """
        loadbalancers = service['loadBalancers']
        utils.logger.info(
            'Found {} loadbalancers for service {}'.format(len(loadbalancers), self.ecs_service_arn))

        # We get the target infos for awsvpc networking mode separately and merge the two maps together, as the target
        # info is different depending on the networking mode.
        awsvpc_task_target_info = self.__get_awsvpc_targets_from_tasks(loadbalancers)
        other_task_target_info, container_instance_arns = self.__get_ec2_targets_from_tasks()

        # We now build the mapping of the container instance arns to the actual EC2 instance ID. We do this here instead
        # of in `__get_ec2_targets_from_tasks` because the number of tasks are expected to be less than the total number
        # of ECS instances running.
        container_instance_arn_to_id = self.__map_container_instance_arn_to_instance_ids(list(container_instance_arns))

        task_target_info = defaultdict(list)
        for k, v in six.iteritems(awsvpc_task_target_info):
            task_target_info[k].extend(v)
        for k, v in six.iteritems(other_task_target_info):
            # Make sure to remap container instance ARNs to EC2 instance IDs
            for target in v:
                target['Id'] = container_instance_arn_to_id[target['Id']]
            task_target_info[k].extend(v)

        return all(
            self.check_loadbalancer_target(loadbalancer, task_target_info)
            for loadbalancer in loadbalancers
        )

    def __get_ec2_targets_from_tasks(self):
        """
        For each running task on the ECS service, find the bound host port for each container name and port pair.

        Returns:
            Tuple pair where:
            - First item is a map where keys are tuple pair of container name and container port and values is a list of
              container instance ARN and host port pairs.
            - Second items is the set of container instance ARNs found. This is used to get all the corresponding EC2
              instance IDs later.
        """
        tasks = self.get_running_tasks()
        task_info = defaultdict(list)
        container_instance_arns = set()
        for task in tasks:
            for container in task['containers']:
                container_name = container['name']
                for network in container['networkBindings']:
                    container_port = network['containerPort']
                    task_info[(container_name, container_port)].append({
                        'Id': task['containerInstanceArn'],
                        'Port': network['hostPort'],
                    })
                    container_instance_arns.add(task['containerInstanceArn'])
        return task_info, container_instance_arns

    def __map_container_instance_arn_to_instance_ids(self, container_instance_arns):
        """
        Returns a map where keys are container instance ARNs and values are instance ids for all the instances on
        the ECS cluster.
        """
        out = {}

        container_instances = []
        for arns in utils.groups_of(container_instance_arns, 100):
            arns = [arn for arn in arns if arn]  # filter out the Nones in the last group
            container_instances += self.ecs_client.describe_container_instances(
                cluster=self.ecs_cluster_arn,
                containerInstances=arns,
            )['containerInstances']
            # Add a sleep for 500 milliseconds to avoid hitting the AWS API rate limit
            sleep(0.5)

        for container_instance in container_instances:
            out[container_instance['containerInstanceArn']] = container_instance['ec2InstanceId']
        return out

    def __get_awsvpc_targets_from_tasks(self, loadbalancers):
        """
        For each running task on the ECS service, find the bound network IP.

        For awsvpc networking mode, there is no indirection in the port mapping as it will directly connect to the
        container via the bound IP address. As such, target groups are registered as IP address and container port
        pairs. Since the exposed ports are not available in the task information for Fargate, we assume that all the
        ports for the loadbalancers are open.

        Returns:
            Map where keys are tuple pair of container name and container port and values is a list of ip address and
            port pairs.
        """

        # Construct a map from container name to port.
        container_to_ports = defaultdict(list)
        for loadbalancer in loadbalancers:
            container_to_ports[loadbalancer['containerName']].append(loadbalancer['containerPort'])

        # Walk the tasks and construct the target info (IP address + exposed port).
        tasks = self.get_running_tasks()
        task_info = defaultdict(list)
        for task in tasks:
            for container in task['containers']:
                container_name = container['name']
                ports = container_to_ports[container_name]
                for network in container['networkInterfaces']:
                    for port in ports:
                        task_info[(container_name, port)].append({
                            'Id': network['privateIpv4Address'],
                            'Port': port,
                        })
        return task_info

    def __targets_contain_expected_target(self, expected_target, targets):
        # NOTE: We only match Id and Port. The rest of the fields are irrelevant in deciding if a task target is
        # registered to the LB.
        return expected_target in [{'Id': target['Target']['Id'], 'Port': target['Target']['Port']} for target in targets]
