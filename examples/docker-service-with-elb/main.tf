# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER APP WITH AN ELASTIC LOAD BALANCER IN FRONT OF IT
# These templates show an example of how to run a Docker app on top of Amazon's EC2 Container Service (ECS) with an
# Elastic Load Balancer (ELB) routing traffic to the app.
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
# CREATE THE ECS CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "ecs_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-cluster?ref=v1.0.8"
  source = "../../modules/ecs-cluster"

  cluster_name = var.cluster_name

  # Make the max size twice the min size to allow for rolling out updates to the cluster without downtime
  # During ECS upgrade, if desired_capacity * 2 > max_size, cluster_max_size will be increased to desired_capacity * 2 to avoid downtimes
  cluster_min_size = 2
  cluster_max_size = 2

  cluster_instance_ami              = var.cluster_instance_ami
  cluster_instance_type             = module.instance_type.recommended_instance_type
  cluster_instance_keypair_name     = var.cluster_instance_keypair_name
  cluster_instance_user_data        = local.user_data
  enable_cluster_container_insights = true
  use_imdsv1                        = false

  ## This example does not create a NAT, so cluster must have a public IP to reach ECS endpoints
  cluster_instance_associate_public_ip_address = true

  vpc_id         = data.aws_vpc.default.id
  vpc_subnet_ids = data.aws_subnets.default.ids
}

# Expose an incoming port for HTTP requests on each instance in the ECS cluster
resource "aws_security_group_rule" "allow_inbound_http_from_elb" {
  type                     = "ingress"
  from_port                = var.host_http_port
  to_port                  = var.host_http_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_elb.id

  security_group_id = module.ecs_cluster.ecs_instance_security_group_id
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE USER DATA SCRIPT THAT WILL RUN ON EACH INSTANCE IN THE ECS CLUSTER
# This script will configure each instance so it registers in the right ECS cluster and authenticates to the proper
# Docker registry.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  user_data = templatefile(
    "${path.module}/user-data/user-data.sh",
    {
      ecs_cluster_name = var.cluster_name
      user_data_text   = var.user_data_text
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ECS TASK TO RUN MY DOCKER CONTAINER
# ---------------------------------------------------------------------------------------------------------------------

# This local defines the Docker containers we want to run in our ECS Task
locals {
  container_definition = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.service_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image               = "gruntwork/docker-test-webapp"
      version             = "latest"
      server_text         = var.server_text
      aws_region          = var.aws_region
      s3_test_file        = "s3://${aws_s3_bucket.s3_test_bucket.id}/${var.s3_test_file_name}"
      cpu                 = 512
      memory              = 256
      container_http_port = var.container_http_port
      host_http_port      = var.host_http_port
      command             = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH AN IAM POLICY TO THE TASK THAT ALLOWS IT TO ACCESS AN S3 BUCKET FOR TESTING PURPOSES
# The Docker container in our ECS Task will need this policy to download a file from an S3 bucket. We use this solely
# to test that the IAM policy is properly attached to the ECS Task.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_policy" "access_test_s3_bucket" {
  name   = "${var.service_name}-s3-test-bucket-access"
  policy = data.aws_iam_policy_document.access_test_s3_bucket.json
}

data "aws_iam_policy_document" "access_test_s3_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.s3_test_bucket.arn}/${var.s3_test_file_name}"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.s3_test_bucket.arn]
  }
}

resource "aws_iam_policy_attachment" "access_test_s3_bucket" {
  name       = "${var.service_name}-s3-test-bucket-access"
  policy_arn = aws_iam_policy.access_test_s3_bucket.arn
  roles      = [module.ecs_service.ecs_task_iam_role_name]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN S3 BUCKET FOR TESTING
# We upload a simple text file into this bucket. The ECS Task will try to download the file and display its contents.
# This is used to verify that we are correctly attaching an IAM Policy to the ECS Task that gives it the permissions to
# access the S3 bucket.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "s3_test_bucket" {
  bucket = "${lower(var.service_name)}-test-s3-bucket"
}

resource "aws_s3_bucket_object" "s3_test_file" {
  bucket  = aws_s3_bucket.s3_test_bucket.id
  key     = var.s3_test_file_name
  content = "world!"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ECS SERVICE TO RUN MY ECS TASK
# ---------------------------------------------------------------------------------------------------------------------

module "ecs_service" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-service?ref=v1.0.8"
  source = "../../modules/ecs-service"

  service_name    = var.service_name
  ecs_cluster_arn = module.ecs_cluster.ecs_cluster_arn
  launch_type     = "EC2"

  ecs_task_container_definitions = local.container_definition
  desired_number_of_tasks        = 1

  clb_name           = aws_elb.ecs_elb.name
  clb_container_name = var.service_name
  clb_container_port = var.container_http_port

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  health_check_interval = var.health_check_interval

  # Make sure all the ECS cluster and ELB resources are deployed before deploying any ECS service resources. This is
  # also necessary to avoid issues on 'destroy'.
  depends_on = [module.ecs_cluster, aws_elb.ecs_elb]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ELB TO ROUTE TRAFFIC ACROSS THE ECS TASKS
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_elb" "ecs_elb" {
  name                      = var.service_name
  security_groups           = [aws_security_group.ecs_elb.id]
  subnets                   = data.aws_subnets.default.ids
  cross_zone_load_balancing = true
  connection_draining       = true

  listener {
    instance_port     = var.host_http_port
    instance_protocol = "http"
    lb_port           = var.elb_http_port
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:${var.host_http_port}/"
    interval            = 15
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP TO CONTROL WHAT TRAFFIC CAN GO IN AND OUT OF THE ELB
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "ecs_elb" {
  name        = "${var.service_name}-elb"
  description = "For the ${var.service_name} ELB."
  vpc_id      = data.aws_vpc.default.id

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP inbound from anywhere
  ingress {
    from_port   = var.elb_http_port
    to_port     = var.elb_http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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

data "aws_caller_identity" "current" {}
