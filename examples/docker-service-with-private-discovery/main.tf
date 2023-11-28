# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKER CLUSTER WITH SERVICE DISCOVERY
# This is an example of how to deploy a Docker cluster with service discovery
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
  #source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-cluster?ref=v0.6.4"
  source = "../../modules/ecs-cluster"

  cluster_name                      = var.ecs_cluster_name
  cluster_min_size                  = 2
  cluster_max_size                  = 2
  cluster_instance_ami              = var.ecs_cluster_instance_ami
  cluster_instance_type             = module.instance_type.recommended_instance_type
  cluster_instance_keypair_name     = var.ecs_cluster_instance_keypair_name
  cluster_instance_user_data        = local.user_data
  enable_cluster_container_insights = true
  use_imdsv1                        = false

  vpc_id         = var.vpc_id
  vpc_subnet_ids = var.private_subnet_ids
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
# CREATE THE DOCKER CONTAINER DEFINITION WE WANT TO RUN IN OUR ECS TASK
# ---------------------------------------------------------------------------------------------------------------------

locals {
  container_definition = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.service_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image        = "gruntwork/docker-test-webapp"
      version      = "latest"
      server_text  = var.server_text
      aws_region   = var.aws_region
      s3_test_file = "s3://${aws_s3_bucket.s3_test_bucket.id}/${var.s3_test_file_name}"
      cpu          = 256
      memory       = 256
      # We don't need to define the host port.
      # For awsvpc tasks, the container port is the same one exposed to the network interface
      container_http_port = var.container_http_port
      command             = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A DNS HOSTNAME TO NAMESPACE THE SERVICE
# You can have multiple services using the same namespace
# In this example we are creating a private namespace
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_service_discovery_private_dns_namespace" "namespace" {
  name = var.discovery_namespace_name
  vpc  = var.vpc_id
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
  desired_number_of_tasks        = 2

  # Network information is necessary for service discovery with awsvpc tasks
  ecs_task_definition_network_mode = "awsvpc"
  ecs_service_network_configuration = {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_task_security_group.id]
    assign_public_ip = false
  }

  # Discovery information
  use_service_discovery  = true
  discovery_namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
  discovery_name         = var.service_name
  discovery_dns_ttl      = 10

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  # Make sure all the ECS cluster resources are deployed before deploying any ECS service resources. This is also
  # necessary to avoid issues on 'destroy'.
  depends_on = [module.ecs_cluster]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP FOR THE AWSVPC TASK NETWORK FOR OUTBOUND ACCESS
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "ecs_task_security_group" {
  name   = "${var.service_name}-task-access"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "allow_outbound_all" {
  security_group_id = aws_security_group.ecs_task_security_group.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_inbound_on_container_port_from_within_cluster" {
  security_group_id        = aws_security_group.ecs_task_security_group.id
  type                     = "ingress"
  from_port                = var.container_http_port
  to_port                  = var.container_http_port
  protocol                 = "tcp"
  source_security_group_id = module.ecs_cluster.ecs_instance_security_group_id
}

resource "aws_security_group_rule" "allow_inbound_on_container_port_from_bastion" {
  security_group_id        = aws_security_group.ecs_task_security_group.id
  type                     = "ingress"
  from_port                = var.container_http_port
  to_port                  = var.container_http_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ssh_host.id
}


# ---------------------------------------------------------------------------------------------------------------------
# CREATE A EC2 INSTANCE JUMP HOST FOR TESTING PURPOSES
# Because all the resources are hidden in a private subnet on the VPC, we need some way to access it from the outside
# for testing purposes. We do this by creating a bastion host in the public subnet that we can use to SSH into, and
# access the service DNS record and application from there.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "ssh_host" {
  name   = "${var.service_name}-ssh-host"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "ssh_host_allow_outbound_all" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.ssh_host.id
}

# Allowing SSH from anywhere for test purposes only, this should not be done in prod
resource "aws_security_group_rule" "allow_inbound_ssh_from_anywhere" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.ssh_host.id
}

resource "aws_instance" "ssh_host" {
  ami                         = var.ecs_cluster_instance_ami
  instance_type               = module.instance_type.recommended_instance_type
  key_name                    = var.ecs_cluster_instance_keypair_name
  vpc_security_group_ids      = [aws_security_group.ssh_host.id]
  subnet_id                   = element(var.public_subnet_ids, 0)
  associate_public_ip_address = true
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
