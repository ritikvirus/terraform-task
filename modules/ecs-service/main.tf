# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE AN ELASTIC CONTAINER SERVICE (ECS) SERVICE WITH EC2 LAUNCH TYPE
# These templates create an ECS Service which runs one or more related Docker containers in fault-tolerant way.
# The templates are broken up as follows:
# - main.tf: All the resources and logic for the ECS service.
# - task_definition.tf: All the resources and logic for the ECS task definition.
# - elb.tf: All the resources and logic for associating the ECS service with an ELB. This includes any special IAM
#           resources necessary.
# - service_discovery.tf: All the resources and logic for setting up ECS Service Discovery.
# - auto_scaling.tf: All the resources and logic for setting up auto scaling on the ECS service.
# - deployment_check.tf: All the local-exec calls for ensuring the ECS service deployment rolls out.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0.0"

  required_providers {
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
# SET MODULE DEPENDENCY RESOURCE
# This works around a terraform limitation where we can not specify module dependencies natively.
# See https://github.com/hashicorp/terraform/issues/1178 for more discussion.
# By resolving and computing the dependencies list, we are able to make all the resources in this module depend on the
# resources backing the values in the dependencies list.
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "dependency_getter" {
  triggers = {
    instance = join(",", var.dependencies)
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SET DEPENDENT LISTENER RULES
# Workaround resource used to wait for external listener rules to be created before ECS cluster provisioning.
# Separated definition from "dependency_getter" since it blocks only creation of aws_ecs_service resources.
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "listener_rules" {
  triggers = {
    instance = join(",", var.listener_rule_ids)
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CONVENIENCE VARIABLES USED THROUGHOUT
# ---------------------------------------------------------------------------------------------------------------------

locals {
  has_canary = var.desired_number_of_canary_tasks_to_run > 0

  # Filter FARGATE and FARGATE_SPOT capacity providers based on their restricted names
  has_fargate_capacity_providers = [
    for provider in var.capacity_provider_strategy : true
    if length(regexall("^(FARGATE|FARGATE_SPOT)", provider.capacity_provider)) > 0
  ]
  is_fargate = (length(var.capacity_provider_strategy) == 0 && var.launch_type == "FARGATE") || length(local.has_fargate_capacity_providers) > 0
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS SERVICE
# Note that we have two aws_ecs_service resources: one without auto scaling and one with auto scaling. Only ONE of these
# will be created, based on the values the user of this module set var.use_auto_scaling. See the count parameter in each
# resource to see how we are simulating an if-statement in Terraform.
#
# The reason we have to create two resources to create these two cases is because the resources differ based on
# lifecycle blocks, and lifecycle blocks can not be dynamic as Terraform must process these before it is safe to
# evaluate expressions (https://www.terraform.io/docs/configuration/expressions.html#dynamic-blocks).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Requirements for launch_type and capacity_provider_strategy parameters based on the AWS docs
  # See https://docs.aws.amazon.com/cli/latest/reference/ecs/create-service.html for details
  #
  # 1. If a capacity_provider_strategy is specified, the launch_type parameter must be omitted. If no capacity_provider_strategy
  # or launch_type is specified, the default_capacity_provider_strategy for the cluster is used.
  # 2. If specifying a capacity provider that uses an Auto Scaling group, the capacity provider must already be created.
  # 3. To use an AWS Fargate capacity provider, specify either the FARGATE or FARGATE_SPOT capacity providers.
  launch_type = length(var.capacity_provider_strategy) == 0 ? var.launch_type : null
}

resource "aws_ecs_service" "service_with_auto_scaling" {
  count = var.use_auto_scaling ? 1 : 0
  depends_on = [
    aws_iam_role_policy.ecs_service_policy,
    null_resource.dependency_getter,
    null_resource.listener_rules
  ]

  name            = var.service_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.task.arn

  # If associating with an ELB, set the IAM role that has the permissions to be able to talk to the ELB. The depends_on
  # is required according to the Terraform docs: https://www.terraform.io/docs/providers/aws/r/ecs_service.html
  # NOTE: resources/locals here are defined in elb.tf
  iam_role = (
    local.need_ecs_iam_role_for_elb
    ? aws_iam_role.ecs_service_role[0].arn
    : null
  )

  launch_type                        = local.launch_type
  desired_count                      = var.desired_number_of_tasks
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = var.enable_execute_command

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker == null ? [] : [var.deployment_circuit_breaker]

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "ordered_placement_strategy" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = local.is_fargate ? [] : var.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = lookup(ordered_placement_strategy.value, "field", null)
    }
  }

  dynamic "placement_constraints" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = local.is_fargate ? [] : ["use_ec2"]
    content {
      type       = var.placement_constraint_type
      expression = var.placement_constraint_expression
    }
  }

  dynamic "network_configuration" {
    for_each = var.ecs_task_definition_network_mode == "awsvpc" ? [var.ecs_service_network_configuration] : []
    content {
      subnets          = network_configuration.value.subnets
      security_groups  = network_configuration.value.security_groups
      assign_public_ip = network_configuration.value.assign_public_ip
    }
  }

  dynamic "service_registries" {
    for_each = aws_service_discovery_service.discovery.*.arn
    content {
      registry_arn = service_registries.value
    }
  }

  # NOTE: resources/locals here are defined in elb.tf
  dynamic "load_balancer" {
    for_each = aws_lb_target_group.ecs_service
    content {
      target_group_arn = load_balancer.value.arn
      container_name   = var.elb_target_groups[load_balancer.key].container_name
      container_port   = var.elb_target_groups[load_balancer.key].container_port
    }
  }

  dynamic "load_balancer" {
    for_each = var.clb_name == null ? [] : [var.clb_name]
    content {
      elb_name       = var.clb_name
      container_name = var.clb_container_name
      container_port = var.clb_container_port
    }
  }

  # When the use_auto_scaling property is set to true, we need to tell the ECS Service to ignore the desired_count
  # property, as the number of instances will be controlled by auto scaling. For more info, see:
  # https://github.com/hashicorp/terraform/issues/10308
  lifecycle {
    ignore_changes = [desired_count]
  }

  platform_version = var.platform_version

  tags           = var.service_tags
  propagate_tags = var.propagate_tags

  wait_for_steady_state = var.wait_for_steady_state

  dynamic "deployment_controller" {
    for_each = var.deployment_controller != null ? [var.deployment_controller] : []
    content {
      type = var.deployment_controller
    }
  }
}

resource "aws_ecs_service" "service_without_auto_scaling" {
  count = var.use_auto_scaling ? 0 : 1
  depends_on = [
    aws_iam_role_policy.ecs_service_policy,
    null_resource.dependency_getter,
    null_resource.listener_rules,
  ]

  name            = var.service_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.task.arn

  # If associating with an ELB, set the IAM role that has the permissions to be able to talk to the ELB. The depends_on
  # is required according to the Terraform docs: https://www.terraform.io/docs/providers/aws/r/ecs_service.html
  # NOTE: resources/locals here are defined in elb.tf
  iam_role = (
    local.need_ecs_iam_role_for_elb
    ? aws_iam_role.ecs_service_role[0].arn
    : null
  )

  launch_type                        = local.launch_type
  desired_count                      = var.desired_number_of_tasks
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = var.enable_execute_command

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker == null ? [] : [var.deployment_circuit_breaker]

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "ordered_placement_strategy" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = local.is_fargate ? [] : var.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = lookup(ordered_placement_strategy.value, "field", null)
    }
  }

  dynamic "placement_constraints" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = local.is_fargate ? [] : ["use_ec2"]
    content {
      type       = var.placement_constraint_type
      expression = var.placement_constraint_expression
    }
  }

  dynamic "network_configuration" {
    for_each = var.ecs_task_definition_network_mode == "awsvpc" ? [var.ecs_service_network_configuration] : []
    content {
      subnets          = network_configuration.value.subnets
      security_groups  = network_configuration.value.security_groups
      assign_public_ip = network_configuration.value.assign_public_ip
    }
  }

  dynamic "service_registries" {
    for_each = aws_service_discovery_service.discovery.*.arn
    content {
      registry_arn = service_registries.value
    }
  }

  # NOTE: resources/locals here are defined in elb.tf
  dynamic "load_balancer" {
    for_each = aws_lb_target_group.ecs_service
    content {
      target_group_arn = load_balancer.value.arn
      container_name   = var.elb_target_groups[load_balancer.key].container_name
      container_port   = var.elb_target_groups[load_balancer.key].container_port
    }
  }

  dynamic "load_balancer" {
    for_each = var.clb_name == null ? [] : [var.clb_name]
    content {
      elb_name       = var.clb_name
      container_name = var.clb_container_name
      container_port = var.clb_container_port
    }
  }

  platform_version = var.platform_version

  tags           = var.service_tags
  propagate_tags = var.propagate_tags

  wait_for_steady_state = var.wait_for_steady_state

  deployment_controller {
    type = var.deployment_controller
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS SERVICE CANARIES
# We create a canary version of the ECS Service that can be used to test deployment of a new version of a Docker
# container on a small number of ECS Tasks (usually just one) before deploying it across all ECS Tasks.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ecs_service" "canary" {
  # Ensure we only create this resource if the user has requested at least one canary task to run.
  count      = local.has_canary ? 1 : 0
  depends_on = [aws_iam_role_policy.ecs_service_policy]

  name            = "${var.service_name}-canary"
  cluster         = var.ecs_cluster_arn
  task_definition = local.has_canary ? aws_ecs_task_definition.task_canary[0].arn : null

  # If associating with an ELB, set the IAM role that has the permissions to be able to talk to the ELB. The depends_on
  # is required according to the Terraform docs: https://www.terraform.io/docs/providers/aws/r/ecs_service.html
  # NOTE: resources/locals here are defined in elb.tf
  iam_role = (
    local.need_ecs_iam_role_for_elb
    ? aws_iam_role.ecs_service_role[0].arn
    : null
  )

  launch_type                        = local.launch_type
  desired_count                      = var.desired_number_of_canary_tasks_to_run
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = var.enable_execute_command

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker == null ? [] : [var.deployment_circuit_breaker]

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "ordered_placement_strategy" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = local.is_fargate ? [] : var.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = lookup(ordered_placement_strategy.value, "field", null)
    }
  }

  dynamic "placement_constraints" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = local.is_fargate ? [] : ["use_ec2"]
    content {
      type       = var.placement_constraint_type
      expression = var.placement_constraint_expression
    }
  }

  dynamic "network_configuration" {
    for_each = var.ecs_task_definition_network_mode == "awsvpc" ? [var.ecs_service_network_configuration] : []
    content {
      subnets          = network_configuration.value.subnets
      security_groups  = network_configuration.value.security_groups
      assign_public_ip = network_configuration.value.assign_public_ip
    }
  }

  dynamic "service_registries" {
    for_each = aws_service_discovery_service.discovery.*.arn
    content {
      registry_arn = service_registries.value
    }
  }

  # NOTE: resources/locals here are defined in elb.tf
  dynamic "load_balancer" {
    for_each = aws_lb_target_group.ecs_service
    content {
      target_group_arn = load_balancer.value.arn
      container_name   = var.elb_target_groups[load_balancer.key].container_name
      container_port   = var.elb_target_groups[load_balancer.key].container_port
    }
  }

  dynamic "load_balancer" {
    for_each = var.clb_name == null ? [] : [var.clb_name]
    content {
      elb_name       = var.clb_name
      container_name = var.clb_container_name
      container_port = var.clb_container_port
    }
  }

  # Workaround for a bug where Terraform sometimes doesn't wait long enough for the service to propagate.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 30 seconds to work around ecs service creation bug in Terraform' && sleep 30"
  }

  platform_version = var.platform_version

  tags           = var.service_tags
  propagate_tags = var.propagate_tags

  wait_for_steady_state = var.wait_for_steady_state
}
