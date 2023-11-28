output "service_arn" {
  value = module.ecs_daemon_service.service_arn
}

output "ecs_task_iam_role_name" {
  value = module.ecs_daemon_service.ecs_task_iam_role_name
}

output "ecs_task_iam_role_arn" {
  value = module.ecs_daemon_service.ecs_task_iam_role_arn
}

output "aws_ecs_task_definition_arn" {
  value = module.ecs_daemon_service.aws_ecs_task_definition_arn
}
