# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER DAEMON SERVICE
# These templates show an example of how to run a Docker app on as a Daemon Service on ECS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  required_version = ">= 1.0.0"
}

# ------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE USER DATA SCRIPT THAT WILL RUN ON EACH INSTANCE IN THE ECS CLUSTER
# This script will configure each instance so it registers in the right ECS cluster and authenticates to the proper
# Docker registry.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  container_definition = templatefile(
    "${path.module}/containers/datadog-agent-ecs.json",
    {
      cpu     = var.cpu
      memory  = var.memory
      api_key = var.api_key
      command = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ECS SERVICE TO RUN MY ECS TASK
# ---------------------------------------------------------------------------------------------------------------------

module "ecs_daemon_service" {
  source = "../../modules/ecs-daemon-service"

  service_name                   = var.service_name
  ecs_cluster_arn                = var.ecs_cluster_arn
  ecs_task_container_definitions = local.container_definition

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  volumes = {
    docker_sock = {
      host_path = "/var/run/docker.sock"
    }
    proc = {
      host_path = "/proc/"
    }
    cgroup = {
      host_path = "/cgroup/"
    }
    volumeConfigExample = {
      docker_volume_configuration = {
        scope         = "shared"
        autoprovision = true
        driver        = "local"
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ADDITIONAL POLICIES
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role_policy" "iam_policy" {
  name   = "datadog-agent-policy"
  role   = module.ecs_daemon_service.ecs_task_iam_role_name
  policy = data.aws_iam_policy_document.datadog_agent_policy.json
}

data "aws_iam_policy_document" "datadog_agent_policy" {
  statement {
    effect = "Allow"

    actions = [
      "ecs:RegisterContainerInstance",
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Submit*",
      "ecs:Poll",
      "ecs:StartTask",
      "ecs:StartTelemetrySession"
    ]

    resources = ["*"]
  }
}
