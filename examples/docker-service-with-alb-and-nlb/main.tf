# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER APP WITH AN APPLICATION LOAD BALANCER IN FRONT OF IT
# These templates show an example of how to run a Docker app on top of Amazon's EC2 Container Service (ECS) with an
# Application Load Balancer (ALB) routing traffic to the app.
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
  cluster_min_size = 2
  cluster_max_size = 4

  cluster_instance_ami              = var.ecs_cluster_instance_ami
  cluster_instance_type             = module.instance_type.recommended_instance_type
  cluster_instance_keypair_name     = var.ecs_cluster_instance_keypair_name
  cluster_instance_user_data        = local.user_data
  enable_cluster_container_insights = true
  use_imdsv1                        = false

  vpc_id         = data.aws_vpc.default.id
  vpc_subnet_ids = data.aws_subnets.default.ids

  ## This example does not create a NAT, so cluster must have a public IP to reach ECS endpoints
  cluster_instance_associate_public_ip_address = true

  alb_security_group_ids = [module.alb.alb_security_group_id]

  custom_tags_security_group = {
    Foo = "Bar"
  }

  custom_tags_ec2_instances = [
    {
      key                 = "Foo"
      value               = "Bar"
      propagate_at_launch = true
    },
  ]
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

  http_listener_ports                    = values(local.listener_ports)
  https_listener_ports_and_ssl_certs     = []
  https_listener_ports_and_acm_ssl_certs = []
  ssl_policy                             = "ELBSecurityPolicy-TLS-1-1-2017-01"

  vpc_id         = data.aws_vpc.default.id
  vpc_subnet_ids = data.aws_subnets.default.ids
}

locals {
  listener_ports = {
    web = 80
  }
}

# ------------------------------------------------------------------------------
# CREATE AN NLB TO ROUTE TRAFFIC ACROSS THE ECS TASKS
# An NLB can front a single target group.
# ------------------------------------------------------------------------------

resource "aws_lb" "nlb" {
  name               = "${var.service_name}-nlb"
  internal           = false
  load_balancer_type = "network"

  dynamic "subnet_mapping" {
    for_each = data.aws_subnets.default.ids

    content {
      subnet_id = subnet_mapping.value
    }
  }

  enable_cross_zone_load_balancing = false
  ip_address_type                  = "ipv4"
}

# ------------------------------------------------------------------------------
# CREATE A SECURITY GROUP TO ALLOW NLB HEALTH CHECKS
# NLBs do not have security groups, so the traffic will originate from the
# subnet of the NLB, but will not have an associated security group.
# ------------------------------------------------------------------------------

