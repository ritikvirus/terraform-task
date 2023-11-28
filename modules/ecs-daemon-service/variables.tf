# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "service_name" {
  description = "The name of the service. This is used to namespace all resources created by this module."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the ECS Cluster where this service should run."
  type        = string
}

variable "ecs_task_container_definitions" {
  description = "The JSON text of the ECS Task Container Definitions. This portion of the ECS Task Definition defines the Docker container(s) to be run along with all their properties. It should adhere to the format described at https://goo.gl/ob5U3g."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "wait_for_steady_state" {
  description = "If true, Terraform will wait for the service to reach a steady state—as in, the ECS tasks you wanted are actually deployed—before 'apply' is considered complete."
  type        = bool
  default     = false
}

variable "launch_type" {
  description = "The launch type on which to run your service. The valid values are EC2 and FARGATE. Defaults to EC2"
  type        = string
  default     = "EC2"
}

variable "custom_iam_role_name_prefix" {
  description = "Prefix for name of the IAM role used by the ECS task. If not provide, will be set to var.service_name."
  type        = string
  default     = null
}

variable "custom_task_execution_name_prefix" {
  description = "Prefix for name of iam role and policy that allows cloudwatch and ecr access"
  type        = string
  default     = null
}

variable "ecs_task_definition_network_mode" {
  description = "The Docker networking mode to use for the containers in the task. The valid values are none, bridge, awsvpc, and host"
  type        = string
  default     = "bridge"
}

variable "ecs_task_definition_pid_mode" {
  description = "The process namespace to use for the containers in the task. The valid values are host and task."
  type        = string
  default     = "task"
}

variable "volumes" {
  description = "(Optional) A map of volume blocks that containers in your task may use. The key should be the name of the volume and the value should be a map compatible with https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html#volume-block-arguments, but not including the name parameter."
  # Ideally, this would be a map of (string, object), but object does not support optional properties, whereas the
  # volume definition supports a number of optional properties. We can't use a map(any) either, as that would require
  # the values to all have the same type, and due to optional parameters, that wouldn't work either. So, we have to
  # lamely fall back to any.
  type    = any
  default = {}

  # Example:
  # volumes = {
  #   datadog = {
  #     host_path = "/var/run/datadog"
  #   }
  #
  #   logs = {
  #     host_path = "/var/log"
  #     docker_volume_configuration = {
  #       scope         = "shared"
  #       autoprovision = true
  #       driver        = "local"
  #     }
  #   }
  # }
}

variable "deployment_minimum_healthy_percent" {
  description = "(Optional) The lower limit (as a percentage of the service's desiredCount) of the number of running tasks that must remain running and healthy in a service during a deployment"
  type        = number
  default     = null
}

variable "custom_tags" {
  description = "A map of tags to apply to all resources created by this module. Each item in this list should be a map with the parameters key and value."
  type        = map(string)
  default     = {}
  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }

}

variable "service_tags" {
  description = "A map of tags to apply to the ECS service. Each item in this list should be a map with the parameters key and value."
  type        = map(string)
  default     = {}
  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }
}

variable "task_definition_tags" {
  description = "A map of tags to apply to the task definition. Each item in this list should be a map with the parameters key and value."
  type        = map(string)
  default     = {}
  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }
}

variable "propagate_tags" {
  description = "Whether tags should be propogated to the tasks from the service or from the task definition. Valid values are SERVICE and TASK_DEFINITION. Defaults to SERVICE. If set to null, no tags are created for tasks."
  type        = string
  default     = "SERVICE"
}

# Deployment Check Options

variable "enable_ecs_deployment_check" {
  description = "Whether or not to enable the ECS deployment check binary to make terraform wait for the task to be deployed. See ecs_deploy_check_binaries for more details. You must install the companion binary before the check can be used. Refer to the README for more details."
  type        = bool
  default     = true
}

variable "deployment_check_timeout_seconds" {
  description = "Seconds to wait before timing out each check for verifying ECS service deployment. See ecs_deploy_check_binaries for more details."
  type        = number
  default     = 600
}

variable "deployment_check_loglevel" {
  description = "Set the logging level of the deployment check script. You can set this to `error`, `warn`, or `info`, in increasing verbosity."
  type        = string
  default     = "info"
}

variable "deployment_controller" {
  description = "Type of deployment controller, possible values: CODE_DEPLOY, ECS, EXTERNAL"
  type        = string
  default     = null
}

variable "additional_task_assume_role_policy_principals" {
  description = "A list of additional principals who can assume the task and task execution roles"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------------------------------------------------
# ECS TASK PLACEMENT PARAMETERS
# These variables are used to determine where ecs tasks should be placed on a cluster.
#
# https://www.terraform.io/docs/providers/aws/r/ecs_service.html#placement_constraints-1
#
# Since placement_constraint is an inline block and you can't use count to make it conditional,
# we give some sane defaults here
# ---------------------------------------------------------------------------------------------------------------------

variable "placement_constraint_type" {
  type    = string
  default = "memberOf"
}

variable "placement_constraint_expression" {
  type    = string
  default = "attribute:ecs.ami-id != 'ami-fake'"
}

variable "task_role_permissions_boundary_arn" {
  description = "The ARN of the policy that is used to set the permissions boundary for the IAM role for the ECS task."
  type        = string
  default     = null
}

variable "task_execution_role_permissions_boundary_arn" {
  description = "The ARN of the policy that is used to set the permissions boundary for the IAM role for the ECS task execution."
  type        = string
  default     = null
}
