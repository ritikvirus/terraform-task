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
}

variable "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  type        = string
}

variable "ecs_cluster_instance_ami" {
  description = "The AMI to run on each instance in the ECS cluster"
  type        = string
}

variable "ecs_cluster_instance_keypair_name" {
  description = "The name of the Key Pair that can be used to SSH to each instance in the ECS cluster"
  type        = string
}

variable "ecs_cluster_vpc_subnet_ids" {
  description = "A list of subnet ids in which the ECS cluster should be deployed. If using the standard Gruntwork VPC, these should typically be the private app subnet ids."
  type        = list(string)
}

variable "vpc_id" {
  description = "The id of the VPC in which to run the ECS cluster"
  type        = string
}

variable "container_name" {
  description = "The name of the container in the ECS Task Definition. This is only useful if you have multiple containers defined in the ECS Task Definition. Otherwise, it doesn't matter."
  type        = string
  default     = "webapp"
}

variable "service_name" {
  description = "The name of the ECS service to run"
  type        = string
  default     = "example-ecs-service-with-elb"
}

variable "alb_listener_port" {
  description = "The port on which the ALB will accept requests for our service."
  type        = number
  default     = 80
}

variable "container_http_port" {
  description = "The port var.docker_image listens on for HTTP requests"
  type        = number

  # The Docker container we run in this example listens on port 3000
  default = 3000
}

variable "server_text" {
  description = "The Docker container we run in this example will display this text for every request."
  type        = string
  default     = "Hello"
}

variable "canary_server_text" {
  description = "The canary Docker container we run in this example will display this text for every request."
  type        = string
  default     = "Hello Canary"
}

variable "desired_number_of_canary_tasks_to_run" {
  description = "How many Tasks to run to do a canary deployment of a new version of the sample Docker app. Typically, only 0 or 1 should be used."
  type        = number
  default     = 0
}

variable "s3_test_file_name" {
  description = "The name of the file to store in the S3 bucket. The ECS Task will try to download this file from S3 as a way to check that we are giving the Task the proper IAM permissions."
  type        = string
  default     = "s3-test-file.txt"
}

variable "alb_listener_rule_configs" {
  description = "A list of all ALB Listener Rules that should be attached to an existing ALB Listener. The format of each entry in the list should be '<port>:<priority>:<path>' where the port is the port number on the listener, the priority is the order in which this Listener Rule should be evaluated relative to other Listener Rules, and the path is the path pattern to be used for path-based routing as described at https://goo.gl/kUJjcu. Note that you can use regex in the path pattern, such as using '*' to match all paths."
  type        = list(string)

  default = [
    "80:100:*",
  ] # This rule, with priority 100, will match requests at any path on port 80.
}

variable "alb_vpc_subnet_ids" {
  description = "A list of the subnets into which the ALB will place its underlying nodes. Include one subnet per Availabability Zone. If the ALB is public-facing, these should be public subnets. Otherwise, they should be private subnets."
  type        = list(string)
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables have defaults and may be overwritten
# ---------------------------------------------------------------------------------------------------------------------

variable "route53_hosted_zone_name" {
  description = "The name of the Route53 Hosted Zone where we will create a DNS record for this service (e.g. gruntwork-dev.io)"
  type        = string
  default     = "gruntwork-dev.io"
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
  description = "Command to run on the container. Set this to see what happens when a container is set up to exit on boot."
  type        = list(string)
  default     = []
  # Example:
  # default = ["echo", "Hello"]
}

variable "canary_container_command" {
  description = "Command to run on the canary_container. Set this to see what happens when a container is set up to exit on boot."
  type        = list(string)
  default     = []
  # Example:
  # default = ["echo", "Hello"]
}

variable "health_check_interval" {
  description = "The approximate amount of time, in seconds, between health checks of an individual Target. Minimum value 5 seconds, Maximum value 300 seconds."
  type        = number
  default     = 60
}