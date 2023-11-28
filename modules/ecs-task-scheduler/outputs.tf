output "ecs_schedule_task_rule_arn" {
  value = aws_cloudwatch_event_rule.ecs_schedule_task_rule.arn
}

output "ecs_schedule_task_rule_name" {
  value = aws_cloudwatch_event_rule.ecs_schedule_task_rule.id
}

output "ecs_events_iam_role_arn" {
  value = var.create_iam_role ? aws_iam_role.ecs_events_role.0.name : var.ecs_task_iam_role
}

output "ecs_events_iam_role_name" {
  value = var.create_iam_role ? aws_iam_role.ecs_events_role.0.name : split("/", var.ecs_task_iam_role)[1]
}