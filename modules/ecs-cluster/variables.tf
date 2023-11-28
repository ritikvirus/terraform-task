# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

# General ECS Cluster properties
variable "cluster_name" {
  description = "The name of the ECS cluster (e.g. ecs-prod). This is used to namespace all the resources created by these templates."
  type        = string
}

variable "cluster_min_size" {
  description = "The minimum number of EC2 Instances launchable for this ECS Cluster. Useful for auto-scaling limits."
  type        = number
}

variable "cluster_max_size" {
  description = "The maximum number of EC2 Instances that must be running for this ECS Cluster. We recommend making this twice var.cluster_min_size, even if you don't plan on scaling the cluster up and down, as the extra capacity will be used to deploy udpates to the cluster."
  type        = number
}

# Properties of the ECS Cluster's EC2 Instances
variable "cluster_instance_ami" {
  description = "The AMI to run on each of the ECS Cluster's EC2 Instances."
  type        = string
}

variable "cluster_instance_type" {
  description = "The type of EC2 instance to run for each of the ECS Cluster's EC2 Instances (e.g. t2.medium)."
  type        = string
}

variable "cluster_instance_root_volume_size" {
  description = "The size in GB of the root volume for each of the ECS Cluster's EC2 Instances"
  type        = number
  default     = 40
}

variable "cluster_instance_root_volume_type" {
  description = "The volume type for the root volume for each of the ECS Cluster's EC2 Instances. Can be standard, gp2, or io1"
  type        = string
  default     = "gp2"
}

variable "cluster_instance_root_volume_encrypted" {
  description = "Set to true to encrypt the root block devices for the ECS cluster's EC2 instances"
  type        = bool
  default     = false
}

variable "cluster_instance_keypair_name" {
  description = "The EC2 Keypair name used to SSH into the ECS Cluster's EC2 Instances."
  type        = string
}

variable "cluster_instance_request_spot_instances" {
  description = "Set to true to request spot instances. Set cluster_instance_spot_price variable to set a maximum spot price limit."
  type        = bool
  default     = false
}

variable "cluster_instance_spot_price" {
  description = "Value is the maximum bid price for the instance on the EC2 Spot Market."
  type        = string
  default     = null
}

variable "cluster_detailed_monitoring" {
  description = "Enables/disables detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
}

variable "cluster_instance_associate_public_ip_address" {
  description = "Passthrough to aws_launch_template resource.  Associate a public ip address with EC2 instances in cluster"
  type        = bool
  default     = false
}

variable "cluster_instance_ebs_optimized" {
  description = "If true, the launched EC2 instance will be EBS-optimized"
  type        = bool
  default     = false
}

# Customization of IAM names

variable "custom_iam_role_name" {
  description = "When set, name the IAM role for the ECS cluster using this variable. When null, the IAM role name will be derived from var.cluster_name."
  type        = string
  default     = null
}

# Info about the VPC in which this Cluster resides

variable "vpc_id" {
  description = "The ID of the VPC in which the ECS Cluster's EC2 Instances will reside."
  type        = string
}

