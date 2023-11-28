output "elb_dns_name" {
  value = aws_elb.ecs_elb.dns_name
}

output "elb_port" {
  value = var.elb_http_port
}

output "asg_name" {
  value = module.ecs_cluster.ecs_cluster_asg_name
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.ecs_cluster_name
}

output "aws_region" {
  value = var.aws_region
}
