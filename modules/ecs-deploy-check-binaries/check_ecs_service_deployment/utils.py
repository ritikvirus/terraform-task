from __future__ import print_function

import logging
import time
import boto3
from six.moves import zip_longest


logging.basicConfig()
logger = logging.getLogger("check_ecs_service_deployment")
logger.setLevel(logging.WARN)


def pause(t):
    """
    Sleep for `t` seconds while logging the fact.
    """
    logger.info('Retrying check in {} seconds...'.format(t))
    time.sleep(t)


def groups_of(iterable, n, padvalue=None):
    """
    Chunks the provided list into groups of `n` items.
    From: https://stackoverflow.com/a/312644
    """
    # `iter` creates a single iterator. We then repeat this iterator reference `n` times. We then expand that out in the
    # call to zip.
    # iterator = iter(iterable)
    # [iterator]*n = [iterator, iterator, iterator, ...]
    # zip_longest(*[iterator, iterator, ...]) = zip_longest(iterator, iterator, iterator, ...)
    # When we do this, the zip function will take the first element of each iterator to construct the first list. This
    # list will contain `n` elements because the iterator is repeated n times. However, because the iterator is shared,
    # each call as it moves through the list will be the next element from the previous call.
    return zip_longest(*[iter(iterable)]*n, fillvalue=padvalue)


def exceeded_timeout(start, timeout_seconds):
    """
    Given a start time and timeout_seconds, return if we reached the timeout
    """
    return (time.time() - start) > timeout_seconds


def get_events_for_service(aws_region, cluster_arn, service_arn):
    """
    Given an ECS service ARN and cluster ARN, return the last few event logs
    for that service.

    Args:
        aws_region -
            String representing AWS region where the service lives.
        cluster_arn -
            String representing ARN of the ECS cluster where the service lives.
        service_arn -
            String representing ARN of the ECS service.

    Returns:
        A list of up to 5 elements representing a ECS service
        log.
    """
    ecs_client = boto3.client('ecs', region_name=aws_region)
    services_response = ecs_client.describe_services(
            cluster=cluster_arn, services=[service_arn])
    services = services_response['services']
    if not services:
        return []

    service = services[0]
    return service['events'][:5]


LOG_LEVEL_MAP = {
    'info': logging.INFO,
    'warn': logging.WARNING,
    'error': logging.ERROR,
}


def set_log_level(loglevel):
    """
    Map a user friendly log level name to an internal logging
    level.
    """
    logger.setLevel(LOG_LEVEL_MAP[loglevel])
