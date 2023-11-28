# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EVENTBRIDGE/CLOUDWATCH EVENT RULE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "ecs_schedule_task_rule" {
  event_pattern       = var.task_event_pattern
  schedule_expression = var.task_schedule_expression
  is_enabled          = var.is_enabled
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EVENT TARGET
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_event_target" "ecs_scheduled_task_target" {
  arn      = var.ecs_target_cluster_arn
  rule     = aws_cloudwatch_event_rule.ecs_schedule_task_rule.name
  role_arn = var.create_iam_role ? aws_iam_role.ecs_events_role.0.arn : var.ecs_task_iam_role

  # Container Overrides input
  input = var.ecs_target_container_overrides

  ecs_target {
    task_definition_arn = var.ecs_target_task_definition_arn

    group                   = var.ecs_target_group
    launch_type             = var.ecs_target_launch_type
    platform_version        = var.ecs_target_platform_version
    task_count              = var.ecs_target_task_count
    propagate_tags          = var.ecs_target_propagate_tags
    enable_execute_command  = var.ecs_target_enable_execute_command
    enable_ecs_managed_tags = var.enable_ecs_managed_tags

    dynamic "network_configuration" {
      # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
      for_each = var.ecs_target_network_configuration == null ? [] : [1]

      content {
        # Use try() function since assign_public_ip and security_groups are optional parameters and may not exist in the input object
        assign_public_ip = try(var.ecs_target_network_configuration.assign_public_ip, null)
        security_groups  = try(var.ecs_target_network_configuration.security_groups, null)
        subnets          = var.ecs_target_network_configuration.subnets
      }
    }

    dynamic "placement_constraint" {
      # Up to 10 placement constraint blocks can be created (per AWS Documentation).
      for_each = var.ecs_target_placement_constraints
      content {
        type       = placement_constraint.value["type"]
        expression = placement_constraint.value["expression"]
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS TASK IAM ROLE AND ASSOCIATED POLICY DOCUMENT
# This role will allow EventBridge/Cloudwatch to run the ECS task
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "ecs_events_role" {
  count = var.create_iam_role ? 1 : 0

  assume_role_policy = data.aws_iam_policy_document.ecs_events_assume_role_policy_document.json
}

# Assume Role policy document for EventBridge/Cloudwatch events to assume the IAM role
data "aws_iam_policy_document" "ecs_events_assume_role_policy_document" {

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# IAM role definition for EventBridge/CloudWatch to run the ECS task
resource "aws_iam_role_policy" "ecs_events_run_task_policy" {
  count = var.create_iam_role ? 1 : 0

  role   = aws_iam_role.ecs_events_role.0.id
  policy = data.aws_iam_policy_document.ecs_events_run_task_policy_document.json
}

# IAM role policy document
data "aws_iam_policy_document" "ecs_events_run_task_policy_document" {

  statement {
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = [var.ecs_target_task_definition_arn]

    condition {
      test     = "ArnLike"
      variable = "ecs:cluster"
      values   = [var.ecs_target_cluster_arn]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}
