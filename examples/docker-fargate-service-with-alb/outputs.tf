output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "service_dns_name" {
  value = "${var.service_name}.${data.aws_route53_zone.sample.name}"
}

output "alb_security_group_id" {
  value = module.alb.alb_security_group_id
}

output "http_listener_arns" {
  value = module.alb.http_listener_arns
}

output "https_listener_non_acm_cert_arns" {
  value = module.alb.https_listener_non_acm_cert_arns
}

output "https_listener_acm_cert_arns" {
  value = module.alb.https_listener_acm_cert_arns
}
