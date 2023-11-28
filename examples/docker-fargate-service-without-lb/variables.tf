# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region in which all resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "service_name" {
  description = "The name of the ECS service to run"
  type        = string
  default     = "fargate-no-lb"
}

variable "http_port" {
  description = "The port on which the host and container listens on for HTTP requests"
  type        = number
  default     = 3000
}

variable "desired_number_of_tasks" {
  description = "How many instances of the container to schedule on the cluster"
  type        = number
  default     = 3
}

variable "server_text" {
  description = "The Docker container we run in this example will display this text for every request."
  type        = string
  default     = "Hello"
}

variable "s3_test_file_name" {
  description = "The name of the file to store in the S3 bucket. The ECS Task will try to download this file from S3 as a way to check that we are giving the Task the proper IAM permissions."
  type        = string
  default     = "s3-test-file.txt"
}

variable "enable_ecs_deployment_check" {
  description = "Whether or not to enable ECS deployment check. This requires installation of the check-ecs-service-deployment binary. See the ecs-deploy-check-binaries module README for more information."
  type        = bool
  default     = false
}

variable "deployment_check_timeout_seconds" {
  description = "Number of seconds to wait for the ECS deployment check before giving up as a failure."
  type        = number
  default     = 600
}

variable "container_command" {
  description = "Command to run on the container. Set this to see what happens when a container is set up to exit on boot"
  type        = list(string)
  default     = []
  # Related issue: https://github.com/hashicorp/packer/issues/7578
  # Example:
  # default = ["-c", "/bin/sh", "echo", "Hello"]
}

variable "volumes" {
  description = "(Optional) A map of volume blocks that containers in your task may use. The key should be the name of the volume and the value should be a map compatible with https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html#volume-block-arguments, but not including the name parameter."
  # Ideally, this would be a map of (string, object), but object does not support optional properties, whereas the
  # volume definition supports a number of optional properties. We can't use a map(any) either, as that would require
  # the values to all have the same type, and due to optional parameters, that wouldn't work either. So, we have to
  # lamely fall back to any.
  type = any

  default = {
    example = {}
  }
}

variable "volumes_mount_paths" {
  description = "(Optional) A map of volume mount paths. The key should be the volume name and must correspond to one of the volumes in var.volumes. The value should be the path at which to mount that volume."
  type        = map(string)
  default = {
    example = "/mnt/example"
  }
}

variable "health_check_interval" {
  description = "The approximate amount of time, in seconds, between health checks of an individual Target. Minimum value 5 seconds, Maximum value 300 seconds."
  type        = number
  default     = 60
}