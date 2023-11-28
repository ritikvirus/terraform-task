# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# These variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

variable "ecs_target_task_definition_arn" {
  description = "The task definition ARN for cloudwatch schedule to run."
  type        = string
}

variable "ecs_target_cluster_arn" {
  description = "The arn of the ECS cluster to use."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# SCHEDULE EXPRESSION VARIABLES
#
# These variables define the schedule expression for triggering the EventBridge Rule that runs the ECS task 
# 
# One of these variables must be provided when creating the module definition
# 
# See the ecs-task-scheduler README and AWS Documentation for more information:
# https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html
# ---------------------------------------------------------------------------------------------------------------------

variable "task_event_pattern" {
  description = "The event pattern to use. See README for usage examples. Leave null if using task_schedule_expression."
  type        = string
  default     = null
}

variable "task_schedule_expression" {
  description = "The scheduling expression to use (rate or cron - see README for usage examples). Leave null if using task_event_pattern."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables may optionally be passed in by the operator, but they have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "is_enabled" {
  description = "Set to true to enable the rule and false to disable"
  type        = bool
  default     = true
}

variable "create_iam_role" {
  description = "Creation of the Eventbridge IAM role within the module. If omitted IAM role ARN must be provided in ecs_task_iam_role variable."
  type        = bool
  default     = true
}

variable "ecs_task_iam_role" {
  description = "ARN of IAM role for eventbridge to use. Only use if create_iam_role is set to true"
  type        = string
  default     = null
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