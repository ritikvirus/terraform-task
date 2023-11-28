output "vpc_id" {
  description = "The AWS ID of the created VPC."
  value       = module.vpc_app.vpc_id
}

output "private_subnet_ids" {
  description = "A list of AWS IDs of the private subnets in the VPC that should be used for your applications."
  value       = module.vpc_app.private_app_subnet_ids
}

output "public_subnet_ids" {
  description = "A list of AWS IDs of the public subnets in the VPC that should be used for load balancers."
  value       = module.vpc_app.public_subnet_ids
}

output "public_namespace_id" {
  description = "Public DNS Namespace ID that can be used for service discovery."
  value       = aws_service_discovery_public_dns_namespace.public_namespace.id
}

output "public_namespace_hosted_zone" {
  description = "Public DNS Namespace Hosted Zone that can be used for service discovery."
  value       = aws_service_discovery_public_dns_namespace.public_namespace.hosted_zone
}
