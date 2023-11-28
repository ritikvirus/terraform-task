# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE AN EC2 CONTAINER SERVICE (ECS) CLUSTER
# These templates launch an ECS cluster you can use for running Docker containers. The cluster includes:
# - Auto Scaling Group (ASG)
# - Launch template
# - Security group
# - IAM roles and policies
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.75.1, < 6.0.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS CLUSTER ENTITY
# Amazon's ECS Service requires that we create an entity called a "cluster". We will then register EC2 Instances with
# that cluster.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ecs_cluster" "ecs" {
  count = var.create_resources ? 1 : 0
  name  = var.cluster_name
  tags  = var.custom_tags_ecs_cluster

  dynamic "setting" {
    # The content of the for_each attribute does not matter, as it is only used to indicate if this block should be
    # enabled or not.
    for_each = var.enable_cluster_container_insights ? ["enabled"] : []
    content {
      name  = "containerInsights"
      value = "enabled"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS CLUSTER AUTO SCALING GROUP (ASG)
# The ECS Cluster's EC2 Instances (known in AWS as "Container Instances") exist in an Auto Scaling Group so that failed
# instances will automatically be replaced, and we can easily scale the cluster's resources.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_autoscaling_group" "ecs" {
  count = local.auto_scaling_group_count

  name     = local.auto_scaling_group_count == 1 ? var.cluster_name : "${var.cluster_name}-${count.index}"
  min_size = var.cluster_min_size
  max_size = var.cluster_max_size

  launch_template {
    id      = aws_launch_template.ecs[0].id
    version = aws_launch_template.ecs[0].latest_version
  }

  vpc_zone_identifier   = local.auto_scaling_group_count == 1 ? var.vpc_subnet_ids : [var.vpc_subnet_ids[count.index]]
  termination_policies  = var.termination_policies
  protect_from_scale_in = var.autoscaling_termination_protection
  enabled_metrics       = var.cluster_asg_metrics_enabled
  max_instance_lifetime = var.max_instance_lifetime

  dynamic "tag" {
    for_each = concat(local.default_tags, var.custom_tags_ec2_instances)
    content {
      key                 = tag.value.key
      value               = tag.value.value
      propagate_at_launch = tag.value.propagate_at_launch
    }
  }
}

resource "aws_launch_template" "ecs" {
  count = var.create_resources ? 1 : 0

  name_prefix   = "${var.cluster_name}-"
  image_id      = var.cluster_instance_ami
  instance_type = var.cluster_instance_type
  key_name      = var.cluster_instance_keypair_name
  user_data     = local.user_data
  ebs_optimized = var.cluster_instance_ebs_optimized

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs[0].name
  }

  placement {
    tenancy                 = var.tenancy
    affinity                = var.cluster_instance_placement_affinity
    group_name              = var.cluster_instance_placement_group_name
    host_id                 = var.cluster_instance_placement_host_id
    host_resource_group_arn = var.cluster_instance_placement_host_resource_group_arn
    partition_number        = var.cluster_instance_placement_partition_number
  }

  dynamic "instance_market_options" {
    for_each = var.cluster_instance_request_spot_instances ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price                      = var.cluster_instance_spot_price
        block_duration_minutes         = var.cluster_instance_market_block_duration_minutes
        instance_interruption_behavior = var.cluster_instance_market_instance_interruption_behavior
        spot_instance_type             = var.cluster_instance_market_spot_instance_type
        valid_until                    = var.cluster_instance_market_valid_until
      }
    }
  }

  network_interfaces {
    associate_public_ip_address = var.cluster_instance_associate_public_ip_address
    security_groups             = [aws_security_group.ecs[0].id]
  }

  monitoring {
    enabled = var.cluster_detailed_monitoring
  }

  dynamic "block_device_mappings" {
    for_each = var.enable_block_device_mappings ? [1] : []
    content {
      device_name = var.cluster_instance_block_device_name
      ebs {
        volume_size           = var.cluster_instance_root_volume_size
        volume_type           = var.cluster_instance_root_volume_type
        encrypted             = var.cluster_instance_root_volume_encrypted
        delete_on_termination = var.cluster_instance_ebs_delete_on_termination
        iops                  = var.cluster_instance_ebs_iops
        kms_key_id            = var.cluster_instance_ebs_kms_key_id
        snapshot_id           = var.cluster_instance_ebs_snapshot_id
        throughput            = var.cluster_instance_ebs_throughput
      }
    }
  }

  # metadata_options allow you to configure the behavior of the Instance Metadata Service (IMDS).
  # See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html for more information
  #
  # Note the user-data.sh scripts in this repo's examples have been updated to require use of IMDSv2, yet we provide this escape
  # hatch in order to avoid breaking AMIs that were created outside of our modules that might require IMDSv1
  #
  # To allow the use of IMDSv1 AND IMDSv2 (which is required for openvpn to work properly)
  # 1. set var.use_imdsv1 variable to true
  # 2. set var.enable_imds to true
  #
  # To allow the use of IMDSv2 only:
  # 1. set var.enable_imds to true
  # 2. set var.use_imdsv1 to false
  #
  metadata_options {
    http_endpoint = (var.enable_imds ? "enabled" : "disabled")
    # HTTP tokens are required by IMDS version 2. Therefore, setting this value to "optional" means that both IMDSv1 and IMDSv2 can be used
    # whereas "required" means that only IMDSv2 will be available
    http_tokens                 = (var.enable_imds && var.use_imdsv1 ? "optional" : "required")
    http_put_response_hop_limit = var.http_put_response_hop_limit
  }
}

