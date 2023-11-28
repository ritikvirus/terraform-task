output "elb_dns_name" {
  value = aws_elb.ecs_elb.dns_name
}

output "elb_port" {
  value = var.elb_http_port
}
