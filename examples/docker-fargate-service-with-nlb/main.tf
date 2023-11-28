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

  # Configure NLB
  elb_target_groups = {
    nlb = {
      name                  = var.service_name
      container_name        = var.service_name
      container_port        = var.http_port
      protocol              = "TCP"
      health_check_protocol = "TCP"
    }
  }
  elb_target_group_vpc_id = data.aws_vpc.default.id

  health_check_healthy_threshold   = 5
  health_check_unhealthy_threshold = 5

  # Give the container 30 seconds to boot before having the NLB start checking health
  health_check_grace_period_seconds = 30

  health_check_interval = var.health_check_interval

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  # Make sure all the ECS cluster and NLB resources are deployed before deploying any ECS service resources. This is
  # also necessary to avoid issues on 'destroy'.
  depends_on = [aws_ecs_cluster.fargate_cluster, aws_lb.nlb]
}

# This local defines the Docker containers we want to run in our ECS Task
locals {
  container_definition = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.service_name
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
      # Container and host mmust listen on the same port for Fargate
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

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN NLB TO ROUTE TRAFFIC ACROSS THE ECS TASKS
# Typically, this would be created once for use with many different ECS Services.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb" "nlb" {
  name                             = var.service_name
  internal                         = false
  load_balancer_type               = "network"
  enable_cross_zone_load_balancing = false
  ip_address_type                  = "ipv4"
  subnets                          = data.aws_subnets.default.ids
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

# --------------------------------------------------------------------------------------------------------------------
# CREATE AN EXAMPLE CLOUDWATCH LOG GROUP
# --------------------------------------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "log_group_example" {
  name = var.service_name
}

# ---------------------------------------------------------------------------------------------------------------------
# GET VPC AND SUBNET INFO FROM TERRAFORM DATA SOURCE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    target_group_arn = module.fargate_service.target_group_arns["nlb"]
    type             = "forward"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ASSOCIATE A DNS RECORD WITH OUR NLB
# This way we can test the host-based routing properly.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_route53_zone" "sample" {
  name = var.route53_hosted_zone_name
}

resource "aws_route53_record" "nlb_endpoint" {
  zone_id = data.aws_route53_zone.sample.zone_id
  name    = "${var.service_name}.${data.aws_route53_zone.sample.name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ROUTE53 DOMAIN NAME TO BE ASSOCIATED WITH THIS FARGATE SERVICE
# The Route53 Resource Record Set (DNS record) will point to the NLB.
# ---------------------------------------------------------------------------------------------------------------------

# Create a Route53 Private Hosted Zone ID
# In production, this template would be a poor place to create this resource, but we'll need it for testing purposes.
resource "aws_route53_zone" "for_testing" {
  name = "${var.service_name}.nlbtest"

  vpc {
    vpc_id = data.aws_vpc.default.id
  }
}

# Create a DNS Record in Route53 for the ECS Service
# - We are creating a Route53 "alias" record to take advantage of its unique benefits such as instant updates when an
#   NLB's underlying nodes change.
# - We set alias.evaluate_target_health to false because Amazon uses these health checks to determine if, in a complex
#   DNS routing tree, it should "back out" of using this DNS Record in favor of another option, and we do not expect
#   such a complex routing tree to be in use here.
resource "aws_route53_record" "fargate_service" {
  zone_id = aws_route53_zone.for_testing.id
  name    = "service.${var.service_name}"
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = false
  }
}
