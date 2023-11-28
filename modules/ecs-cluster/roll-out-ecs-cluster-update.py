import logging
import boto3
import time
import argparse
import math
import sys

logging.basicConfig()
logger = logging.getLogger()
logger.setLevel(logging.INFO)

SLEEP_BETWEEN_RETRIES_SEC = 10

"""Parse the arguments passed to this script
"""
def parse_args():
    parser = argparse.ArgumentParser(description='Roll out an update to an ECS Cluster Auto Scaling Group with zero downtime.')

    parser.add_argument('--asg-name', required=True, help='The name of the Auto Scaling Group')
    parser.add_argument('--cluster-name', required=True, help='The name of the ECS Cluster')
    parser.add_argument('--aws-region', required=True, help='The AWS region to use')
    parser.add_argument('--timeout', type=int, help='The maximum amount of time, in seconds, to wait for deployment to complete before timing out.', default=900)
    parser.add_argument('--keep-max-size', action='store_true', help='When passed in, do not expand the max size of the cluster, even if the cluster does not have enough capacity to double the current size.')

    return parser.parse_args()


"""The main entrypoint for this script, which does the following:

   1. Double the desired capacity of the ASG, which will cause Instances to deploy with the new launch template.
   2. Put all the old Instances in DRAINING state so all ECS Tasks are migrated off of them to the new Instances.
   3. Wait for all ECS Tasks to migrate off the old Instances.
   4. Set the desired capacity of the ASG back to its original value.
"""
def do_rollout():
    args = parse_args()

    session = boto3.session.Session(region_name=args.aws_region)
    ecs_client = session.client('ecs')
    asg_client = session.client('autoscaling')
    ec2_client = session.client('ec2')

    logger.info('Beginning roll out for ECS cluster %s in %s', args.cluster_name, args.aws_region)

    start = time.time()

    original_capacity, original_max_size = get_asg_capacity_and_max_size(asg_client, args.asg_name)
    instance_ids = get_ec2_instance_ids(asg_client, args.asg_name, original_capacity)

    update_asg(asg_client, args.asg_name, original_capacity, original_max_size, args.keep_max_size)
    container_instance_arns = get_container_instance_arns(ecs_client, args.cluster_name)
    put_container_instances_in_draining_state(ecs_client, args.cluster_name, container_instance_arns)
    wait_for_container_instances_to_drain(ecs_client, args.cluster_name, container_instance_arns, start, args.timeout)
    detach_and_terminate_instances(ec2_client, asg_client, args.asg_name, instance_ids)
    restore_asg(asg_client, args.asg_name, original_capacity, original_max_size)
    logger.info('Roll out for ECS cluster %s complete!', args.cluster_name)

"""Return the ASG information given its name.
"""
def get_asg_info(asg_client, asg_name):
    logger.info('Looking up info for ASG %s', asg_name)

    output = asg_client.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])

    asgs = output.get('AutoScalingGroups', [])
    if len(asgs) != 1:
        raise LookupError('Expected to find one Auto Scaling Group named %s but found %d' % (asg_name, len(asgs)))
    return asgs[0]



"""Return the desired capacity of an Auto Scaling Group.
"""
def get_asg_capacity_and_max_size(asg_client, asg_name):
    logger.info('Looking up size of ASG %s', asg_name)

    output = asg_client.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])

    asgs = output.get('AutoScalingGroups', [])
    if len(asgs) != 1:
        raise LookupError('Expected to find one Auto Scaling Group named %s but found %d' % (asg_name, len(asgs)))

    desired_capacity = asgs[0].get('DesiredCapacity')
    if desired_capacity is None:
        raise LookupError('Could not find a desired capacity for ASG %s', asg_name)

    max_size = asgs[0].get('MaxSize')
    if max_size is None:
        raise LookupError('Could not find a max_size for ASG %s', asg_name)

    return desired_capacity, max_size

