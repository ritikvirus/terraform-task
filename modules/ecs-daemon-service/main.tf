# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE AN ECS CONTAINER DAEMON SERVICE
# These templates create an ECS Daemon Service which runs one or more related Docker containers in fault-tolerant way. This
# includes:
# - The ECS Service itself
# - An optional association with an Elastic Load Balancer (ELB)
# - IAM roles and policies
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    # This module has only been tested with 2.X series of provider
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.75.1, < 6.0.0"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS DAEMON SERVICE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ecs_service" "daemon_service" {
  name            = var.service_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.task.arn
  launch_type     = var.launch_type

  # The reseaon why we have a separate module for DAEMON is discussed here:
  # https://github.com/gruntwork-io/terraform-aws-ecs/issues/77
  #
  # TLDR: introducing the DAEMON in the other ecs modules would cause breaking changes
  # and lots of conditional logic.
  scheduling_strategy = "DAEMON"

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  placement_constraints {
    type       = var.placement_constraint_type
    expression = var.placement_constraint_expression
  }

  tags           = merge(var.custom_tags, var.service_tags)
  propagate_tags = var.propagate_tags

  wait_for_steady_state = var.wait_for_steady_state

  dynamic "deployment_controller" {
    for_each = var.deployment_controller != null ? [var.deployment_controller] : []
    content {
      type = var.deployment_controller
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS TASK DEFINITION
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "task" {
  family                = var.service_name
  container_definitions = var.ecs_task_container_definitions
  task_role_arn         = aws_iam_role.ecs_task.arn
  execution_role_arn    = aws_iam_role.ecs_task_execution_role.arn
  network_mode          = var.ecs_task_definition_network_mode
  pid_mode              = var.ecs_task_definition_pid_mode

  tags = merge(var.custom_tags, var.task_definition_tags)

  dynamic "volume" {
    for_each = var.volumes

    content {
      name      = volume.key
      host_path = lookup(volume.value, "host_path", null)

      dynamic "docker_volume_configuration" {
        # The contents of the for_each don't matter; all the matters is if we have it once or not at all.
        for_each = lookup(volume.value, "docker_volume_configuration", null) == null ? [] : ["once"]

        content {
          autoprovision = lookup(volume.value["docker_volume_configuration"], "autoprovision", null)
          driver        = lookup(volume.value["docker_volume_configuration"], "driver", null)
          driver_opts   = lookup(volume.value["docker_volume_configuration"], "driver_opts", null)
          labels        = lookup(volume.value["docker_volume_configuration"], "labels", null)
          scope         = lookup(volume.value["docker_volume_configuration"], "scope", null)
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS TASK ROLE
# ---------------------------------------------------------------------------------------------------------------------

# Create the ECS Task IAM Role
resource "aws_iam_role" "ecs_task" {
  name                 = "${local.task_iam_role_name_prefix}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_task.json
  permissions_boundary = var.task_role_permissions_boundary_arn
  tags                 = var.custom_tags

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the ECS task cannot be
  # created because the IAM role does not exist. We add a 15 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 15 seconds to wait for IAM role to be created'; sleep 15"
  }
}

# Define the Assume Role IAM Policy Document for the ECS Service Scheduler IAM Role
data "aws_iam_policy_document" "ecs_task" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = concat(["ecs-tasks.amazonaws.com"], var.additional_task_assume_role_policy_principals)
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN IAM POLICY AND EXECUTION ROLE TO ALLOW ECS TASK TO MAKE CLOUDWATCH REQUESTS AND PULL IMAGES FROM ECR
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution_role" {
  name                 = "${local.task_execution_name_prefix}-task-execution-role"
  assume_role_policy   = data.aws_iam_policy_document.ecs_task.json
  permissions_boundary = var.task_execution_role_permissions_boundary_arn
  tags                 = var.custom_tags

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the ECS task cannot be
  # created because the IAM role does not exist. We add a 15 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 15 seconds to wait for IAM role to be created'; sleep 15"
  }
}

resource "aws_iam_policy" "ecs_task_execution_policy" {
  name   = "${local.task_execution_name_prefix}-task-excution-policy"
  policy = data.aws_iam_policy_document.ecs_task_execution_policy_document.json
}

data "aws_iam_policy_document" "ecs_task_execution_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy_attachment" "task_execution_policy_attachment" {
  name       = "${local.task_execution_name_prefix}-task-execution"
  policy_arn = aws_iam_policy.ecs_task_execution_policy.arn
  roles      = [aws_iam_role.ecs_task_execution_role.name]
}

# ---------------------------------------------------------------------------------------------------------------------
# COMPUTE TEMPORARY VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

locals {
  task_execution_name_prefix = var.custom_task_execution_name_prefix == null ? var.service_name : var.custom_task_execution_name_prefix
  task_iam_role_name_prefix  = var.custom_iam_role_name_prefix == null ? var.service_name : var.custom_iam_role_name_prefix
}

# ---------------------------------------------------------------------------------------------------------------------
# CHECK THE ECS SERVICE DEPLOYMENT
# ---------------------------------------------------------------------------------------------------------------------

data "aws_arn" "ecs_service" {
  arn = aws_ecs_service.daemon_service.id
}

resource "null_resource" "ecs_deployment_check" {
  count = var.enable_ecs_deployment_check ? 1 : 0

  triggers = {
    ecs_service_arn         = aws_ecs_service.daemon_service.id
    ecs_task_definition_arn = aws_ecs_service.daemon_service.task_definition
  }

  provisioner "local-exec" {
    command = <<EOF
${module.ecs_deployment_check_bin.path} \
  --loglevel ${var.deployment_check_loglevel} \
  --ecs-cluster-arn ${var.ecs_cluster_arn} \
  --ecs-service-arn ${aws_ecs_service.daemon_service.id} \
  --ecs-task-definition-arn ${aws_ecs_task_definition.task.arn} \
  --aws-region ${data.aws_arn.ecs_service.region} \
  --check-timeout-seconds ${var.deployment_check_timeout_seconds} \
  --daemon-check --no-loadbalancer
EOF

  }
}

# Build the path to the deployment check binary
module "ecs_deployment_check_bin" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-utilities.git//modules/join-path?ref=v0.9.4"

  path_parts = [path.module, "..", "ecs-deploy-check-binaries", "bin", "check-ecs-service-deployment"]
}
