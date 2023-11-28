# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER APP WITH AN APPLICATION LOAD BALANCER IN FRONT OF IT
# These templates show an example of how to run a Docker app on top of Amazon's EC2 Container Service (ECS) with an
# Application Load Balancer (ALB) routing traffic to the app, and the ability to launch a canary container which receives
# some of the traffic from the ALB.
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

  cluster_name = var.ecs_cluster_name

  # Make the max size twice the min size to allow for rolling out updates to the cluster without downtime
  cluster_min_size = 3
  cluster_max_size = 6

  cluster_instance_ami              = var.ecs_cluster_instance_ami
  cluster_instance_type             = module.instance_type.recommended_instance_type
  cluster_instance_keypair_name     = var.ecs_cluster_instance_keypair_name
  cluster_instance_user_data        = local.user_data
  enable_cluster_container_insights = true
  use_imdsv1                        = false

  ## This example does not create a NAT, so cluster must have a public IP to reach ECS endpoints
  cluster_instance_associate_public_ip_address = true

  vpc_id         = data.aws_vpc.default.id
  vpc_subnet_ids = data.aws_subnets.default.ids

  alb_security_group_ids = [module.alb.alb_security_group_id]
}

# Create the User Data script that will run on boot for each EC2 Instance in the ECS Cluster.
# - This script will configure each instance so it registers in the right ECS cluster and authenticates to the proper
#   Docker registry.
locals {
  user_data = templatefile(
    "${path.module}/user-data/user-data.sh",
    {
      ecs_cluster_name = var.ecs_cluster_name
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ALB TO ROUTE TRAFFIC ACROSS THE ECS TASKS
# Typically, this would be created once for use with many different ECS Services.
# ---------------------------------------------------------------------------------------------------------------------

module "alb" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-load-balancer.git//modules/alb?ref=v0.29.11"

  alb_name        = var.service_name
  is_internal_alb = false

  http_listener_ports                = [80, 5000]
  https_listener_ports_and_ssl_certs = []
  ssl_policy                         = "ELBSecurityPolicy-TLS-1-1-2017-01"

  vpc_id         = data.aws_vpc.default.id
  vpc_subnet_ids = data.aws_subnets.default.ids
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN S3 BUCKET FOR TESTING PURPOSES ONLY
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
# CREATE AN ECS TASK DEFINITION FORMATTED AS JSON TO PASS TO THE ECS SERVICE
# This tells the ECS Service which Docker image to run, how much memory to allocate, and every other aspect of how the
# Docker image should run. Note that this resoure merely generates a JSON file; the actual AWS resource is created in
# module.ecs_service
# ---------------------------------------------------------------------------------------------------------------------

locals {

  # This local defines the Docker containers we want to run in our ECS Task
  ecs_task_container_definitions = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.container_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image               = "gruntwork/docker-test-webapp"
      version             = "latest"
      server_text         = var.server_text
      aws_region          = var.aws_region
      s3_test_file        = "s3://${aws_s3_bucket.s3_test_bucket.id}/${var.s3_test_file_name}"
      cpu                 = 512
      memory              = 256
      container_http_port = var.container_http_port
      command             = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
    },
  )

  # This local defines the Docker containers we want to run in our canary ECS Task
  ecs_task_definition_canary = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.container_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image               = "gruntwork/docker-test-webapp"
      version             = "latest"
      server_text         = var.canary_server_text
      aws_region          = var.aws_region
      s3_test_file        = "s3://${aws_s3_bucket.s3_test_bucket.id}/${var.s3_test_file_name}"
      cpu                 = 512
      memory              = 256
      container_http_port = var.container_http_port
      command             = "[${join(",", formatlist("\"%s\"", var.canary_container_command))}]"
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# ASSOCIATE A DNS RECORD WITH OUR ALB
# This way we can test the host-based routing properly.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_route53_zone" "sample" {
  name = "${var.route53_hosted_zone_name}."
}

