# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# SETUP ELB RESOURCES
# When hooking up the ECS service with an ELB, you need to setup a few things:
# - With ELBv2 (NLB or ALB), you need to create a target group for the ECS services to register to
# - For all ELB setups, if you are not using awsvpc network modes, you need to create an IAM role for the ECS service
# This file contains the resource definitions for setting up the above.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# CONVENIENCE VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

locals {
  need_ecs_iam_role_for_elb = length(var.elb_target_groups) == 1 && var.ecs_task_definition_network_mode != "awsvpc"
  has_elbv2                 = length(var.elb_target_groups) > 0
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ELB TARGET GROUP
# - An ALB or NLB sends requests to one or more Targets (containers) contained in a Target Group. Typically a Target
#   Group is scoped to the level of an ECS Service, so we create one here.
# - The port number listed below in each aws_lb_target_group refers to the default port to which the ELB will route
#   traffic, but because this value will be overridden by each container instance that boots up, the actual value
#   doesn't matter.
# ---------------------------------------------------------------------------------------------------------------------

# This resource is only created when using ELB v2 (ALB or NLB)
resource "aws_lb_target_group" "ecs_service" {
  for_each = var.elb_target_groups

  # Potential workaround for https://github.com/hashicorp/terraform/issues/12634#issuecomment-363849290
  depends_on = [null_resource.dependency_getter]

  name = each.value.name
  # Note that the port 80 specified below is simply the default port for the Target Group. When a Docker container
  # launches, the actual port will be chosen dynamically, so the value specified below is arbitrary.
  port             = 80
  protocol         = lookup(each.value, "protocol", "TCP")
  protocol_version = lookup(each.value, "protocol_version", null)
  # Note: For ALBs, null will translate to the default value "round_robin". NLBs do not have a
  # load_balancing_algorithm_type, thus `null` is appropriate.
  load_balancing_algorithm_type = lookup(each.value, "load_balancing_algorithm_type", null)
  vpc_id                        = var.elb_target_group_vpc_id
  target_type                   = var.ecs_task_definition_network_mode == "awsvpc" ? "ip" : "instance"
  tags                          = var.lb_target_group_tags

  deregistration_delay = var.elb_target_group_deregistration_delay
  slow_start = (
    each.value.protocol == "TCP"
    ? null
    : var.elb_slow_start
  )

  health_check {
    enabled = var.health_check_enabled
    # The approximate amount of time, in seconds, between health checks of an individual target. If the target group protocol
    # is TCP, TLS, UDP, or TCP_UDP, the supported values are 10 and 30 seconds.
    # https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_CreateTargetGroup.html
    interval = (
      each.value.protocol == "TCP" || each.value.protocol == "TLS" || each.value.protocol == "UDP" || each.value.protocol == "TCP_UDP"
      ? (var.health_check_interval < 20 ? 10 : 30)
      : var.health_check_interval
    )
    port              = var.health_check_port
    healthy_threshold = var.health_check_healthy_threshold
    # The number of consecutive health check failures required before considering a target unhealthy. If the target group
    # protocol is TCP or TLS, this value must be the same as the healthy threshold count.
    # https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_CreateTargetGroup.html
    unhealthy_threshold = (
      each.value.protocol == "TCP" || each.value.protocol == "TLS"
      ? var.health_check_healthy_threshold
      : var.health_check_unhealthy_threshold
    )

    protocol = lookup(each.value, "health_check_protocol", "TCP")

    # The amount of time, in seconds, during which no response from a target means a failed health check. For target groups
    # with a protocol of TCP or TLS, this value must be 6 seconds for HTTP health checks and 10 seconds for TCP and HTTPS
    # health checks.
    # https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_CreateTargetGroup.html
    timeout = (
      each.value.protocol != "TCP" && each.value.protocol != "TLS"
      ? var.health_check_timeout
      : null
    )
    # HealthCheckPath param can only be set for HTTP or HTTPS health checks
    path = (
      each.value.health_check_protocol == "HTTP" || each.value.health_check_protocol == "HTTPS"
      ? var.health_check_path
      : null
    )
    # Matcher param can only be set for HTTP or HTTPS health checks and for target group protocol is HTTP or HTTPS (however this is not 100% clear from the documentation)
    matcher = (
      (each.value.health_check_protocol == "HTTP" || each.value.health_check_protocol == "HTTPS") &&
      (each.value.protocol == "HTTP" || each.value.protocol == "HTTPS")
      ? var.health_check_matcher
      : null
    )
  }

  dynamic "stickiness" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = var.use_alb_sticky_sessions ? ["use_sticky"] : []
    content {
      type            = var.alb_sticky_session_type
      cookie_duration = var.alb_sticky_session_cookie_duration
    }
  }
}


# Note that no ELB Listener Rules are defined by this module! As a result, you'll need to add those ELB Listener Rules
# somewhere external to this module. Most likely, this will be in the code that calls this module. We made this decision
# because trying to capture the full range of ELB Listener Rule functionality in this module's API proved more confusing
# than helpful.


# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN IAM ROLE FOR THE SERVICE
# We output the id of this IAM role in case the module user wants to attach custom IAM policies to it. Note that the
# role is only created and used if this ECS Service is being used with an ELB.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "ecs_service_role" {
  count = local.need_ecs_iam_role_for_elb ? 1 : 0

  name = (
    var.custom_ecs_service_role_name != ""
    ? var.custom_ecs_service_role_name
    : var.service_name
  )
  assume_role_policy   = data.aws_iam_policy_document.ecs_service_role.json
  permissions_boundary = var.elb_role_permissions_boundary_arn

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the ECS service cannot be
  # created because the IAM role does not exist. We add a 15 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 15 seconds to wait for IAM role to be created'; sleep 15"
  }
}

data "aws_iam_policy_document" "ecs_service_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN IAM POLICY THAT ALLOWS THE SERVICE TO TALK TO THE ELB
# Note that this policy is only created and used if this ECS Service is being used with an ELB.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role_policy" "ecs_service_policy" {
  count = local.need_ecs_iam_role_for_elb ? 1 : 0

  name   = "${var.service_name}-ecs-service-policy"
  role   = local.need_ecs_iam_role_for_elb ? aws_iam_role.ecs_service_role[0].id : ""
  policy = data.aws_iam_policy_document.ecs_service_policy.json

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the ECS task cannot be
  # created because the IAM role does not exist. We add a 15 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 15 seconds to wait for IAM role to be created'; sleep 15"
  }
}

data "aws_iam_policy_document" "ecs_service_policy" {
  statement {
    effect = "Allow"

    actions = concat(
      [
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      ],
      local.has_elbv2 ? ["elasticloadbalancing:DeregisterTargets", "elasticloadbalancing:RegisterTargets"] : [],
    )

    resources = ["*"]
  }
}
