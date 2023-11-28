from __future__ import print_function

import json
import click
import os
import sys


# Extend the PYTHONPATH to include the module directory so that the library code can be imported
BINARY_SOURCE_DIR = os.path.dirname(os.path.realpath(__file__))
MODULE_DIR = os.path.dirname(BINARY_SOURCE_DIR)
sys.path.append(MODULE_DIR)


from check_ecs_service_deployment import utils, exceptions
from check_ecs_service_deployment.checker import run_checks


@click.command()
@click.option(
    '--loglevel',
    default='info',
    type=click.Choice(list(utils.LOG_LEVEL_MAP.keys())))
@click.option(
    '--aws-region',
    default='us-east-1',
    help='AWS region where the resources are located. (Default: us-east-1)')
@click.option(
    '--ecs-cluster-arn',
    required=True,
    help='ARN of the ECS cluster to check.')
@click.option(
    '--ecs-service-arn',
    required=True,
    help='ARN of the ECS service to check.')
@click.option(
    '--ecs-task-definition-arn',
    required=True,
    help='ARN of the ECS task definition that is expected to be active on the service.')
@click.option(
    '--check-timeout-seconds',
    default=600,
    type=int,
    help='How many seconds to try polling that the service was deployed before failing the check. (Default: 600)')
@click.option(
    '--min-active-task-count',
    type=int,
    default=1,
    help='Minimum number of active tasks to expect for declaring a successful deployment of the service. (Default: 1)')
@click.option(
    '--daemon-check/--no-daemon-check',
    default=False,
    help='Whether or not this is a daemon service check. (Default: --no-daemon-check)')
@click.option(
    '--loadbalancer/--no-loadbalancer',
    default=True,
    help='Whether or not to include check for ALB/NLB health checks. (Default: --loadbalancer)')
def check_ecs_service_deployment(
        loglevel,
        aws_region,
        ecs_cluster_arn,
        ecs_service_arn,
        ecs_task_definition_arn,
        check_timeout_seconds,
        min_active_task_count,
        daemon_check,
        loadbalancer):
    """
    Validate that the specified ECS service is actively servicing the specified
    ECS task definition and is passing health checks.

    The check will fail if it does not detect that the task has been deployed
    within the provided timeout limit.
    """
    utils.set_log_level(loglevel)
    try:
        was_deployed_successfully, error_msg = run_checks(
            aws_region,
            ecs_cluster_arn,
            ecs_service_arn,
            ecs_task_definition_arn,
            check_timeout_seconds,
            min_active_task_count,
            daemon_check,
            loadbalancer)
    except exceptions.DeployCheckException as exc:
        # Translate to ClickException for better error message formatting
        raise click.ClickException(exc.msg)

    if not was_deployed_successfully:
        events = utils.get_events_for_service(
                aws_region, ecs_cluster_arn, ecs_service_arn)
        for ev in events:
            # TODO: format error message better
            utils.logger.error('{} {}'.format(ev['createdAt'].isoformat(), ev['message']))
        raise click.ClickException(error_msg)

    print(json.dumps({'success': '1'}))


if __name__ == '__main__':
    check_ecs_service_deployment()
