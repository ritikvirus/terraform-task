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

variable "docker_image_command" {
  description = "The command to run in the Docker image."
  type        = list(string)
  # Example:
  # default = ["echo", "Hello"]
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

variable "instance_types" {
  description = "instance type"
  type        = list(string)
}