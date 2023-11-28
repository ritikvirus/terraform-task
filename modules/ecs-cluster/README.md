# ECS Cluster Module

This Terraform Module launches an [EC2 Container Service
Cluster](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_clusters.html) that you can use to run
Docker containers and services (see the [ecs-service module](/modules/ecs-service/README.adoc)).

**WARNING: Launch Configurations:** [Launch configurations](https://docs.aws.amazon.com/autoscaling/ec2/userguide/launch-configurations.html) are being phased out in favor of [Launch Templates](https://docs.aws.amazon.com/autoscaling/ec2/userguide/launch-templates.html). Before upgrading to the latest release please be sure to test and plan any changes to infrastructure that may be impacted. Launch templates are being introduced in [PR #371](https://github.com/gruntwork-io/terraform-aws-ecs/pull/371)

## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [examples](/examples) folder for example usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See the [ecs-service module](/modules/ecs-service/README.adoc) for how to run Docker containers across this cluster.

## What is an ECS Cluster?

To use ECS with the EC2 launch type, you first deploy one or more EC2 Instances into a "cluster". The ECS scheduler can
then deploy Docker containers across any of the instances in this cluster. Each instance needs to have the [Amazon ECS
Agent](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_agent.html) installed so it can communicate with
ECS and register itself as part of the right cluster.

## How do you run Docker containers on the cluster?

See the [service module](/modules/ecs-service/README.adoc).

## How do you add additional security group rules?

To add additional security group rules to the EC2 Instances in the ECS cluster, you can use the
[aws_security_group_rule](https://www.terraform.io/docs/providers/aws/r/security_group_rule.html) resource, and set its
`security_group_id` argument to the Terraform output of this module called `ecs_instance_security_group_id`. For
example, here is how you can allow the EC2 Instances in this cluster to allow incoming HTTP requests on port 8080:

```hcl
module "ecs_cluster" {
  # (arguments omitted)
}

resource "aws_security_group_rule" "allow_inbound_http_from_anywhere" {
  type = "ingress"
  from_port = 8080
  to_port = 8080
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${module.ecs_cluster.ecs_instance_security_group_id}"
}
```

**Note**: The security group rules you add will apply to ALL Docker containers running on these EC2 Instances. There is
currently no way in ECS to manage security group rules on a per-Docker-container basis.

## How do you add additional IAM policies?

To add additional IAM policies to the EC2 Instances in the ECS cluster, you can use the
[aws_iam_role_policy](https://www.terraform.io/docs/providers/aws/r/iam_role_policy.html) or
[aws_iam_policy_attachment](https://www.terraform.io/docs/providers/aws/r/iam_policy_attachment.html) resources, and
set the IAM role id to the Terraform output of this module called `ecs_instance_iam_role_name` . For example, here is how
you can allow the EC2 Instances in this cluster to access an S3 bucket:

```hcl
module "ecs_cluster" {
  # (arguments omitted)
}

resource "aws_iam_role_policy" "access_s3_bucket" {
    name = "access_s3_bucket"
    role = "${module.ecs_cluster.ecs_instance_iam_role_name}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect":"Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::examplebucket/*"
    }
  ]
}
EOF
}
```

**Note**: The IAM policies you add will apply to ALL Docker containers running on these EC2 Instances. There is
currently no way in ECS to manage IAM policies on a per-Docker-container basis.

## How do you make changes to the EC2 Instances in the cluster?

To deploy an update to an ECS Service, see the [ecs-service module](/modules/ecs-service). To deploy an update to the
EC2 Instances in your ECS cluster, such as a new AMI, read on.

Terraform and AWS do not provide a way to automatically roll out a change to the Instances in an ECS Cluster. Due to
Terraform limitations (see [here for a discussion](https://github.com/gruntwork-io/terraform-aws-ecs/pull/29)), there is
currently no way to implement this purely in Terraform code. Therefore, we've created a script called
`roll-out-ecs-cluster-update.py` that can do a zero-downtime roll out for you.

### How to use the roll-out-ecs-cluster-update.py script

First, make sure you have the latest version of the [AWS Python SDK (boto3)](https://github.com/boto/boto3) installed
(e.g. `pip3 install boto3`).

To deploy a change such as rolling out a new AMI to all ECS Instances:

1. Make sure the `cluster_max_size` is at least twice the size of `cluster_min_size`. The extra capacity will be used
   to deploy the updated instances.
1. Update the Terraform code with your changes (e.g. update the `cluster_instance_ami` variable to a new AMI).
1. Run `terraform apply`.
1. Run the script:

    ```
    python3 roll-out-ecs-cluster-update.py --asg-name ASG_NAME --cluster-name CLUSTER_NAME --aws-region AWS_REGION
    ```

    If you have your output variables configured as shown in [outputs.tf](/examples/docker-service-with-elb/outputs.tf)
    of the [docker-service-with-elb example](/examples/docker-service-with-elb), you can use the `terraform output`
    command to fill in most of the arguments automatically:

    ```
    python3 roll-out-ecs-cluster-update.py \
      --asg-name $(terragrunt output -no-color asg_name) \
      --cluster-name $(terragrunt output -no-color ecs_cluster_name) \
      --aws-region $(terragrunt output -no-color aws_region)
    ```

**Note**: during upgrade, if `desired_capacity * 2 > max_size` then ASG max size will be updated to `desired_capacity * 2` for the period of upgrade, to disable this behaviour - pass `--keep-max-size` argument.

To avoid the need to install python dependencies on your local machine, you may choose to use Docker.

1. Navigate to the directory that you have downloaded `roll-out-ecs-cluster-update.py`:
2. If you use [aws-vault](https://github.com/99designs/aws-vault), you can run the following to make your aws
   credentials available to the container. If you do not use `aws-vault`, you will have to manually use the `--env`
   option of `docker run`

    ```
    docker run \
        -it --rm -v "$PWD":/usr/src -w /usr/src \
        --env-file <(aws-vault exec --assume-role-ttl=1h PROFILE -- env | grep AWS) \
        python:3.10-alpine \
        sh -c "pip3 install boto3 && python3 roll-out-ecs-cluster-update.py \
        --asg-name ASG_NAME \
        --cluster-name CLUSTER_NAME \
        --aws-region AWS_REGION"
    ```

### How roll-out-ecs-cluster-update.py works

The `roll-out-ecs-cluster-update.py` script does the following:

1. Double the desired capacity of the Auto Scaling Group that powers the ECS Cluster. This causes EC2 Instances to
   deploy with the new launch template.
1. Put all the old ECS Instances in DRAINING state so all ECS Tasks are migrated to the new Instances.
1. Wait for all ECS Tasks to migrate to the new Instances.
1. Detach the now drained instances from the Auto Scaling Group, decrementing the desired capacity back to the original value.


## How do you configure cluster autoscaling?

ECS Clusters support two tiers of autoscaling:

- Autoscaling of ECS Service and Tasks, where ECS will horizontally or vertically scale your ECS Tasks by provisioning
  more replicas of the Task or replacing them with Tasks that have more resources allocated to it.
- Autoscaling of the ECS Cluster, where the AWS Autoscaling Group will horizontally scale the worker nodes by
  provisioning more.

The `ecs-cluster` module supports configuring ECS Cluster Autoscaling by leveraging [ECS Capacity
Providers](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-capacity-providers.html). You can read
more about how cluster autoscaling works with capacity providers in the [official
documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html).

To enable capacity providers for cluster autoscaling on your ECS cluster, you will want to configure the following
variables:

```hcl
# Turn on capacity providers for autoscaling
capacity_provider_enabled = true

# Enable Multi AZ capacity providers to balance autoscaling load across AZs. This should be true in production. Can be
# false in dev and stage.
multi_az_capacity_provider = true

# Configure target utilization for the ECS cluster. This number influences when scale out happens, and when instances
# should be scaled in. For example, a setting of 90 means that new instances will be provisioned when all instances are
# at 90% utilization, while instances that are only 10% utilized (CPU and Memory usage from tasks = 10%) will be scaled
# in. A recommended default to start with is 90.
capacity_provider_target = 90

# The following are optional configurations, and configures how many instances should be scaled out or scaled in at one
# time. Defaults to 1.
# capacity_provider_max_scale_step = 1
# capacity_provider_min_scale_step = 1
```

### Note on toggling capacity providers on existing ECS Clusters

Each EC2 instance must be registered with Capacity Providers to be considered in the pool. This means that when you
enable Capacity Providers on an existing ECS cluster that did not have Capacity Providers, you must rotate the EC2
instances to ensure all the instances get associated with the new Capacity Provider.

To rotate the instances, you can run the
[roll-out-ecs-cluster-update.py](/modules/ecs-cluster/roll-out-ecs-cluster-update.py)
script in the `terraform-aws-ecs` module. Refer to the
[documentation](#how-do-you-make-changes-to-the-ec2-instances-in-the-cluster)
for more information on the script.
