# Docker Fargate Service with Ephemeral Storage specified
This folder shows an example of how to use the ECS modules to:

1. Deploy an ECS cluster
1. Run a simple "Hello, World" web service Docker container as a Fargate service with mounted EFS volume
1. This service does NOT have a load balancer associated with it for simplicity sake.

## How do you run this example?

To run this example, simply apply the Terraform templates.

### Apply the Terraform templates

To apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/), minimum version `1.0.0`.
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables that don't have a default.
1. Run `terraform init`.
1. Run `terraform apply`.
