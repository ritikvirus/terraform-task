from .. import utils
from .base import ECSDeployCheckerBase


class ECSDeployDaemonServiceChecker(ECSDeployCheckerBase):
    def run(self):
        """
        Execute check for daemon services, validating that there is an instance
        of the given task definition running on each container instance of the
        cluster.

        Returns:
            A tuple pair of boolean and string, where the boolean indicates
            whether or not the check passed, and the string represents an error
            reason if it failed.
        """
        utils.logger.info('Checking whether or not daemon service has been fully deployed and is active')
        passed = self.check_until_consecutive_successes(self.check_daemon_service_is_fully_deployed)
        if not passed:
            utils.logger.info('ECS deployment check timedout waiting for daemon service to be active')
            return False, 'Timedout waiting for daemon service to be active'

        utils.logger.info('Passed daemon service check')
        return True, ''

    def check_daemon_service_is_fully_deployed(self):
        """
        Check if all container instances are running the task of the daemon ECS service.
        """
        container_instances = self.ecs_client.list_container_instances(cluster=self.ecs_cluster_arn)
        container_instance_arns = set(container_instances['containerInstanceArns'])
        running_tasks = self.get_running_tasks()
        container_instances_running_task = set([task['containerInstanceArn'] for task in running_tasks])
        return (
            container_instance_arns and
            container_instances_running_task and
            container_instance_arns == container_instances_running_task)