# Capacity providers for the cluster to enable autoscaling.
resource "aws_ecs_capacity_provider" "capacity_provider" {
  count = local.capacity_provider_count

  name = (
    local.capacity_provider_count == 1
    ? "capacity-${var.cluster_name}"
    : "capacity-${var.cluster_name}-${count.index}"
  )

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs[count.index].arn
    managed_termination_protection = var.autoscaling_termination_protection ? "ENABLED" : "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = var.capacity_provider_max_scale_step
      minimum_scaling_step_size = var.capacity_provider_min_scale_step
      status                    = "ENABLED"
      target_capacity           = var.capacity_provider_target
    }
  }
}

# When enabled, create this resource only once to capture capacity providers and associate this resource with the ECS
# cluster.
resource "aws_ecs_cluster_capacity_providers" "this" {
  count = (
    var.create_resources && local.capacity_provider_count > 0
    ? 1
    : 0
  )

  cluster_name = aws_ecs_cluster.ecs[0].name

  capacity_providers = aws_ecs_capacity_provider.capacity_provider[*].name

  dynamic "default_capacity_provider_strategy" {
    for_each = aws_ecs_capacity_provider.capacity_provider
    iterator = capacity_provider

    content {
      capacity_provider = capacity_provider.value.name
      weight            = 1
    }
  }
}