variable "vpc_subnet_ids" {
  description = "A list of the subnets into which the ECS Cluster's EC2 Instances will be launched. These should usually be all private subnets and include one in each AWS Availability Zone."
  type        = list(string)
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

# User data scripts

variable "cluster_instance_user_data" {
  description = "The User Data script to run on each of the ECS Cluster's EC2 Instances on their first boot."
  type        = string
  default     = null
}

variable "cluster_instance_user_data_base64" {
  description = "The base64-encoded User Data script to run on the server when it is booting. This can be used to pass binary User Data, such as a gzipped cloud-init script. If you wish to pass in plain text (e.g., typical Bash script) for User Data, use var.cluster_instance_user_data instead."
  type        = string
  default     = null
}

# Worker configuration

variable "ssh_port" {
  description = "The port to use for SSH access."
  type        = number
  default     = 22
}

variable "allow_ssh_from_cidr_blocks" {
  description = "The IP address ranges in CIDR format from which to allow incoming SSH requests to the ECS instances."
  type        = list(string)
  default     = []
}

variable "allow_ssh_from_security_group_ids" {
  description = "The IDs of security groups from which to allow incoming SSH requests to the ECS instances."
  type        = list(string)
  default     = []
}

variable "alb_security_group_ids" {
  description = "A list of Security Group IDs of the ALBs which will send traffic to this ECS Cluster."
  type        = list(string)
  default     = []
}

variable "tenancy" {
  description = "The tenancy of the servers in this cluster. Must be one of: default, dedicated, or host."
  type        = string
  default     = "default"
}

variable "enable_imds" {
  description = "Set this variable to true to enable the Instance Metadata Service (IMDS) endpoint, which is used to fetch information such as user-data scripts, instance IP address and region, etc. Set this variable to false if you do not want the IMDS endpoint enabled for instances launched into the Auto Scaling Group for the workers."
  type        = bool
  default     = true
}

variable "use_imdsv1" {
  description = "Set this variable to true to enable the use of Instance Metadata Service Version 1 in this module's aws_launch_template. Note that while IMDsv2 is preferred due to its special security hardening, we allow this in order to support the use case of AMIs built outside of these modules that depend on IMDSv1."
  type        = bool
  default     = true
}

variable "http_put_response_hop_limit" {
  description = "The desired HTTP PUT response hop limit for instance metadata requests."
  type        = number
  default     = null
}

variable "custom_tags_ecs_cluster" {
  description = "Custom tags to apply to the ECS cluster"
  type        = map(string)
  default     = {}
}

variable "custom_tags_ec2_instances" {
  description = "A list of custom tags to apply to the EC2 Instances in this ASG. Each item in this list should be a map with the parameters key, value, and propagate_at_launch."
  type = list(
    object({
      key                 = string
      value               = string
      propagate_at_launch = bool
    })
  )
  default = []
  # Example:
  # default = [
  #   {
  #     key = "foo"
  #     value = "bar"
  #     propagate_at_launch = true
  #   },
  #   {
  #     key = "baz"
  #     value = "blah"
  #     propagate_at_launch = true
  #   }
  # ]
}

variable "custom_tags_security_group" {
  description = "A map of custom tags to apply to the Security Group for this ECS Cluster. The key is the tag name and the value is the tag value."
  type        = map(string)
  default     = {}
  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }
}

variable "termination_policies" {
  description = "A list of policies to decide how the instances in the auto scale group should be terminated. The allowed values are OldestInstance, NewestInstance, OldestLaunchConfiguration, ClosestToNextInstanceHour, OldestLaunchTemplate, AllocationStrategy, Default. If you specify more than one policy, the ASG will try each one in turn, use it to select the instance(s) to terminate, and if more than one instance matches the criteria, then use the next policy to try to break the tie. E.g., If you use ['OldestInstance', 'ClosestToNextInstanceHour'] and and there were two instances with exactly the same launch time, then the ASG would try the next policy, which is to terminate the one closest to the next instance hour in billing."
  type        = list(string)
  default     = ["OldestInstance"]
}

variable "autoscaling_termination_protection" {
  description = "Protect EC2 instances running ECS tasks from being terminated due to scale in (spot instances do not support lifecycle modifications)"
  type        = bool
  default     = false
}

variable "capacity_provider_enabled" {
  description = "Enable a capacity provider to autoscale the EC2 ASG created for this ECS cluster"
  type        = bool
  default     = false
}

variable "multi_az_capacity_provider" {
  description = "Enable a multi-az capacity provider to autoscale the EC2 ASGs created for this ECS cluster, only if capacity_provider_enabled = true"
  type        = bool
  default     = false
}

variable "capacity_provider_target" {
  description = "Target cluster utilization for the capacity provider; a number from 1 to 100."
  type        = number
  default     = 75
}

variable "capacity_provider_max_scale_step" {
  description = "Maximum step adjustment size to the ASG's desired instance count"
  type        = number
  default     = 10
}

variable "capacity_provider_min_scale_step" {
  description = "Minimum step adjustment size to the ASG's desired instance count"
  type        = number
  default     = 1
}

variable "cluster_asg_metrics_enabled" {
  description = "A list of metrics to collect. The allowed values are GroupDesiredCapacity, GroupInServiceCapacity, GroupPendingCapacity, GroupMinSize, GroupMaxSize, GroupInServiceInstances, GroupPendingInstances, GroupStandbyInstances, GroupStandbyCapacity, GroupTerminatingCapacity, GroupTerminatingInstances, GroupTotalCapacity, GroupTotalInstances."
  type        = list(string)
  default     = []
}

