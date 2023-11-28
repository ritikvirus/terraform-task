output "ecs_cluster_asg_name" {
  value = module.ecs_cluster.ecs_cluster_asg_name
}

output "host_http_port" {
  value = var.host_http_port
}

output "ecs_instance_iam_role_name" {
  value = module.ecs_cluster.ecs_instance_iam_role_name
}
