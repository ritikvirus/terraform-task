import time
import boto3

from .. import utils
from .. import exceptions


class ECSDeployCheckerBase(object):
    """
    Base class for implementing ECS deployment checkers.

    Each check should extend this class and implement the
    `run` method that will execute the check.
    """
    PAUSE_SECONDS = 5

    def __init__(
            self,
            aws_region,
            ecs_cluster_arn,
            ecs_service_arn,
            ecs_task_definition_arn,
            check_timeout_seconds,
            min_active_task_count):
        self.elb_client = boto3.client('elbv2', region_name=aws_region)
        self.ecs_client = boto3.client('ecs', region_name=aws_region)
        self.ecs_service_arn = ecs_service_arn
        self.ecs_cluster_arn = ecs_cluster_arn
        self.ecs_task_definition_arn = ecs_task_definition_arn
        self.min_active_task_count = min_active_task_count
        self.check_timeout_seconds = check_timeout_seconds

    def run(self):
        """
        Override this method with the code for executing the
        actual `check`.

        Returns:
            A tuple of (bool, str), where the first element
            signals whether or not the check was successful
            and the second element is a friendly error
            message that describes why the check failed, if
            it did.
        """
        raise NotImplementedError

    def check_until_consecutive_successes(
            self, check_func, required_consecutive_successes=3):
        """
        Execute the given `check_func` until it passes
        `required_consecutive_successes` consecutive times

        Args:
            check_func -
              A function that accepts no arguments and returns
              a bool indicating whether or not a check was
              successful.
            required_consecutive_successes -
              The number of times a check must pass before the
              check is considered successful.

        Returns:
            bool indicating whether or not the check was
            successful.
        """
        consecutive_success = 0
        start = time.time()
        while consecutive_success < required_consecutive_successes:
            success = False
            try:
                success = check_func()
            except Exception:
                utils.logger.exception("Check function encountered an error: Treating as a failed check")

            if success:
                consecutive_success += 1
                utils.logger.info(
                    'Passed check {}/{} times'
                    .format(consecutive_success, required_consecutive_successes))
            else:
                # Reset on failure
                consecutive_success = 0
                utils.logger.info(
                    'Failed check. Resetting counter from {} consecutive successes'
                    .format(consecutive_success))

            # check if we passed the timeout, erroring out if we have
            if utils.exceeded_timeout(start, self.check_timeout_seconds):
                return False

            # Add a pause to buffer the next check
            utils.pause(self.PAUSE_SECONDS)
        return True

    def get_service(self):
        services_response = self.ecs_client.describe_services(
                cluster=self.ecs_cluster_arn, services=[self.ecs_service_arn])
        services = services_response['services']
        if services:
            return services[0]
        raise exceptions.DeployCheckException(
            'No ECS service found with name "{}"'.format(self.ecs_service_arn))

    def get_running_tasks(self):
        tasks = self.ecs_client.list_tasks(
            cluster=self.ecs_cluster_arn,
            serviceName=self.ecs_service_arn)
        if not tasks['taskArns']:
            utils.logger.info('Found no tasks for service {}'.format(self.ecs_service_arn))
            return []

        task_descriptions = self.ecs_client.describe_tasks(
            cluster=self.ecs_cluster_arn,
            tasks=tasks['taskArns'])['tasks']
        active_task_descriptions = [
            task for task in task_descriptions
            if task['lastStatus'] == 'RUNNING'
        ]
        related_active_tasks = [
            task for task in active_task_descriptions
            if task['taskDefinitionArn'] == self.ecs_task_definition_arn
        ]

        utils.logger.info(
            'Found {} active tasks (of {} tasks) for service {}'
            .format(len(active_task_descriptions), len(task_descriptions), self.ecs_service_arn))
        utils.logger.info(
            'Found {} active tasks for task definition {}'.format(len(related_active_tasks), self.ecs_service_arn))

        return related_active_tasks
