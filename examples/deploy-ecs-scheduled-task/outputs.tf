output "ecs_cluster_arn" {
  value = module.ecs_cluster.ecs_cluster_arn
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.ecs_cluster_name
}

output "ecs_task_family" {
  value = var.create_resources ? aws_ecs_task_definition.example[0].family : null
}

output "ecs_task_revision" {
  value = var.create_resources ? aws_ecs_task_definition.example[0].revision : null
}

output "ecs_cluster_asg_name" {
  value = module.ecs_cluster.ecs_cluster_asg_name
}

output "aws_region" {
  value = var.aws_region
}

output "ecs_schedule_task_rule_arn" {
  value = module.task_scheduler.ecs_schedule_task_rule_arn
}

output "ecs_schedule_task_rule_name" {
  value = module.task_scheduler.ecs_schedule_task_rule_name
}

output "ecs_events_iam_role_arn" {
  value = module.task_scheduler.ecs_events_iam_role_arn
}

output "ecs_events_iam_role_name" {
  value = module.task_scheduler.ecs_events_iam_role_name
}