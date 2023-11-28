output "http_port" {
  value = var.http_port
}

output "service_dns_name" {
  value = "${var.service_name}.${data.aws_route53_zone.sample.name}"
}

output "nlb_dns_name" {
  value = aws_lb.nlb.dns_name
}
