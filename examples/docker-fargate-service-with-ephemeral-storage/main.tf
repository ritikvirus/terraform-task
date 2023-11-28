# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER APP WITH custom ephemeral storage size
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  required_version = ">= 1.0.0"
}

# --------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# --------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A CLUSTER TO WHICH THE FARGATE SERVICE WILL BE DEPLOYED TO
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ecs_cluster" "fargate_cluster" {
  name = "${var.service_name}-example"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A FARGATE SERVICE TO RUN MY ECS TASK
# ---------------------------------------------------------------------------------------------------------------------

module "fargate_service" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-service?ref=v1.0.8"
  source = "../../modules/ecs-service"

  service_name    = var.service_name
  ecs_cluster_arn = aws_ecs_cluster.fargate_cluster.arn

  desired_number_of_tasks        = var.desired_number_of_tasks
  ecs_task_container_definitions = local.container_definition
  launch_type                    = "FARGATE"
  platform_version               = "1.4.0"

  # Network information is necessary for Fargate, as it required VPC type
  ecs_task_definition_network_mode = "awsvpc"
  ecs_service_network_configuration = {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_task_security_group.id]
    assign_public_ip = true
  }

  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html#fargate-tasks-size.
  # Specify memory in MB
  task_cpu    = 256
  task_memory = 512

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds
  health_check_interval            = var.health_check_interval

  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_definition_ephemeralStorage
  task_ephemeral_storage = 30

  # Make sure all the ECS cluster resources are deployed before deploying any ECS service resources. This is also
  # necessary to avoid issues on 'destroy'.
  depends_on = [aws_ecs_cluster.fargate_cluster]
}

# This local defines the Docker containers we want to run in our ECS Task
locals {
  container_definition = templatefile(
    "${path.module}/containers/container-definition.json.tpl",
    {
      container_name = var.service_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image               = "gruntwork/docker-test-webapp"
      version             = "latest"
      server_text         = var.server_text
      cpu                 = 256
      memory              = 512
      awslogs_group       = var.service_name
      awslogs_region      = var.aws_region
      awslogs_prefix      = var.service_name
      container_http_port = var.http_port
      command             = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP FOR THE AWSVPC TASK NETWORK
# Allow all inbound access on the container port and outbound access
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "ecs_task_security_group" {
  name   = "${var.service_name}-task-access"
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "allow_outbound_all" {
  security_group_id = aws_security_group.ecs_task_security_group.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_inbound_on_container_port" {
  security_group_id = aws_security_group.ecs_task_security_group.id
  type              = "ingress"
  from_port         = var.http_port
  to_port           = var.http_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# --------------------------------------------------------------------------------------------------------------------
# GET VPC AND SUBNET INFO FROM TERRAFORM DATA SOURCE
# --------------------------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = [true]
  }
}

# --------------------------------------------------------------------------------------------------------------------
# CREATE AN EXAMPLE CLOUDWATCH LOG GROUP
# --------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "log_group_example" {
  name = var.service_name
}