"""
In case when desired_capacity * 2 > max_size - set max_size to desired_capacity * 2, and doubles desired_capacity
In case when desired_capacity * 2 =< max_size - doubles desired_capacity
"""
def update_asg(asg_client, asg_name, desired_capacity, max_size, keep_max_size):
    if not keep_max_size and desired_capacity * 2 > max_size:
        logger.info("Updating the max_size in order to expand the desired capacity")
        asg_client.update_auto_scaling_group(AutoScalingGroupName=asg_name, MaxSize=(desired_capacity * 2))
    logger.info("Updating %s desired_capacity to %d", asg_name, desired_capacity * 2)
    asg_client.set_desired_capacity(AutoScalingGroupName=asg_name, DesiredCapacity=desired_capacity * 2)

"""Set the desired capacity and max_size of an Auto Scaling Group.
"""
def restore_asg(asg_client, asg_name, desired_capacity, max_size):
    logger.info('Setting desired capacity of ASG %s to %d', asg_name, desired_capacity)
    asg_client.update_auto_scaling_group(AutoScalingGroupName=asg_name, DesiredCapacity=desired_capacity, MaxSize=max_size)


"""Detach the provided instances from the ASG, and then terminate the instances.
"""
def detach_and_terminate_instances(ec2_client, asg_client, asg_name, instance_ids):
    ec2_terminate_waiter = ec2_client.get_waiter('instance_terminated')

    logger.info('Detaching and terminating %d instances from ASG %s', len(instance_ids), asg_name)
    # Group the instances into 20 instance chunks, which is the max that the AWS API supports
    MAX_INSTANCES = 20
    max_batches = (len(instance_ids) / MAX_INSTANCES) + 1
    for i, grouped_instance_ids in enumerate(groups_of(instance_ids, MAX_INSTANCES)):
        logger.info('Processing batch %d/%d', i+1, max_batches)
        logger.info('Detaching instances from ASG')
        asg_client.detach_instances(
            InstanceIds=grouped_instance_ids,
            AutoScalingGroupName=asg_name,
            ShouldDecrementDesiredCapacity=True,
        )
        logger.info('Terminating instances from ASG')
        ec2_client.terminate_instances(InstanceIds=grouped_instance_ids)
        logger.info('Waiting for instances to terminate')
        ec2_terminate_waiter.wait(InstanceIds=grouped_instance_ids)
        logger.info('Done processing batch %d/%d', i+1, max_batches)


"""Get the Instance IDs of all the Instances in an ASG.
"""
def get_ec2_instance_ids(asg_client, asg_name, expected_count):
    logger.info('Looking up EC2 Instance IDs for ASG %s', asg_name)

    asg = get_asg_info(asg_client, asg_name)
    instances = asg.get('Instances', [])
    if len(instances) != expected_count:
        raise LookupError('Expected to find {} instances but found {}'.format(expected_count, len(instances)))
    return [instance['InstanceId'] for instance in instances]


"""Get the Instance ARNs of all the Instances in an ECS Cluster. Note that ECS Instance ARNs are NOT the same thing as
   EC2 Instance IDs.
"""
def get_container_instance_arns(ecs_client, cluster_name):
    logger.info('Looking up Cluster Instance ARNs for ECS cluster %s', cluster_name)
    arns = []
    nextToken = ''

    while True:
        cluster_instances = ecs_client.list_container_instances(cluster=cluster_name, nextToken=nextToken)
        arns.extend(cluster_instances['containerInstanceArns'])

        # If there are more than 100 instances in the cluster, the nextToken param can be used to paginate through them
        # all.
        nextToken = cluster_instances.get('nextToken')
        if not nextToken:
            return arns


