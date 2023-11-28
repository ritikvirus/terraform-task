# Docker Service with Service Discovery using a private DNS hostname

This example demonstrates how to set up an ECS cluster and then deploy an ECS service which can register
itself with [AWS Service Discovery](https://aws.amazon.com/blogs/aws/amazon-ecs-service-discovery/). This allows
reaching your service through a hostname that can be queried within your VPC.

## How do you run this example?

To run this example, you need to do the following:

1. Build the AMI
1. (Optional) Create a VPC
1. Apply the Terraform templates

### Build the AMI

See the [example-ecs-instance-ami docs](/examples/example-ecs-instance-ami).

### Create a VPC

This example requires a VPC with private and public subnets. You can use the [example-vpc
example](/examples/example-vpc) to create one if you do not already have one handy.

### Apply the Terraform templates

To apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/).
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables that
   don't have a default. This includes setting the `ecs_cluster_instance_ami` with the ID of the AMI you just built.
1. Run `terraform init`.
1. Run `terraform apply`, it will give you a plan and request if you wish to proceed.

#### Resources

1. [AWS ECS Service Discovery guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-discovery.html#create-service-discovery)
1. [ecs-service-with-discovery module](/modules/ecs-service-with-discovery)
