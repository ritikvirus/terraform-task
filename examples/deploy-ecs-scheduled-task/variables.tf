# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# These variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region in which all resources will be created"
  type        = string
}

variable "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  type        = string
}

variable "ecs_cluster_instance_ami" {
  description = "The AMI to run on each instance in the ECS cluster"
  type        = string
}

variable "docker_image" {
  description = "The Docker image to run in the ECS Task (e.g. acme/my-container)"
  type        = string
}

variable "docker_image_version" {
  description = "The version of the Docker image in var.docker_image to run in the ECS Task (e.g. latest)"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# SCHEDULE PARAMETERS
# One of these variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

variable "task_schedule_expression" {
  description = ""
  type        = string
  default     = null
}

variable "task_event_pattern" {
  description = ""
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables may optionally be passed in by the operator, but they have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "ecs_cluster_instance_keypair_name" {
  description = "The name of the Key Pair that can be used to SSH to each instance in the ECS cluster"
  type        = string
  default     = null
}

variable "create_resources" {
  description = "If you set this variable to false, this module will not create any resources. This is used as a workaround because Terraform does not allow you to use the 'count' parameter on modules. By using this parameter, you can optionally create or not create the resources within this module."
  type        = bool
  default     = true
}

variable "ecs_target_group" {
  description = "Specifies an ECS task group for the task."
  type        = string
  default     = null
}

variable "ecs_target_launch_type" {
  description = "Specifies the launch type on which your task is running."
  type        = string
  default     = null
}

variable "ecs_target_platform_version" {
  description = "Specifies the platform version for the task."
  type        = string
  default     = null
}

variable "ecs_target_task_count" {
  description = "The number of tasks to create based on the TaskDefinition."
  type        = number
  default     = 1
}

variable "ecs_target_propagate_tags" {
  description = "Specifies whether to propagate the tags from the task definition to the task."
  type        = string
  default     = null
}

variable "ecs_target_enable_execute_command" {
  description = "Whether or not to enable the execute command functionality for the containers in this task."
  type        = bool
  default     = null
}

variable "enable_ecs_managed_tags" {
  description = "Specifies whether to enable Amazon ECS managed tags for the task."
  type        = bool
  default     = null
}

## See module README for additional references on configuring the network configuration block.
variable "ecs_target_network_configuration" {
  description = "Object that defines the target network configuration."
  default     = null
}

## See module README for additional references on configuring the placement constraints block.
variable "ecs_target_placement_constraints" {
  description = "An array of placement constraint objects to use for the task."
  type        = list(map(string))
  default     = []
}

# See module README for additional references on configuring the container override input.
variable "ecs_target_container_overrides" {
  description = "String of JSON that defines container overrides that are passed to the task."
  type        = string
  default     = null
}

variable "docker_image_command" {
  description = "The command to run in the Docker image."
  type        = list(string)
  # Example:
  default = ["echo", "Hello"]
}

variable "ecs_task_network_mode" {
  description = ""
  type        = string
  default     = null
}
