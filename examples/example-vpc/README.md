# VPC 

This folder shows an example of how to create a VPC that can be used with the [docker-service-with-private-discovery
example](/examples/docker-service-with-private-discovery) and the [docker-service-with-public-discovery
example](/examples/docker-service-with-public-discovery).

## How do you run this example?

To run this example, apply the associated Terraform templates.

#### Apply the Terraform templates

To apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/)
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables that
   don't have a default.
1. Run `terraform get`.
1. Run `terraform plan`.
1. If the plan looks good, run `terraform apply`.