resource "aws_security_group_rule" "allow_health_check_nlb" {
  type      = "ingress"
  from_port = "32768"
  to_port   = "65535"
  protocol  = "tcp"
  cidr_blocks = [
    "0.0.0.0/0", # Public NLB health checks can come from any AWS public IP
  ]
  security_group_id = module.ecs_cluster.ecs_instance_security_group_id
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH AN IAM POLICY TO THE TASK THAT ALLOWS THE ECS SERVICE TO CLOUDWATCH
# ---------------------------------------------------------------------------------------------------------------------

module "cloudwatch_log_aggregation" {
  source           = "git::git@github.com:gruntwork-io/terraform-aws-monitoring.git//modules/logs/cloudwatch-log-aggregation-iam-policy?ref=v0.36.3"
  create_resources = false
  name_prefix      = var.service_name
}

resource "aws_iam_role_policy" "attach_cloudwatch_log_aggregation_policy" {
  name   = "attach-cloudwatch-log-aggregation-policy"
  role   = module.ecs_service.ecs_task_iam_role_name
  policy = module.cloudwatch_log_aggregation.cloudwatch_logs_permissions_json
}

resource "aws_cloudwatch_log_group" "ecs_task" {
  name_prefix = var.service_name
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ECS TASK DEFINITION FORMATTED AS JSON TO PASS TO THE ECS SERVICE
# This tells the ECS Service which Docker image to run, how much memory to allocate, and every other aspect of how the
# Docker image should run. Note that this resoure merely generates a JSON file; the actual AWS resource is created in
# module.ecs_service
# ---------------------------------------------------------------------------------------------------------------------

# This local defines the Docker containers we want to run in our ECS Task
locals {
  ecs_task_container_definitions = [
    {
      name      = var.container_name
      image     = "gruntwork/docker-test-webapp:latest"
      cpu       = 512
      memory    = var.container_memory
      command   = var.container_command
      essential = true
      portMappings = [{
        containerPort = var.container_http_port
        protocol      = "tcp"
      }]
      environment = [for k, v in local.all_env_vars : {
        name  = k
        value = tostring(v)
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_task.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.container_name
        }
      }
    },
    # Run nginx as a side car to test routing to different containers.
    {
      name      = local.alt_container_name
      image     = "nginx:1.19"
      cpu       = 512
      memory    = var.container_memory
      essential = true
      portMappings = [{
        containerPort = local.alt_container_port
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_task.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = local.alt_container_name
        }
      }
    }
  ]
}

locals {
  all_env_vars = {
    SERVER_TEXT        = var.server_text
    AWS_DEFAULT_REGION = var.aws_region
    BOOT_DELAY_SEC     = var.container_boot_delay_seconds
  }

  alt_container_name = "nginx"
  alt_container_port = 80
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
  ecs_task_container_definitions = jsonencode(local.ecs_task_container_definitions)

  desired_number_of_tasks = var.desired_number_of_tasks

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  elb_target_groups = {
    alb = {
      name                  = var.service_name
      container_name        = var.container_name
      container_port        = var.container_http_port
      protocol              = "HTTP"
      health_check_protocol = "HTTP"
    }
    nlb = {
      name                  = "ecs-nlb"
      container_name        = local.alt_container_name
      container_port        = local.alt_container_port
      protocol              = "TCP"
      health_check_protocol = "TCP"
    }
  }
  elb_target_group_vpc_id = data.aws_vpc.default.id
  elb_slow_start          = 30
  health_check_interval   = var.health_check_interval

  use_auto_scaling                 = false
  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  # Make sure all the ECS cluster, ALB, and NLB resources are deployed before deploying any ECS service resources. This
  # is also necessary to avoid issues on 'destroy'.
  depends_on = [module.ecs_cluster, module.alb, aws_lb.nlb]

  # Explicit dependency to aws_alb_listener_rules to make sure listeners are created before deploying any ECS services
  # and avoid any race condition.
  listener_rule_ids = [
    aws_alb_listener_rule.path_based_example.id
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALB LISTENER RULES ASSOCIATED WITH THIS ECS SERVICE
# When an HTTP request is received by the ALB, how will the ALB know to route that request to this particular ECS Service?
# The answer is that we define ALB Listener Rules (https://goo.gl/vQv8oQ) that can route a request to a specific "Target
# Group" that contains "Targets". Each Target is actually an ECS Task (which is really just a Docker container). An ECS Service
# is ultimately made up of zero or more ECS Tasks.
#
# For example purposes, we will define a path-based routing rule
# ---------------------------------------------------------------------------------------------------------------------

# EXAMPLE OF A PATH-BASED LISTENER RULE
# Path-based Listener Rules are used when you wish to route all requests received by the ALB that match a certain
# "path" pattern to a given ECS Service. This is useful if you have one service that should receive all requests sent
# to /api and another service that receives requests sent to /customers.
resource "aws_alb_listener_rule" "path_based_example" {
  # Get the Listener ARN associated with port 80 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = module.alb.http_listener_arns["80"]

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
# CREATE THE NLB LISTENER ASSOCIATED WITH THIS ECS SERVICE
# When an TCP request is received by the NLB, how will the ALB know to route that request to this particular ECS Service?
# The answer is that we define NLB Listeners (https://goo.gl/vQv8oQ) that can route a request to a specific "Target
# Group" that contains "Targets". Each Target is actually an ECS Task (which is really just a Docker container). An ECS Service
# is ultimately made up of zero or more ECS Tasks.
#
# For example purposes, we will define one listener on each of the same ports that the ALB uses.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb_listener" "nlb" {
  for_each = local.listener_ports

  lifecycle {
    create_before_destroy = true
  }

  load_balancer_arn = aws_lb.nlb.arn
  port              = each.value
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = module.ecs_service.target_group_arns["nlb"]
  }
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
