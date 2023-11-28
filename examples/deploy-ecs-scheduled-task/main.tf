# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER CLUSTER AND CREATE AN ECS TASK DEFINITION
# This is an example of how to deploy a Docker cluster and create an ECS Task Definition. You can use the run-ecs-task
# script in the ecs-deploy module to run this ECS Task Definition in the ECS Cluster.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  required_version = ">= 1.0.0"
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "ecs_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-cluster?ref=v1.0.8"
  source           = "../../modules/ecs-cluster"
  create_resources = var.create_resources

  cluster_name = var.ecs_cluster_name

  cluster_min_size = 2
  cluster_max_size = 2

  cluster_instance_ami          = var.ecs_cluster_instance_ami
  cluster_instance_type         = module.instance_type.recommended_instance_type
  cluster_instance_keypair_name = var.ecs_cluster_instance_keypair_name
  cluster_instance_user_data    = local.user_data
  use_imdsv1                    = false

  ## This example does not create a NAT, so cluster must have a public IP to reach ECS endpoints
  cluster_instance_associate_public_ip_address = true

  vpc_id         = data.aws_vpc.default.id
  vpc_subnet_ids = data.aws_subnet.default.*.id

  # To make testing easier, we allow inbound SSH globally. In production, you will want to limit this to a more
  # restrictive list.
  allow_ssh_from_cidr_blocks = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE USER DATA SCRIPT THAT WILL RUN ON BOOT FOR EACH EC2 INSTANCE IN THE ECS CLUSTER
# This script will configure each instance so it registers in the right ECS cluster and authenticates to the proper
# Docker registry.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  user_data = templatefile(
    "${path.module}/user-data/user-data.sh",
    {
      ecs_cluster_name = var.ecs_cluster_name
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ECS TASK DEFINITION
# You can run this ECS Task Definition in the ECS Cluster by using the run-ecs-task script in the ecs-deploy module.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "example" {
  count                 = var.create_resources ? 1 : 0
  family                = "${var.ecs_cluster_name}-example-task-definition"
  container_definitions = local.ecs_task_container_definitions
  network_mode          = var.ecs_task_network_mode
}

module "task_scheduler" {
  source = "../../modules/ecs-task-scheduler"

  ecs_target_task_definition_arn = resource.aws_ecs_task_definition.example.0.arn
  ecs_target_cluster_arn         = module.ecs_cluster.ecs_cluster_arn

  task_schedule_expression = var.task_schedule_expression
  task_event_pattern       = var.task_event_pattern

  ecs_target_task_count = var.ecs_target_task_count

  ecs_target_placement_constraints = var.ecs_target_placement_constraints
  ecs_target_network_configuration = var.ecs_target_network_configuration
  ecs_target_container_overrides   = var.ecs_target_container_overrides
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE CONTAINER DEFINITIONS FOR THE ECS TASK DEFINITION
# This specifies what Docker container(s) to run in the ECS Task and the resources those container(s) need.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  ecs_task_container_definitions = templatefile(
    "${path.module}/containers/container-definitions.json",
    {
      container_name = "${var.ecs_cluster_name}-example-container"
      image          = var.docker_image
      version        = var.docker_image_version
      cpu            = 1024
      memory         = 512
      command        = "[${join(",", formatlist("\"%s\"", var.docker_image_command))}]"
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# PICK AN INSTANCE TYPE
# We run automated tests against this example code in many regions, and some AZs in some regions don't have certain
# instance types. Therefore, we use this module to pick an instance type that's available in all AZs in the current
# region.
# ---------------------------------------------------------------------------------------------------------------------

module "instance_type" {
  source = "../../modules/instance-type"
  instance_types = ["t3.micro", "t2.micro"]
}

# ---------------------------------------------------------------------------------------------------------------------
# RUN THIS EXAMPLE IN THE DEFAULT VPC AND SUBNETS
# To keep this example simple, we run all of the code in the Default VPC and Subnets. In real-world usage, you should
# always use a custom VPC with private subnets.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "all" {}

data "aws_subnet" "default" {
  count             = min(length(data.aws_availability_zones.all.names), 3)
  availability_zone = element(data.aws_availability_zones.all.names, count.index)
  default_for_az    = true
}
