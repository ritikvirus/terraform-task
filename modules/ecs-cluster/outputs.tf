output "ecs_cluster_arn" {
  value = var.create_resources ? aws_ecs_cluster.ecs[0].id : null

  # Explicitly ties the aws_ecs_cluster to the aws_autoscaling_group, so that the resources are created together
  depends_on = [aws_autoscaling_group.ecs]
}

output "ecs_cluster_launch_template_id" {
  value = var.create_resources ? aws_launch_template.ecs[0].id : null
}

output "ecs_cluster_name" {
  value = var.create_resources ? aws_ecs_cluster.ecs[0].name : null

  # Explicitly ties the aws_ecs_cluster to the aws_autoscaling_group, so that the resources are created together
  depends_on = [aws_autoscaling_group.ecs]
}

output "ecs_cluster_asg_name" {
  value = var.create_resources ? aws_autoscaling_group.ecs[0].name : null
}

output "ecs_cluster_asg_names" {
  value = var.create_resources ? aws_autoscaling_group.ecs[*].name : null
}

output "ecs_cluster_capacity_provider_names" {
  value = var.create_resources && var.capacity_provider_enabled ? aws_ecs_capacity_provider.capacity_provider[*].name : null
}

output "ecs_instance_security_group_id" {
  value = var.create_resources ? aws_security_group.ecs[0].id : null
}

output "ecs_instance_iam_role_id" {
  value = var.create_resources ? aws_iam_role.ecs[0].id : null
}

output "ecs_instance_iam_role_arn" {
  value = var.create_resources ? aws_iam_role.ecs[0].arn : null
}

output "ecs_instance_iam_role_name" {
  # Use a RegEx (https://www.terraform.io/docs/configuration/interpolation.html#replace_string_search_replace_) that
  # takes a value like "arn:aws:iam::123456789012:role/S3Access" and looks for the string after the last "/".
  value = var.create_resources ? replace(aws_iam_role.ecs[0].arn, "/.*/+(.*)/", "$1") : null
}