variable "enable_cluster_container_insights" {
  description = "Whether or not to enable Container Insights on the ECS cluster. Refer to https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cloudwatch-container-insights.html for more information on ECS Container Insights."
  type        = bool

  # We intentionally default this to false. While Container Insights provides useful metrics, the costs can add up
  # depending on how large your clusters are. Specifically, Container Insights will add:
  # - 8 custom metrics per ECS cluster
  # - 6 custom metrics per ECS task
  # - 11 custom metrics per ECS service
  # Each metric costs $0.30 per month up to 10,000 metrics, at which point the costs start to drop. Refer to
  # https://aws.amazon.com/cloudwatch/pricing/ for more details.
  default = false
}

variable "create_resources" {
  description = "If you set this variable to false, this module will not create any resources. This is used as a workaround because Terraform does not allow you to use the 'count' parameter on modules. By using this parameter, you can optionally create or not create the resources within this module."
  type        = bool
  default     = true
}

variable "cluster_instance_role_permissions_boundary_arn" {
  description = "The ARN of the policy that is used to set the permissions boundary for the IAM role for the cluster instances."
  type        = string
  default     = null
}

# Launch template placement group configurations

variable "cluster_instance_placement_affinity" {
  description = "The affinity setting for an instance on a Dedicated Host."
  type        = string
  default     = null
}

variable "cluster_instance_placement_group_name" {
  description = "The name of the placement group for the instance."
  type        = string
  default     = null
}

variable "cluster_instance_placement_host_id" {
  description = "The ID of the Dedicated Host for the instance."
  type        = string
  default     = null
}

variable "cluster_instance_placement_host_resource_group_arn" {
  description = "The ARN of the Host Resource Group in which to launch instances."
  type        = string
  default     = null
}

variable "cluster_instance_placement_partition_number" {
  description = "The number of the partition the instance should launch in. Valid only if the placement group strategy is set to partition."
  type        = number
  default     = null
}

# Launch template market option configurations

variable "enable_block_device_mappings" {
  description = "Enables additional block device mapping. Change to false if you wish to disable additional EBS volume attachment to EC2 instances. Defaults to true."
  type        = bool
  default     = true
}

variable "cluster_instance_market_block_duration_minutes" {
  description = "The required duration in minutes. This value must be a multiple of 60."
  type        = number
  default     = null
}

variable "cluster_instance_market_instance_interruption_behavior" {
  description = "The behavior when a Spot Instance is interrupted. Can be hibernate, stop, or terminate. (Default: terminate)."
  type        = string
  default     = "terminate"
}

variable "cluster_instance_market_spot_instance_type" {
  description = "The Spot Instance request type. Can be one-time, or persistent."
  type        = string
  default     = null
}

variable "cluster_instance_market_valid_until" {
  description = "The end date of the request."
  type        = string
  default     = null
}

# Launch template block device configurations

variable "cluster_instance_block_device_name" {
  description = "The name of the device to mount."
  type        = string
  default     = "/dev/xvdcz"

}

variable "cluster_instance_ebs_delete_on_termination" {
  description = "Whether the volume should be destroyed on instance termination. Defaults to false"
  type        = bool
  default     = false

}

variable "cluster_instance_ebs_iops" {
  description = "The amount of provisioned IOPS. This must be set with a volume_type of io1/io2."
  type        = string
  default     = null

}

variable "cluster_instance_ebs_kms_key_id" {
  description = "The ARN of the AWS Key Management Service (AWS KMS) customer master key (CMK) to use when creating the encrypted volume. The variable cluster_instance_root_volume_encrypted must be set to true when this is set."
  type        = string
  default     = null
}

variable "cluster_instance_ebs_snapshot_id" {
  description = "The Snapshot ID to mount."
  type        = string
  default     = null
}

variable "cluster_instance_ebs_throughput" {
  description = "The throughput to provision for a gp3 volume in MiB/s (specified as an integer, e.g., 500), with a maximum of 1,000 MiB/s."
  type        = number
  default     = null
}

variable "max_instance_lifetime" {
  description = "Maximum amount of time, in seconds, that an instance can be in service, values must be either equal to 0 or between 86400 and 31536000 seconds."
  type        = number
  default     = null
}
