# ECS Deployment Scripts

This folder contains scripts that help with ECS deployment:

* `run-ecs-task`: Run a single ECS Task, wait for it to exit, and return the exit code of the first container in that 
  Task. This is useful for running short-lived ECS Tasks (e.g., an ECS Task that takes a backup of your data or runs
  a schema migration) and ensuring those ECS Tasks complete successfully. For example, if you had a database that lived
  in private subnets and you wanted a reliable and repeatable way to apply schema migrations to that database before 
  deploying your apps, you could package the schema migration code in a Docker container and update your automated 
  deployment process to use the `run-ecs-task` script to run that Docker container in an ECS Cluster that can access 
  the database. If the schema migration completes successfully, the deployment continues; if it fails, `run-ecs-task`
  will exit with a non-zero exit code, and the deployment will be halted.





## Installing the scripts

You can install the helpers using the [Gruntwork Installer](https://github.com/gruntwork-io/gruntwork-installer):

```bash
gruntwork-install --module-name "ecs-deploy" --repo "https://github.com/gruntwork-io/terraform-aws-ecs" --tag "v0.7.0"
```





## Using the run-ecs-task script

The `run-ecs-task` script assumes you already have the following:

1. An ECS Cluster deployed. The easiest way to deploy one is with the [ecs-cluster 
   module](https://github.com/gruntwork-io/terraform-aws-ecs/tree/main/modules/ecs-cluster). You'll need to know the name
   of the cluster and the AWS region in which it is deployed. 

1. An ECS Task Definition defined. The easiest way to create one is with the [aws_ecs_task_definition 
   resource](https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html). You'll need to know the family 
   name and revision of the ECS Task Definition you want to run. 
   
Check out the [deploy-ecs-task example](/examples/deploy-ecs-task) for working sample code of both of the above.     

To run the ECS Task Definition `db-backup` at revision `3` in an ECS Cluster named `ecs-stage` in `us-west-2`, use the
following command:

```bash
run-ecs-task --task db-backup:3 --cluster ecs-stage --region us-west-2 --timeout 600
```

The command will do the following:

1. Run `db-backup` as an ECS Task in the `ecs-stage` Cluster.
1. Wait for the `db-backup` ECS Task to exit up to 600 seconds (exit with an error if the Task takes longer to run).
1. Read the exit code for the Task and exit with that same code.

If your ECS Task runs successfully and exits with an exit code of 0, `run-ecs-task` will also exit with a code of 0; if 
your ECS Task hits an error and exits with a non-zero exit code, `run-ecs-task` will exit with the same non-zero exit
code. This is particularly useful as part of an automated deployment, as it ensures subsequent deployment steps don't
run if running the ECS Task failed.

## Override the container command

The default operation of `run-ecs-task` is to run an ECS task using the
configurations of the ECS Task Definition, including the container commands to
run. However, there are certain use cases where it is desirable to avoid
maintaining a separate Task Definition for each one off command you want to
run. For example, in a Python Django project, it may be easier to run database
migrations using the web application ECS Task Definition and invoking the
`./manage.py migrate` command.

`run-ecs-task` allows you to override the container command. To override the
container command, provide the container name for which the command is applied
to and pass in the command using positional args. For example, to override
the command to `python manage.py migrate` in the `django` container of the
`my-app` ECS task definition:

```bash
run-ecs-task --task my-app:3 --cluster ecs-stage --region us-west-2 --timeout 600 --container django -- python manage.py migrate
```

This will spin up a new ECS task using the `my-app` revision 3 ECS Task
Definition, and run the `python manage.py migrate` command in the `django`
container instead of the command configured in the Task Definition.
