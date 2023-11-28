# ---------------------------------------------------------------------------------------------------------------------
# ENABLE AUTO SCALING FOR THE ECS SERVICE
# Note that this resource *enables* Auto Scaling, but doesn't actually activate any Auto Scaling policies. To do that,
# in the Terraform template that consumes this module, add the following resources:
# - aws_appautoscaling_policy.scale_out
# - aws_appautoscaling_policy.scale_in
# - aws_cloudwatch_metric_alarm.high_cpu_usage (or other CloudWatch alarm)
# - aws_cloudwatch_metric_alarm.low_cpu_usage (or other CloudWatch alarm)
#
# The resource below is only created if var.use_auto_scaling is true.
# ---------------------------------------------------------------------------------------------------------------------

# Create an App AutoScaling Target that allows us to add AutoScaling Policies to our ECS Service
resource "aws_appautoscaling_target" "appautoscaling_target" {
  count = var.use_auto_scaling ? 1 : 0

  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  # Service id reference to avoid removal of aws_appautoscaling_policy when service is recreated
  # https://github.com/gruntwork-io/terraform-aws-ecs/issues/320
  # https://github.com/hashicorp/terraform-provider-aws/issues/10432#issuecomment-588264307
  resource_id = "service/${local.ecs_cluster_name}/${var.service_name}${replace(aws_ecs_service.service_with_auto_scaling[0].id, "/.*/", "")}"

  min_capacity = var.min_number_of_tasks
  max_capacity = var.max_number_of_tasks

  depends_on = [
    aws_ecs_service.service_with_auto_scaling,
    aws_ecs_service.service_without_auto_scaling,
    aws_ecs_service.canary,
  ]
}

# Calculate the ECS cluster name from the ECS cluster ARN
locals {
  # Use a RegEx (https://www.terraform.io/docs/configuration/interpolation.html#replace_string_search_replace_) that 
  # takes a value like "arn:aws:iam::123456789012:role/S3Access" and looks for the string after the last "/".
  ecs_cluster_name = replace(var.ecs_cluster_arn, "/.*/+(.*)/", "$1")
}