"""Put ECS Instances in DRAINING state so that all ECS Tasks running on them are migrated to other Instances.
   Batches into chunks of 10 because of AWS api limitations (An error occurred InvalidParameterException when
   calling the UpdateContainerInstancesState operation: instanceIds can have at most 10 items)
"""
def put_container_instances_in_draining_state(ecs_client, cluster_name, container_instance_arns):
    batch_size = 10
    n_batches = math.ceil(len(container_instance_arns)/batch_size)
    for i in range(0, len(container_instance_arns), batch_size):
        logger.info('Putting batch %d/%d of container instances %s in cluster %s into DRAINING state', i+1, n_batches, container_instance_arns, cluster_name)
        ecs_client.update_container_instances_state(cluster=cluster_name, containerInstances=container_instance_arns[i:i + batch_size], status='DRAINING')


"""Wait until there are no more ECS Tasks running on any of the ECS Instances.
   Batches instances in groups of 100 because of AWS api limitations
   https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ecs.html#ECS.Client.describe_container_instances
"""
def wait_for_container_instances_to_drain(ecs_client, cluster_name, container_instance_arns, start, timeout):
    while not max_execution_time_exceeded(start, timeout):
        logger.info('Checking if all ECS Tasks have been drained from the ECS Instances in Cluster %s', cluster_name)

        batch_size = 100
        n_batches = math.ceil(len(container_instance_arns)/batch_size)
        responses = []
        for i in range(0, len(container_instance_arns), batch_size):
            logger.info('Fetching description of batch %d/%d of ECS Instances %s in Cluster %s', i+1, n_batches, container_instance_arns, cluster_name)
            responses.append(ecs_client.describe_container_instances(
                cluster=cluster_name,
                containerInstances=container_instance_arns[i:i + batch_size]
            ))

        if all_instances_fully_drained(responses):
            logger.info('All instances have been drained in Cluster %s!', cluster_name)
            return
        else:
            logger.info("Will sleep for %d seconds and check again", SLEEP_BETWEEN_RETRIES_SEC)
            time.sleep(SLEEP_BETWEEN_RETRIES_SEC)

    raise Exception('Maximum drain timeout of %s seconds has elapsed and instances are still draining.', timeout)


"""Return True if the amount of time since start has exceeded the timeout
"""
def max_execution_time_exceeded(start, timeout):
    now = time.time()
    elapsed = now - start
    return elapsed > timeout


"""Return True if the Instances in there are no more ECS Tasks running on the ECS Instances in the response from the
   describe_container_instances API
"""
def all_instances_fully_drained(describe_container_instances_responses):
    for response in describe_container_instances_responses:
        instances = response.get('containerInstances')
        if not instances:
            raise LookupError("The describe_container_instances returned no instances")

        for instance in instances:
            if not instance_fully_drained(instance):
                return False

    return True


"""Return True if the given Instance, as returned by the describe_container_instances API, has no more ECS Tasks
   running on it.
"""
def instance_fully_drained(instance):
    instance_arn = instance.get('containerInstanceArn')

    if instance.get('status') == 'ACTIVE':
        logger.info('The ECS Instance %s is still in ACTIVE status', instance_arn)
        return False


    if instance.get('pendingTasksCount') > 0:
        logger.info('The ECS Instance %s still has pending tasks', instance_arn)
        return False

    if instance.get('runningTasksCount') > 0:
        logger.info('The ECS Instance %s still has running tasks', instance_arn)
        return False

    return True


"""Split given list into groups of n collections.
   Obtained from: https://stackoverflow.com/questions/1624883/alternative-way-to-split-a-list-into-groups-of-n
"""
def groups_of(collection, n):
    if sys.version_info > (3,):
        from itertools import zip_longest as izip_longest
    else:
        from itertools import izip_longest

    # This works by creating an iterator out of the collection, then duplicating that n times. Then, passing all the
    # elements to zip. The effect is that zip will iterate over the same iterator as it zips of the n collections,
    # thereby creating groups of n elements from the original list.
    # NOTE: izip_longest will pad the list with None to fit the size (`n`), so we filter out the Nones before returning.
    n_iter = (iter(collection),) * n
    return [[i for i in lst if i is not None] for lst in izip_longest(*n_iter)]


if __name__ == '__main__':
    do_rollout()
