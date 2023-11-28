# Docker Fargate Service without Load Balancer example

This folder shows an example of how to use the ECS modules to:

1. Deploy an ECS cluster
1. Run a simple "Hello, World" web service Docker container as a Fargate service
1. This service does NOT have a load balancer associated with it, which is a pattern you might use for non user-facing services, background jobs, and services that use load balancer alternatives (e.g. Consul).

## How do you run this example?

To run this example, simply apply the Terraform templates.

### Apply the Terraform templates

To apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/), minimum version: `0.6.11`.
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables that don't have a default.
1. Run `terraform init`.
1. Run `terraform apply`.
