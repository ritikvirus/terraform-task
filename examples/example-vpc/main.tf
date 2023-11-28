# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A VPC FOR USE WITH THE EXAMPLES
# This deploys a VPC that can be used with the ECS examples in this package.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  required_version = ">= 1.0.0"
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A VPC WITH NAT GATEWAY
# awsvpc tasks need to be in private subnet with a NAT gateway to access the internet
# ---------------------------------------------------------------------------------------------------------------------

module "vpc_app" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-vpc.git//modules/vpc-app?ref=v0.23.1"

  vpc_name   = var.vpc_name
  aws_region = var.aws_region

  # The IP address range of the VPC in CIDR notation. A prefix of /18 is recommended. Do not use a prefix higher
  # than /27.
  cidr_block = "10.0.0.0/18"

  # The number of NAT Gateways to launch for this VPC. For production VPCs, a NAT Gateway should be placed in each
  # Availability Zone (so likely 3 total), whereas for non-prod VPCs, just one Availability Zone (and hence 1 NAT
  # Gateway) will suffice. Warning: You must have at least this number of Elastic IP's to spare.  The default AWS
  # limit is 5 per region, but you can request more.
  num_nat_gateways = 1
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A DNS HOSTNAME TO NAMESPACE THE SERVICE
# You can have multiple services using the same namespace
# In this example we are creating a PUBLIC namespace
# Public namespaces must be already registered as a domain on route53
# E.g. gruntwork-sandbox.com
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_service_discovery_public_dns_namespace" "public_namespace" {
  name = var.discovery_namespace_name
}
