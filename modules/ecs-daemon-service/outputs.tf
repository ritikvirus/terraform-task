output "service_arn" {
  value = aws_ecs_service.daemon_service.id
}

output "ecs_task_iam_role_name" {
  value = aws_iam_role.ecs_task.name
}

output "ecs_task_iam_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "ecs_task_execution_iam_role_name" {
  value = aws_iam_role.ecs_task_execution_role.name
}

output "ecs_task_execution_iam_role_arn" {
  value = aws_iam_role.ecs_task_execution_role.arn
}

output "aws_ecs_task_definition_arn" {
  value = aws_ecs_task_definition.task.arn
}
