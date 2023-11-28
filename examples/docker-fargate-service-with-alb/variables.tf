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
  description = "The name of the Fargate service to run"
  type        = string
  default     = "fargate-alb"
}

variable "desired_number_of_tasks" {
  description = "How many instances of the container to schedule on the cluster"
  type        = number
  default     = 3
}

variable "container_name" {
  description = "The name of the container in the ECS Task Definition. This is only useful if you have multiple containers defined in the ECS Task Definition. Otherwise, it doesn't matter."
  type        = string
  default     = "webapp"
}

variable "http_port" {
  description = "The port on which the host and container listens on for HTTP requests"
  type        = number
  default     = 3000
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

variable "route53_hosted_zone_name" {
  description = "The name of the Route53 Hosted Zone where we will create a DNS record for this service (e.g. gruntwork-dev.io)"
  type        = string
  default     = "gruntwork-dev.io"
}

variable "route53_tags" {
  description = "Search for the domain in var.route53_hosted_zone_name by filtering using these tags"
  type        = map(string)
  default     = {}
}

variable "skip_s3_test_file_creation" {
  description = "Whether or not to skip s3 test file creation. Set this to true to see what happens when the container is set up to crash."
  type        = bool
  default     = false
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

variable "container_boot_delay_seconds" {
  description = "Delay the boot up sequence of the container by this many seconds. Use this to test various booting scenarios (e.g crash container after a long boot) against the deployment check."
  type        = number
  default     = 0
}

variable "deployment_circuit_breaker_enabled" {
  description = "Set to 'true' to prevent the task from attempting to continuously redeploy after a failed health check."
  type        = bool
  default     = true
}

variable "deployment_circuit_breaker_rollback" {
  description = "Set to 'true' to also automatically roll back to the last successful deployment."
  type        = bool
  default     = true
}

variable "health_check_interval" {
  description = "The approximate amount of time, in seconds, between health checks of an individual Target. Minimum value 5 seconds, Maximum value 300 seconds."
  type        = number
  default     = 60
}