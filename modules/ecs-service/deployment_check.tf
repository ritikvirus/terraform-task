# ---------------------------------------------------------------------------------------------------------------------
# CHECK THE ECS SERVICE DEPLOYMENT
# Make sure that the deployment rolls out before completing the terraform apply.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_arn" "ecs_service" {
  arn = local.ecs_service_arn
}

locals {
  ecs_service               = var.use_auto_scaling ? aws_ecs_service.service_with_auto_scaling[0] : aws_ecs_service.service_without_auto_scaling[0]
  ecs_service_arn           = local.ecs_service.id
  ecs_task_definition_arn   = local.ecs_service.task_definition
  ecs_service_desired_count = local.ecs_service.desired_count

  canary_service_arn         = local.has_canary ? aws_ecs_service.canary[0].id : null
  canary_task_definition_arn = local.has_canary ? aws_ecs_service.canary[0].task_definition : null
  canary_desired_count       = local.has_canary ? aws_ecs_service.canary[0].desired_count : null

  // We only enable loadbalancer checks if using ELBv2. For CLBs, the deployment check does not know how to verify
  // health checks from those.
  skip_load_balancer_check_arg = !local.has_elbv2 ? "--no-loadbalancer" : ""

  check_common_args = <<EOF
--loglevel ${var.deployment_check_loglevel} \
--aws-region ${data.aws_arn.ecs_service.region} \
--ecs-cluster-arn ${var.ecs_cluster_arn} \
${local.skip_load_balancer_check_arg} \
--check-timeout-seconds ${var.deployment_check_timeout_seconds}
EOF

}

resource "null_resource" "ecs_deployment_check" {
  count = var.enable_ecs_deployment_check ? 1 : 0

  triggers = {
    ecs_service_arn         = local.ecs_service_arn
    ecs_task_definition_arn = local.ecs_task_definition_arn
    desired_count           = local.ecs_service_desired_count
  }

  provisioner "local-exec" {
    command = <<EOF
${module.ecs_deployment_check_bin.path} \
  --ecs-service-arn ${local.ecs_service_arn} \
  --ecs-task-definition-arn ${local.ecs_task_definition_arn} \
  --min-active-task-count ${local.ecs_service_desired_count} \
  ${local.check_common_args}
EOF

  }
}

resource "null_resource" "ecs_canary_deployment_check" {
  count = local.has_canary && var.enable_ecs_deployment_check ? 1 : 0

  triggers = {
    ecs_service_arn         = local.canary_service_arn
    ecs_task_definition_arn = local.canary_task_definition_arn
    desired_count           = local.canary_desired_count
  }

  provisioner "local-exec" {
    command = <<EOF
${module.ecs_deployment_check_bin.path} \
  --ecs-service-arn ${local.canary_service_arn} \
  --ecs-task-definition-arn ${local.canary_task_definition_arn} \
  --min-active-task-count ${local.canary_desired_count} \
  ${local.check_common_args}
EOF

  }
}

# Build the path to the deployment check binary
module "ecs_deployment_check_bin" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-utilities.git//modules/join-path?ref=v0.9.4"

  path_parts = [path.module, "..", "ecs-deploy-check-binaries", "bin", "check-ecs-service-deployment"]
}
