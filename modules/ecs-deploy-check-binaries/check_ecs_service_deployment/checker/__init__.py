from .active_tasks_checker import ECSDeployActiveTasksChecker
from .daemon_service_checker import ECSDeployDaemonServiceChecker
from .loadbalancer_checker import ECSDeployLoadbalancerChecker


def run_checks(
        aws_region,
        ecs_cluster_arn,
        ecs_service_arn,
        ecs_task_definition_arn,
        check_timeout_seconds,
        min_active_task_count,
        is_daemon_check,
        include_loadbalancer):
    """
    The main checker function.

    Constructs the respective checker objects and implements
    the logic for chaining checks together based on
    parameters.

    Returns:
        A tuple of (bool, str), where the first element
        signals whether or not the check was successful and
        the second element is a friendly error message that
        describes why the check failed, if it did.
    """
    deploy_checker_constructor_args = (
        aws_region,
        ecs_cluster_arn,
        ecs_service_arn,
        ecs_task_definition_arn,
        check_timeout_seconds,
        min_active_task_count,
    )
    if is_daemon_check:
        checkers = [
            ECSDeployDaemonServiceChecker(*deploy_checker_constructor_args),
        ]
    elif include_loadbalancer:
        checkers = [
            ECSDeployActiveTasksChecker(*deploy_checker_constructor_args),
            ECSDeployLoadbalancerChecker(*deploy_checker_constructor_args),
        ]
    else:
        checkers = [
            ECSDeployActiveTasksChecker(*deploy_checker_constructor_args),
        ]

    for checker in checkers:
        was_successful, err_msg = checker.run()
        if not was_successful:
            return False, err_msg
    return True, ""
