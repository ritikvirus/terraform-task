# ECS Task Scheduler Module

This terraform module allows for [scheduling of ECS tasks](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/scheduling_tasks.html)

## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.

This module configures the AWS infrastructure required to invoke ECS tasks on an event or scheduled basis. This module does not configure the ECS cluster or task definition.

## How do you configure when the ECS task will run?

This module provides two options for defining when ECS tasks will be run:

* [Event Patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html)
* [Schedule Expressions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html#eb-rate-expressions)

In [variables.tf](./variables.tf) there are two variables (`task_event_pattern` and `task_schedule_expression`) that can be provided in the module definition. At least one, but not both of these fields, must be provided. This is what is passed to the EventBridge rule to determine when to invoke your ECS task.

Note that this approach has AWS limitations with monitoring the event trigger and ECS task. AWS EventBridge fires the event but does not monitor whether the task ran successfully so if there is a failure, EventBridge does not attempt any retries or report failures.

### Event Patterns

The event pattern variable is a json string that defines which events to listen to and invoke your ECS task from. 

```hcl
module "ecs_task_scheduler" {

  task_event_pattern = <<EOF
    {
      "source": ["aws.ec2"],
      "detail-type": ["EC2 Instance State-change Notification"],
      "detail": {
        "state": ["terminated"]
      }
    }
  EOF

  #(additional arguments omitted)
}
```

For more information see the [AWS Documentation on event rule patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule.html)

### Schedule Expressions

With schedule expressions, you can define based on Cron schedules, and rate expressions. For more information on how to use expressions see AWS documention and examples below:

* [Cron Expressions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html#eb-cron-expressions)
* [Rate Expressions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html#eb-rate-expressions)

```hcl
module "ecs_task_scheduler" {

  task_schedule_expression = "rate(5 minutes)"  

  #(additional arguments omitted)
}
```
```hcl
module "ecs_task_scheduler" {

  task_schedule_expression = "cron(0 12 * * ? *)"  

  #(additional arguments omitted)
}
```
For more information see the [AWS Documentation on schedule rules](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html)

## Can I enable or disable the rule?

The rule is enabled by default, and can be disabled by setting the `is_enabled` variable to `false`

## Can I use my own IAM role?

To provide an IAM role instead of using the role provided by the module you can:

  * Set `create_iam_role` variable to `false`
  * Provide the IAM role ARN to the `ecs_task_iam_role_arn` variable

## How do I pass inputs and overrides to my ECS task from the EventBridge rule?

This module provides support for passing the following additional inputs and overrides:

* Task Count
* Target Group
* Launch Type
* Platform Version
* Propagate Tags
* Enable Execute Command
* Enable ECS Managed Tags
* Network Configuration

  Example Network Configuration Block

  ```hcl
  module "ecs_task_scheduler" {

    ecs_target_network_configuration = {
      assign_public_ip = false
      security_groups = [
        "sg-xxxx"
      ]
      subnets = [
        "subnet-xxxx",
        "subnet-xxxx"
      ]
    }

    #(additional arguments omitted)
  }
  ```
  Note that `subnets` is the only required parameter if the `network_configuration` block is defined.

* Placement Contstraints

  Example Placement Constraints Configuration Block

  ```hcl
  module "ecs_task_scheduler" {

    ecs_target_placement_constraints = [
      {
        type = "memberOf"
        expression = "attribute:ecs.availability-zone in [us-west-2a, us-west-2b, us-west-2c, us-west-2d]"
      },
      {
        type = "memberOf"
        expression = "attribute:ecs.subnet-id in [subnet-xxxx]"
      }
    ]

    #(additional arguments omitted)
  }
  ```
  Note that there is a maximum limit of 10 placement constraint objects.
  See [AWS Documention for additional](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-placement-constraints.html) information on placement constraints

* Container Overrides
  
  Example Container Overrides configuration input

  ```hcl
  module "ecs_task_scheduler" {

    ecs_target_container_overrides = <<DOC
      {
        "containerOverrides": [
          {
            "name": "name-of-container-to-override",
            "command": ["bin/console", "scheduled-task"]
          }
        ]
      }
    DOC

    #(additional arguments omitted)
  }
  ```

See [variables.tf](./variables.tf) for specific variable definitions.

