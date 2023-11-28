output "service_iam_role_name" {
  # Use a RegEx (https://www.terraform.io/docs/configuration/interpolation.html#replace_string_search_replace_) that
  # takes a value like "arn:aws:iam::123456789012:role/S3Access" and looks for the string after the last "/".
  value = replace(
    local.need_ecs_iam_role_for_elb ? aws_iam_role.ecs_service_role[0].arn : "",
    "/.*/+(.*)/",
    "$1",
  )
}

output "service_iam_role_arn" {
  value = local.need_ecs_iam_role_for_elb ? aws_iam_role.ecs_service_role[0].arn : ""
}

output "service_app_autoscaling_target_arn" {
  value = var.use_auto_scaling ? aws_appautoscaling_target.appautoscaling_target[0].role_arn : ""
}

output "service_app_autoscaling_target_resource_id" {
  value = var.use_auto_scaling ? aws_appautoscaling_target.appautoscaling_target[0].resource_id : ""
}

output "service_arn" {
  value = local.ecs_service_arn
}

output "canary_service_arn" {
  value = local.has_canary ? aws_ecs_service.canary[0].id : ""
}

output "ecs_task_iam_role_name" {
  value = local.ecs_task_role_name
}

output "ecs_task_iam_role_arn" {
  value = local.ecs_task_role_arn
}

output "ecs_task_execution_iam_role_name" {
  value = local.ecs_task_execution_role_name
}

output "ecs_task_execution_iam_role_arn" {
  value = local.ecs_task_execution_role_arn
}

output "aws_ecs_task_definition_arn" {
  value = aws_ecs_task_definition.task.arn
}

output "aws_ecs_task_definition_canary_arn" {
  value = var.desired_number_of_canary_tasks_to_run > 0 ? aws_ecs_task_definition.task_canary[0].arn : ""
}

output "target_group_names" {
  value = { for key, target_group in aws_lb_target_group.ecs_service : key => target_group.name }
}

output "target_group_arns" {
  value = { for key, target_group in aws_lb_target_group.ecs_service : key => target_group.arn }
}

output "capacity_provider_strategy" {
  value = var.capacity_provider_strategy != [] ? var.capacity_provider_strategy : null
}

output "service_discovery_arn" {
  value = var.use_service_discovery ? aws_service_discovery_service.discovery[0].arn : null
}
