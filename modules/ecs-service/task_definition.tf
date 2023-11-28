# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS TASK DEFINITION
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "task" {
  family                = var.service_name
  container_definitions = var.ecs_task_container_definitions
  task_role_arn         = local.ecs_task_role_arn
  execution_role_arn    = local.ecs_task_execution_role_arn
  network_mode          = var.ecs_task_definition_network_mode

  # Add support to run Graviton instances
  dynamic "runtime_platform" {
    for_each = var.runtime_platform == null ? [] : [var.runtime_platform]
    content {
      operating_system_family = runtime_platform.value["operating_system_family"]
      cpu_architecture        = runtime_platform.value["cpu_architecture"]
    }
  }

  # For FARGATE, these options must be defined here and not in the container definition file
  requires_compatibilities = local.is_fargate ? ["FARGATE"] : null
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  dynamic "ephemeral_storage" {
    for_each = var.task_ephemeral_storage == null ? [] : [var.task_ephemeral_storage]
    content {
      size_in_gib = var.task_ephemeral_storage
    }
  }

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

  dynamic "volume" {
    for_each = var.efs_volumes
    content {
      name = volume.key

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = lookup(volume.value, "root_directory", null)
        transit_encryption      = lookup(volume.value, "transit_encryption", null)
        transit_encryption_port = lookup(volume.value, "transit_encryption_port", null)
        authorization_config {
          access_point_id = lookup(volume.value, "access_point_id", null)
          iam             = lookup(volume.value, "iam", null)
        }
      }
    }
  }

  dynamic "proxy_configuration" {
    for_each = var.proxy_configuration == null ? [] : [var.proxy_configuration]

    content {
      type           = proxy_configuration.value["type"]
      container_name = proxy_configuration.value["container_name"]
      properties     = proxy_configuration.value["properties"]
    }
  }

  tags = var.task_definition_tags
}

# Create a dedicated ECS Task specially for our canaries
resource "aws_ecs_task_definition" "task_canary" {
  # This count parameter ensures we only create this resource if the user has requested at least one canary ECS Task to run.
  count = local.has_canary ? 1 : 0

  family                = var.service_name
  container_definitions = var.ecs_task_definition_canary
  task_role_arn         = local.ecs_task_role_arn
  execution_role_arn    = local.ecs_task_execution_role_arn
  network_mode          = var.ecs_task_definition_network_mode

  # For FARGATE, these options must be defined here and not in the container definition file
  requires_compatibilities = local.is_fargate ? ["FARGATE"] : null
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  dynamic "ephemeral_storage" {
    for_each = var.task_ephemeral_storage == null ? [] : [var.task_ephemeral_storage]
    content {
      size_in_gib = var.task_ephemeral_storage
    }
  }

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

  dynamic "volume" {
    for_each = var.efs_volumes
    content {
      name = volume.key

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = lookup(volume.value, "root_directory", null)
        transit_encryption      = lookup(volume.value, "transit_encryption", null)
        transit_encryption_port = lookup(volume.value, "transit_encryption_port", null)
        authorization_config {
          access_point_id = lookup(volume.value, "access_point_id", null)
          iam             = lookup(volume.value, "iam", null)
        }
      }
    }
  }

  dynamic "proxy_configuration" {
    for_each = var.proxy_configuration == null ? [] : [var.proxy_configuration]

    content {
      type           = proxy_configuration.value["type"]
      container_name = proxy_configuration.value["container_name"]
      properties     = proxy_configuration.value["properties"]
    }
  }

  tags = var.task_definition_tags

  # This is a workaround for a an issue where AWS will reject updates made to the same task family that occur too closely together. By depending on the aws_ecs_task_definition.task resource, we effectively wait to create the canary task until the primary task has been successfully created.
  depends_on = [aws_ecs_task_definition.task]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS TASK IAM ROLE
# Per https://goo.gl/xKpEOp, the ECS Task IAM Role is where arbitrary IAM Policies (permissions) will be attached to
# support the unique needs of the particular ECS Service being created. Because the necessary IAM Policies depend on the
# particular ECS Service, we create the IAM Role here, but the permissions will be attached in the Terraform template
# that consumes this module.
# ---------------------------------------------------------------------------------------------------------------------
# Use existing ECS Task IAM Role; data aws_iam_role are always looked up by 'name':
data "aws_iam_role" "ecs_task" {
  count = var.existing_ecs_task_role_name == null ? 0 : 1
  name  = var.existing_ecs_task_role_name
}

# ... or create a new ECS Task IAM Role if none was passed in
resource "aws_iam_role" "ecs_task" {
  count                = var.existing_ecs_task_role_name == null ? 1 : 0
  name                 = "${local.iam_role_prefix}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_task.json
  permissions_boundary = var.task_role_permissions_boundary_arn

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
# Use existing ECS Task IAM Role; data aws_iam_role are always looked up by 'name':
data "aws_iam_role" "ecs_task_execution_role" {
  count = var.existing_ecs_task_execution_role_name == null ? 0 : 1
  name  = var.existing_ecs_task_execution_role_name
}

# ... or create a new role if none was passed in
resource "aws_iam_role" "ecs_task_execution_role" {
  count                = var.existing_ecs_task_execution_role_name == null ? 1 : 0
  name                 = "${local.task_execution_name_prefix}-task-execution-role"
  assume_role_policy   = data.aws_iam_policy_document.ecs_task.json
  permissions_boundary = var.task_execution_role_permissions_boundary_arn

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the ECS task cannot be
  # created because the IAM role does not exist. We add a 15 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 15 seconds to wait for IAM role to be created'; sleep 15"
  }
}

resource "aws_iam_policy" "ecs_task_execution_policy" {
  count  = var.existing_ecs_task_execution_role_name == null ? 1 : 0
  name   = "${local.task_execution_name_prefix}-task-execution-policy"
  policy = data.aws_iam_policy_document.ecs_task_execution_policy_document[0].json
}

data "aws_iam_policy_document" "ecs_task_execution_policy_document" {
  count = var.existing_ecs_task_execution_role_name == null ? 1 : 0
  statement {
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy_attachment" "task_execution_policy_attachment" {
  count      = var.existing_ecs_task_execution_role_name == null ? 1 : 0
  name       = "${local.task_execution_name_prefix}-task-execution"
  policy_arn = aws_iam_policy.ecs_task_execution_policy[0].arn
  roles      = [local.ecs_task_execution_role_name]
}

locals {
  # Since we cannot set default variables values that include other variables (e.g. variable default values cannot be interpolated),
  # we use a local as a workaround.
  iam_role_prefix            = var.custom_iam_role_name_prefix != null ? var.custom_iam_role_name_prefix : var.service_name
  task_execution_name_prefix = var.custom_task_execution_name_prefix != null ? var.custom_task_execution_name_prefix : var.service_name

  ecs_task_role_arn  = var.existing_ecs_task_role_name == null ? aws_iam_role.ecs_task[0].arn : data.aws_iam_role.ecs_task[0].arn
  ecs_task_role_name = var.existing_ecs_task_role_name == null ? aws_iam_role.ecs_task[0].name : data.aws_iam_role.ecs_task[0].name

  ecs_task_execution_role_arn  = var.existing_ecs_task_execution_role_name == null ? aws_iam_role.ecs_task_execution_role[0].arn : data.aws_iam_role.ecs_task_execution_role[0].arn
  ecs_task_execution_role_name = var.existing_ecs_task_execution_role_name == null ? aws_iam_role.ecs_task_execution_role[0].name : data.aws_iam_role.ecs_task_execution_role[0].name
}
