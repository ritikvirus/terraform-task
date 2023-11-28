# Docker Service with Canary Deployment Example

This folder shows an example of how to use a combination of ECS modules to:

1. Deploy an ECS cluster
1. Run a simple "Hello, World" web service Docker container as an ECS service
1. Use an ELB to route traffic to the ECS service
1. Do a canary deployment of a single instance of a new version of the Docker container

This example runs various versions of the [gruntwork/docker-test-webapp Docker
image](https://hub.docker.com/r/gruntwork/docker-test-webapp/), which contains a simple Node.js app (you can find the
source in the [example-docker-image folder](/examples/example-docker-image)). In the real world, you'll obviously want
to replace this Docker image with your own.

## How do you run this example?

To run this example, you need to do the following:

1. Build the AMI
1. Apply the Terraform templates
1. Deploy a canary version

### Build the AMI

See the [example-ecs-instance-ami docs](/examples/example-ecs-instance-ami).

#### Apply the Terraform templates

To apply the Terraform templates:

1. Install the latest version of [Terraform](https://www.terraform.io/).
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables that
   don't have a default. This includes setting the `cluster_instance_ami` the ID of the AMI you just built.
1. Run `terraform get`.
1. Run `terraform plan`.
1. If the plan looks good, run `terraform apply`.

You should now have several instances of the Docker container saying "Hello World".

#### Deploy a canary version

To deploy the canary version:

1. Set the `desired_number_of_canary_tasks_to_run` input variable to 1
1. Run `terraform plan`.
1. If the plan looks good, run `terraform apply`.

You should now have several instances of the Docker container saying "Hello World" and one instance that says "Hello
Canary World".
