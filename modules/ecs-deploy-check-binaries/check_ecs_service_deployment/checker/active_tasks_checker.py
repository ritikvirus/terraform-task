from .. import utils
from .base import ECSDeployCheckerBase


class ECSDeployActiveTasksChecker(ECSDeployCheckerBase):
    def run(self):
        """
        Execute check for ECS deployment, which validates that the right
        version of the task was deployed to the ECS cluster.

        Returns:
            A tuple pair of boolean and string, where the boolean indicates
            whether or not the check passed, and the string represents an error
            reason if it failed.
        """
        utils.logger.info('Checking whether or not task has been deployed and is active')
        passed = self.check_until_consecutive_successes(self.check_task_is_active)
        if not passed:
            utils.logger.info('ECS deployment check timedout waiting for task to be active')
            return False, 'Timedout waiting for task to be active'

        utils.logger.info('Passed active task check')
        return True, ''

    def check_task_is_active(self):
        """
        Verify that there are more active tasks on the service
        than what is expected.
        """
        running_tasks = self.get_running_tasks()
        return len(running_tasks) >= self.min_active_task_count