# Base64 encode user data input, compute the list of default tags to apply to the cluster, as well as the number of capacity providers and auto-scaling
# groups based on the configuration (either no capacity provider, one capacity provider, or one capacity provider with
# one auto-scaling group per subnet/availability group https://docs.aws.amazon.com/AmazonECS/latest/developerguide/asg-capacity-providers.html)
locals {

  # Launch templates do not support non-base64 user data input - for backwards compatability keep the existing vars, but 
  # encode the non-base64 input if the base64 input is not provided. If both var inputs are null, set user_data input to null
  user_data = (
    var.cluster_instance_user_data_base64 == null
    ? (
      var.cluster_instance_user_data == null
      ? null
      : base64encode(var.cluster_instance_user_data)
    )
    : var.cluster_instance_user_data_base64
  )

  capacity_provider_count = (
    var.create_resources && var.capacity_provider_enabled
    ? (
      var.multi_az_capacity_provider
      ? length(var.vpc_subnet_ids)
      : 1
    )
    : 0
  )
  auto_scaling_group_count = (
    var.create_resources
    ? (
      var.capacity_provider_enabled && var.multi_az_capacity_provider
      ? length(var.vpc_subnet_ids)
      : 1
    )
    : 0
  )

  default_tags = concat([
    {
      key                 = "Name"
      value               = var.cluster_name
      propagate_at_launch = true
    },
    ],

    # When using capacity providers, ECS automatically adds the AmazonECSManaged tag to the ASG. Without this tag,
    # capacity providers don't work correctly. Therefore, we add this tag here to make sure it doesn't accidentally get
    # removed on follow-up calls to 'apply'.
    local.capacity_provider_count > 0
    ? [
      {
        key                 = "AmazonECSManaged"
        value               = ""
        propagate_at_launch = true
      }
    ]
    : []
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS CLUSTER INSTANCE SECURITY GROUP
# Limits which ports are allowed inbound and outbound. We export the security group id as an output so users of this
# module can add their own custom rules.
# ---------------------------------------------------------------------------------------------------------------------

# Note that we do not define ingress and egress rules inline. This is because consumers of this terraform module might
# want to add arbitrary rules to this security group. See:
# https://www.terraform.io/docs/providers/aws/r/security_group.html.
resource "aws_security_group" "ecs" {
  count = var.create_resources ? 1 : 0

  name        = var.cluster_name
  description = "For EC2 Instances in the ${var.cluster_name} ECS Cluster."
  vpc_id      = var.vpc_id
  tags        = var.custom_tags_security_group
}

# Allow all outbound traffic from the ECS Cluster
resource "aws_security_group_rule" "allow_outbound_all" {
  count             = var.create_resources ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs[0].id
}

# Allow inbound SSH traffic from the Security Group ID specified in var.allow_ssh_from_security_group_blocks.
resource "aws_security_group_rule" "allow_inbound_ssh_from_cidr" {
  count             = var.create_resources && length(var.allow_ssh_from_cidr_blocks) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  protocol          = "tcp"
  cidr_blocks       = var.allow_ssh_from_cidr_blocks
  security_group_id = aws_security_group.ecs[0].id
}

# Allow inbound SSH traffic from the Security Group ID specified in var.allow_ssh_from_security_group_ids.
resource "aws_security_group_rule" "allow_inbound_ssh_from_security_group" {
  count                    = var.create_resources ? length(var.allow_ssh_from_security_group_ids) : 0
  type                     = "ingress"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = var.allow_ssh_from_security_group_ids[count.index]
  security_group_id        = aws_security_group.ecs[0].id
}

# Allow inbound access from any ALBs that will send traffic to this ECS Cluster. We assume that the ALB will only send
# traffic to Docker containers that expose a port within the "ephemeral" port range. Per https://goo.gl/uLs9NY under
# "portMappings"/"hostPort", the ephemeral port range used by Docker will range from 32768 - 65535. It gives us pause
# to open such a wide port range, but dynamic Docker ports don't come without their costs!
resource "aws_security_group_rule" "allow_inbound_from_alb" {
  # Create one Security Group Rule for each ALB ARN specified in var.alb_arns.
  count = var.create_resources ? length(var.alb_security_group_ids) : 0

  type                     = "ingress"
  from_port                = 32768
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = var.alb_security_group_ids[count.index]
  security_group_id        = aws_security_group.ecs[0].id
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN IAM ROLE AND POLICIES FOR THE CLUSTER INSTANCES
# IAM Roles allow us to grant the cluster instances access to AWS Resources. We export the IAM role id so users of this
# module can add their own custom IAM policies.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "ecs" {
  count = var.create_resources ? 1 : 0
  name = (
    var.custom_iam_role_name == null
    ? "${var.cluster_name}-instance"
    : var.custom_iam_role_name
  )
  assume_role_policy   = data.aws_iam_policy_document.ecs_role.json
  permissions_boundary = var.cluster_instance_role_permissions_boundary_arn

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the ECS cluster cannot be
  # created because the IAM role does not exist. We add a 15 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 15 seconds to wait for IAM role to be created'; sleep 15"
  }
}

data "aws_iam_policy_document" "ecs_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# To assign an IAM Role to an EC2 instance, we need to create the intermediate concept of an "IAM Instance Profile".
resource "aws_iam_instance_profile" "ecs" {
  count = var.create_resources ? 1 : 0
  name = (
    var.custom_iam_role_name == null
    ? var.cluster_name
    : var.custom_iam_role_name
  )
  role = aws_iam_role.ecs[0].name
}

# IAM policy we add to our EC2 Instance Role that allows an ECS Agent running on the EC2 Instance to communicate with
# an ECS cluster.
resource "aws_iam_role_policy" "ecs" {
  count  = var.create_resources ? 1 : 0
  name   = "${var.cluster_name}-ecs-permissions"
  role   = aws_iam_role.ecs[0].id
  policy = data.aws_iam_policy_document.ecs_permissions.json
}

data "aws_iam_policy_document" "ecs_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "ecs:CreateCluster",
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:Submit*",
      "ecs:UpdateContainerInstancesState",
    ]

    resources = ["*"]
  }
}

# IAM policy we add to our EC2 Instance Role that allows ECS Instances to pull all containers from Amazon EC2 Container
# Registry.
resource "aws_iam_role_policy" "ecr" {
  count  = var.create_resources ? 1 : 0
  name   = "${var.cluster_name}-docker-login-for-ecr"
  role   = aws_iam_role.ecs[0].id
  policy = data.aws_iam_policy_document.ecr_permissions.json
}

data "aws_iam_policy_document" "ecr_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
    ]

    resources = ["*"]
  }
}
