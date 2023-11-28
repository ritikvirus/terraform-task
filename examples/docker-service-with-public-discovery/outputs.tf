output "aws_region" {
  value = var.aws_region
}

output "ecs_cluster_arn" {
  value = module.ecs_cluster.ecs_cluster_arn
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.ecs_cluster_name
}

output "ecs_cluster_asg_name" {
  value = module.ecs_cluster.ecs_cluster_asg_name
}

output "ecs_service_arn" {
  value = module.ecs_service.service_arn
}

output "service_discovery_address" {
  value = "${var.service_name}.${var.discovery_namespace_name}"
}

output "ssh_host_instance_id" {
  value = aws_instance.ssh_host.id
}
