# ECS Daemon Service Module

This Terraform Module creates an [ECS Daemon Service](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html)
that you can use to deploy exactly one task on each active container instance that meets all of the task placement constraints
specified in your cluster.

## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See the [ecs-cluster module](../ecs-cluster) for how to run an ECS cluster.
* This module uses the `ecs-deployment-check` binary available
  under
  [ecs-deploy-check-binaries](../ecs-deploy-check-binaries) to
  have a more robust check for the service deployment. You
  must have `python` installed before you can use this check.
  See the binary [README](../ecs-deploy-check-binaries) for
  more information. You can disable the check by setting the
  module variable `enable_ecs_deployment_check` to `false`.


## What is an ECS Daemon Service?

To run Docker daemon containers with ECS, you first define an [ECS
Task](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_defintions.html), which is a JSON file that
describes what container(s) to run, the resources (memory, CPU) those containers need, the volumes to mount, the
environment variables to set, and so on. To actually run an ECS Task, you define an ECS Daemon Service, which will:

1. Deploy exactly one task on each active container instance.
1. Restart tasks if they fail.

## How do you create an ECS cluster?

To use ECS, you first deploy one or more EC2 Instances into a "cluster". See the [ecs-cluster module](../ecs-cluster)
for how to create a cluster.

## How do you add additional IAM policies?

If you associate this ECS Service with a single ELB, then we create an IAM Role and
associated IAM Policies that allow the ECS Service to talk to the ELB. To add additional IAM policies to this IAM Role,
you can use the [aws_iam_role_policy](https://www.terraform.io/docs/providers/aws/r/iam_role_policy.html) or
[aws_iam_policy_attachment](https://www.terraform.io/docs/providers/aws/r/iam_policy_attachment.html) resources, and
set the IAM role id to the Terraform output of this module called `service_iam_role_id` . For example, here is how
you can allow the ECS Service in this cluster to access an S3 bucket:

```hcl
module "ecs_daemon_service" {
  # (arguments omitted)
}

resource "aws_iam_role_policy" "access_s3_bucket" {
    name = "access_s3_bucket"
    role = "${module.ecs_daemon_service.service_iam_role_arn}"
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
