# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER APP
# These templates show an example of how to run a Docker app on top of Amazon's Fargate Service
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

  # Configure ALB
  elb_target_groups = {
    alb = {
      name                  = var.service_name
      container_name        = var.container_name
      container_port        = var.http_port
      protocol              = "HTTP"
      health_check_protocol = "HTTP"
    }
  }
  elb_target_group_vpc_id = data.aws_vpc.default.id
  elb_slow_start          = 30

  # Give the container 30 seconds to boot before having the ALB start checking health
  health_check_grace_period_seconds = 30
  health_check_interval             = var.health_check_interval

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  deployment_circuit_breaker = {
    enable   = var.deployment_circuit_breaker_enabled
    rollback = var.deployment_circuit_breaker_rollback
  }

  # Make sure all the ECS cluster and ALB resources are deployed before deploying any ECS service resources. This is
  # also necessary to avoid issues on 'destroy'.
  depends_on = [aws_ecs_cluster.fargate_cluster, module.alb]

  # Explicit dependency to aws_alb_listener_rules to make sure listeners are created before deploying any ECS services
  # and avoid any race condition.
  listener_rule_ids = [
    aws_alb_listener_rule.host_based_example.id,
    aws_alb_listener_rule.host_based_path_based_example.id,
    aws_alb_listener_rule.path_based_example.id
  ]
}

# This local defines the Docker containers we want to run in our ECS Task
locals {
  container_definition = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.container_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image          = "gruntwork/docker-test-webapp"
      version        = "latest"
      server_text    = var.server_text
      aws_region     = var.aws_region
      s3_test_file   = "s3://${aws_s3_bucket.s3_test_bucket.id}/${var.s3_test_file_name}"
      cpu            = 256
      memory         = 512
      awslogs_group  = var.service_name
      awslogs_region = var.aws_region
      awslogs_prefix = var.service_name
      # The container and host must listen on the same port for Fargate
      container_http_port = var.http_port
      command             = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
      boot_delay_seconds  = var.container_boot_delay_seconds
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
  count   = var.skip_s3_test_file_creation ? 0 : 1
  bucket  = aws_s3_bucket.s3_test_bucket.id
  key     = var.s3_test_file_name
  content = "world!"
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH AN IAM POLICY TO THE TASK THAT ALLOWS THE ECS SERVICE TO ACCESS THE S3 BUCKET FOR TESTING PURPOSES
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
  roles      = [module.fargate_service.ecs_task_iam_role_name]
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

# --------------------------------------------------------------------------------------------------------------------
# CREATE AN EXAMPLE CLOUDWATCH LOG GROUP
# --------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "log_group_example" {
  name = var.service_name
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALB LISTENER RULES ASSOCIATED WITH THIS ECS SERVICE
# When an HTTP request is received by the ALB, how will the ALB know to route that request to this particular ECS Service?
# The answer is that we define ALB Listener Rules (https://goo.gl/vQv8oQ) that can route a request to a specific "Target
# Group" that contains "Targets". Each Target is actually an ECS Task (which is really just a Docker container). An ECS Service
# is ultimately made up of zero or more ECS Tasks.
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
    target_group_arn = module.fargate_service.target_group_arns["alb"]
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
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = module.alb.http_listener_arns["5000"]

  priority = 100

  action {
    type             = "forward"
    target_group_arn = module.fargate_service.target_group_arns["alb"]
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
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = module.alb.http_listener_arns["5000"]

  priority = 105

  action {
    type             = "forward"
    target_group_arn = module.fargate_service.target_group_arns["alb"]
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
# ASSOCIATE A DNS RECORD WITH OUR ALB
# This way we can test the host-based routing properly.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_route53_zone" "sample" {
  name = var.route53_hosted_zone_name
  tags = var.route53_tags
}

resource "aws_route53_record" "alb_endpoint" {
  zone_id = data.aws_route53_zone.sample.zone_id
  name    = "${var.service_name}.${data.aws_route53_zone.sample.name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_hosted_zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ROUTE53 DOMAIN NAME TO BE ASSOCIATED WITH THIS ECS SERVICE
# The Route53 Resource Record Set (DNS record) will point to the ALB.
# ---------------------------------------------------------------------------------------------------------------------

# Create a Route53 Private Hosted Zone ID
# In production, this template would be a poor place to create this resource, but we'll need it for testing purposes.
resource "aws_route53_zone" "for_testing" {
  name = "${var.service_name}.albtest"

  vpc {
    vpc_id = data.aws_vpc.default.id
  }
}

# Create a DNS Record in Route53 for the ECS Service
# - We are creating a Route53 "alias" record to take advantage of its unique benefits such as instant updates when an
#   ALB's underlying nodes change.
# - We set alias.evaluate_target_health to false because Amazon uses these health checks to determine if, in a complex
#   DNS routing tree, it should "back out" of using this DNS Record in favor of another option, and we do not expect
#   such a complex routing tree to be in use here.
resource "aws_route53_record" "fargate_service" {
  zone_id = aws_route53_zone.for_testing.id
  name    = "service.${var.service_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_hosted_zone_id
    evaluate_target_health = false
  }
}
