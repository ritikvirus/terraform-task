#!/bin/bash
#
# This script is meant to be run in the User Data of each ECS instance. It registers the instance with the proper
# ECS cluster and authenticates it with the proper private Docker repo. Note, this script assumes it is running in the
# AMI built from the /examples/example-ecs-instance-ami/build.json Packer template.

set -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# These variables are filled in by Terraform interpolation
/usr/local/bin/configure-ecs-instance --ecs-cluster-name "${ecs_cluster_name}"