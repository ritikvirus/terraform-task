# Deploy ECS Task Example

This folder shows an example of how to use the ECS modules to:

1. Deploy an ECS cluster
1. Create an ECS Task Definition
1. Run the ECS Task Definition in the ECS Cluster
1. Wait for the ECS Task to exit and return its exit code




## How do you run this example?

To run this example, you need to do the following:

1. Build the AMI
1. Apply the Terraform templates
1. Run the ECS Task


### Build the AMI

See the [example-ecs-instance-ami docs](/examples/example-ecs-instance-ami).


#### Apply the Terraform templates

To apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/)
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables that
   don't have a default. This includes setting the `ecs_cluster_instance_ami` the ID of the AMI you just built.
1. Run `terraform get`.
1. Run `terraform plan`.
1. If the plan looks good, run `terraform apply`.


### Run the ECS Task

To run the ECS Task, you can use the `run-ecs-task` script in the [ecs-deploy module](/modules/ecs-deploy), passing it
outputs from this example module:

```bash
../../modules/ecs-deploy/bin/run-ecs-task \
  --task $(terraform output ecs_task_family):$(terraform output ecs_task_revision) \
  --cluster $(terraform output ecs_cluster_name) \
  --region $(terraform output aws_region) \
  --timeout 300
```