resource "aws_route53_record" "alb_endpoint" {
  zone_id = data.aws_route53_zone.sample.zone_id
  name    = "${var.ecs_cluster_name}.${data.aws_route53_zone.sample.name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_hosted_zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS SERVICE
# In Amazon ECS, Docker containers are run as "ECS Tasks", typically as part of an "ECS Service".
# ---------------------------------------------------------------------------------------------------------------------

module "ecs_service" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-service?ref=v1.0.8"
  source = "../../modules/ecs-service"

  service_name = var.service_name
  launch_type  = "EC2"

  ecs_cluster_arn                = module.ecs_cluster.ecs_cluster_arn
  ecs_task_container_definitions = local.ecs_task_container_definitions

  desired_number_of_tasks = 2

  elb_target_groups = {
    alb = {
      name                  = var.service_name
      container_name        = var.container_name
      container_port        = var.container_http_port
      protocol              = "HTTP"
      health_check_protocol = "HTTP"
    }
  }
  elb_target_group_vpc_id = data.aws_vpc.default.id

  desired_number_of_canary_tasks_to_run = var.desired_number_of_canary_tasks_to_run
  ecs_task_definition_canary            = local.ecs_task_definition_canary

  deployment_minimum_healthy_percent = 50

  use_auto_scaling                 = false
  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds
  health_check_interval            = var.health_check_interval

  # Make sure all the ECS cluster and ALB resources are deployed before deploying any ECS service resources. This is
  # also necessary to avoid issues on 'destroy'.
  depends_on = [module.ecs_cluster, module.alb]

  # Explicit dependency to aws_alb_listener_rules to make sure listeners are created before deploying any ECS services
  # and avoid any race condition.
  listener_rule_ids = [
    aws_alb_listener_rule.host_based_example.id,
    aws_alb_listener_rule.host_based_path_based_example.id,
    aws_alb_listener_rule.path_based_example.id
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALB LISTENER RULES ASSOCIATED WITH THIS ECS SERVICE
# When an HTTP request is received by the ALB, how will the ALB know to route that request to this particular ECS Service?
# The answer is that we define ALB Listener Rules (https://goo.gl/vQv8oQ) that can route a requst to a specific "Target
# Group" that contains "Targets" which represent ECS Tasks (Docker containers) which comprise the ECS Service.
#
# For example purposes, we will define one path-based routing rule and one host-based routing rule.
# ---------------------------------------------------------------------------------------------------------------------

# EXAMPLE OF A HOST-BASED LISTENER RULE
# Host-based Listener Rules are used when you wish to have a single ALB handle requests for both foo.acme.com and
# bar.acme.com. Using a host-based routing rule, the ALB can route each inbound request to the desired Target Group.
resource "aws_alb_listener_rule" "host_based_example" {
  # Get the Listener ARN associated with port 80 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = module.alb.http_listener_arns["80"]

  priority = 95

  action {
    type             = "forward"
    target_group_arn = module.ecs_service.target_group_arns["alb"]
  }

  condition {
    host_header {
      values = ["*.${var.route53_hosted_zone_name}"]
    }
  }
}

# EXAMPLE OF A PATH-BASED LISTENER RULE
# Path-based Listener Rules are used when you wish to route all requests received by the ALB that match a certain
# "path" pattern to a given ECS Service. This is useful if you have one service that should receive all requests sent
# to /api and another service that receives requests sent to /customers.
resource "aws_alb_listener_rule" "path_based_example" {
  # Get the Listener ARN associated with port 5000 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 5000. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = module.alb.http_listener_arns["5000"]

  priority = 100

  action {
    type             = "forward"
    target_group_arn = module.ecs_service.target_group_arns["alb"]
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
  }
}

# EXAMPLE OF A LISTENER RULE THAT USES BOTH PATH-BASED AND HOST-BASED ROUTING CONDITIONS
# This Listener Rule will only route when both conditions are met.
resource "aws_alb_listener_rule" "host_based_path_based_example" {
  # Get the Listener ARN associated with port 5000 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 5000. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = module.alb.http_listener_arns["5000"]

  priority = 105

  action {
    type             = "forward"
    target_group_arn = module.ecs_service.target_group_arns["alb"]
  }

  condition {
    host_header {
      values = ["*.acme.com"]
    }
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
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
