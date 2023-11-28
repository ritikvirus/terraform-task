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
# CREATE A VPC WITH NAT GATEWAY
# We will provision a new VPC because awsvpc networking mode for EC2 launch type requires usage of the private subnet,
# which is not available in the default VPC.
# ---------------------------------------------------------------------------------------------------------------------

module "vpc" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-vpc.git//modules/vpc-app?ref=v0.23.1"

  vpc_name   = var.service_name
  aws_region = var.aws_region

  # The IP address range of the VPC in CIDR notation. A prefix of /18 is recommended. Do not use a prefix higher
  # than /27.
  cidr_block = "10.0.0.0/18"

  # The number of NAT Gateways to launch for this VPC. For production VPCs, a NAT Gateway should be placed in each
  # Availability Zone (so likely 3 total), whereas for non-prod VPCs, just one Availability Zone (and hence 1 NAT
  # Gateway) will suffice. Warning: You must have at least this number of Elastic IP's to spare.  The default AWS
  # limit is 5 per region, but you can request more.
  num_nat_gateways = 1
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

  vpc_id         = module.vpc.vpc_id
  vpc_subnet_ids = module.vpc.private_app_subnet_ids
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

  http_listener_ports                    = [80, 5000]
  https_listener_ports_and_ssl_certs     = []
  https_listener_ports_and_acm_ssl_certs = []
  ssl_policy                             = "ELBSecurityPolicy-TLS-1-1-2017-01"

  vpc_id         = module.vpc.vpc_id
  vpc_subnet_ids = module.vpc.public_subnet_ids

  custom_tags = {
    Environment = "test"
  }
  depends_on = [module.vpc]
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

  service_name            = var.service_name
  desired_number_of_tasks = var.desired_number_of_tasks
  launch_type             = "EC2"

  ecs_cluster_arn = module.ecs_cluster.ecs_cluster_arn
  ecs_task_container_definitions = jsonencode([
    {
      name = var.container_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image     = "gruntwork/docker-test-webapp:latest"
      cpu       = 512
      memory    = 256
      essential = true
      portMappings = [{
        containerPort = var.container_http_port
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log_group_example.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.service_name
        }
      }
      environment = [{
        name  = "AWS_DEFAULT_REGION"
        value = var.aws_region
      }]
    }
  ])


  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  ecs_task_definition_network_mode = "awsvpc"
  ecs_service_network_configuration = {
    subnets          = module.vpc.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_task_security_group.id]
    assign_public_ip = false
  }

  elb_target_group_deregistration_delay = 30

  elb_target_groups = {
    alb = {
      name                  = var.service_name
      container_name        = var.container_name
      container_port        = var.container_http_port
      protocol              = "HTTP"
      health_check_protocol = "HTTP"
    }
  }
  elb_target_group_vpc_id = module.vpc.vpc_id
  elb_slow_start          = 30

  use_auto_scaling                 = false
  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  # Make sure all the ECS cluster and ALB resources are deployed before deploying any ECS service resources. This is
  # also necessary to avoid issues on 'destroy'.
  depends_on = [module.ecs_cluster, module.alb, module.vpc]

  # Explicit dependency to aws_alb_listener_rules to make sure listeners are created before deploying any ECS services
  # and avoid any race condition.
  listener_rule_ids = [
    aws_alb_listener_rule.path_based_example.id
  ]
}

resource "aws_cloudwatch_log_group" "log_group_example" {
  name = var.service_name
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP FOR THE AWSVPC TASK NETWORK
# Allow all inbound access on the container port from ALB and any outbound access
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "ecs_task_security_group" {
  name   = "${var.service_name}-task-access"
  vpc_id = module.vpc.vpc_id
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
  security_group_id        = aws_security_group.ecs_task_security_group.id
  type                     = "ingress"
  from_port                = var.container_http_port
  to_port                  = var.container_http_port
  protocol                 = "tcp"
  source_security_group_id = module.alb.alb_security_group_id
}


# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALB LISTENER RULES ASSOCIATED WITH THIS ECS SERVICE
# When an HTTP request is received by the ALB, how will the ALB know to route that request to this particular ECS Service?
# The answer is that we define ALB Listener Rules (https://goo.gl/vQv8oQ) that can route a request to a specific "Target
# Group" that contains "Targets". Each Target is actually an ECS Task (which is really just a Docker container). An ECS Service
# is ultimately made up of zero or more ECS Tasks.
#
# For example purposes, we will define a path-based routing rule.
# ---------------------------------------------------------------------------------------------------------------------

# EXAMPLE OF A PATH-BASED LISTENER RULE
# Path-based Listener Rules are used when you wish to route all requests received by the ALB that match a certain
# "path" pattern to a given ECS Service. This is useful if you have one service that should receive all requests sent
# to /api and another service that receives requests sent to /customers.
resource "aws_alb_listener_rule" "path_based_example" {
  # Get the Listener ARN associated with port 5000 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
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
