* [Background](#background)
  * [What is an ECS Service?](#what-is-an-ecs-service)
  * [What is ECS Service Discovery?](#what-is-ecs-service-discovery)
* [Operations](#operations)
  * [How do you create an ECS cluster?](#how-do-you-create-an-ecs-cluster)
  * [How do ECS Services deploy new versions of containers?](#how-do-ecs-services-deploy-new-versions-of-containers)
  * [How do I do a canary deployment?](#how-do-i-do-a-canary-deployment)
  * [How does canary deployment work?](#how-does-canary-deployment-work)
  * [How do you add additional IAM policies to the ECS Service?](#how-do-you-add-additional-iam-policies-to-the-ecs-service)
  * [How do I use Fargate?](#how-do-i-use-fargate)
  * [How do you scale an ECS Service?](#how-do-you-scale-an-ecs-service)
  * [How do I associate the ECS Service with a CLB?](#how-do-i-associate-the-ecs-service-with-a-clb)
  * [How do I associate the ECS Service with an ALB or NLB?](#how-do-i-associate-the-ecs-service-with-an-alb-or-nlb)
    * [Why doesn't this module create ALB Listener Rules directly?](#why-doesnt-this-module-create-alb-listener-rules-directly)
  * [How do I setup Service Discovery?](#how-do-i-setup-service-discovery)
  * [How do I set up App Mesh?](#how-do-i-set-up-app-mesh)
* [Known Issues](#known-issues)
  * [Switching the value of var.use_auto_scaling](#switching-the-value-of-varuse_auto_scaling)
  * [Gotchas with Service Discovery](#gotchas-with-service-discovery)
* [Related Concepts](#related-concepts)
  * [ECS clusters](#ecs-clusters)
  * [ECS services and tasks](#ecs-services-and-tasks)
  * [Route 53 Auto Naming Service](#route-53-auto-naming-service)

# Background

## What is an ECS Service?

To run Docker containers with ECS, you first define an [ECS
Task](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_defintions.html), which is a JSON file that
describes what container(s) to run, the resources (memory, CPU) those containers need, the volumes to mount, the
environment variables to set, and so on. To actually run an ECS Task, you define an ECS Service, which can:

1. Deploy the requested number of Tasks across an ECS cluster based on the `desired_number_of_tasks` input variable.
1. Restart tasks if they fail.
1. Route traffic across the tasks with an optional Elastic Load Balancer (ELB).


## What is ECS Service Discovery?

Many services are not guaranteed to have the same IP address through their lifespan. They can, for example, be
dynamically assigned to run on different hosts, be redeployed after a failure recovery or scale in and out. This makes
it complex for services to send traffic to each other.

Service discovery is the action of detecting and addressing these services, allowing them to be found. Some of the ways
of doing service discovery are, for example, hardcoding IP addresses, using a Load Balancer or using specialized tools.

ECS Service Discovery is an AWS feature that allows you to reach your ECS services through a hostname managed by Route53.
This hostname will consist of a service discovery name and a namespace (private or public), in the shape of
`discovery-name.namespace:port`. For example, on our namespace `sandbox.gruntwork.io`, we can have a service with the
discovery name `my-test-webapp` running on port `3000`. This means that we can `dig` or `curl` this service at
`my-test-webapp.sandbox.gruntwork.io:3000`. For more information see the [related concepts](#related-concepts) section.

There are many advantages of using ECS Service Discovery instead of reaching it through a Load Balancer, for example:

- Direct communication with the container run by your service
- Lower latency, if using AWS internal network and private namespace
- You can do service-to-service authentication
- Not having a Load Balancer also means fewer resources to manage
- You can configure a Health Check and associate it with all records within a namespace
- You can make a logical group of services under one namespace


Under the hood, the ECS Service Discovery system uses Amazon Route 53 Auto Naming Service. This service automates the
process of:

* Creating a public or private namespace within a new or existing hosted zone
* Providing a service with the DNS Records configuration and optional health checks

The latter will be used in the Service Registry of your ECS Service Discovery, and it is the only type of service currently supported for this.

Important considerations:
* Public namespaces are accessible on the internet and need the domain to be registered already
* Private namespaces are accessible only within your VPC and can be queried immediately
* For cleaning up, deregistering the instances from the auto naming service will trigger an automatic deletion of resources in AWS. However, the namespaces themselves are not deleted. Namespaces must be deleted manually and that is only allowed once all services in that namespace no longer exist.

For more information on Route 53 Auto Naming Service, please see the AWS documentation on [Using Auto Naming for Service Discovery][4].


# Operations

## How do you create an ECS cluster?

To use ECS, you first deploy one or more EC2 Instances into a "cluster". See the [ecs-cluster module](../ecs-cluster)
for how to create a cluster.


## How do ECS Services deploy new versions of containers?

When you update an ECS Task (e.g. change the version number of a Docker container to deploy), ECS will roll out the change
automatically across your cluster according to two input variables:

* `deployment_maximum_percent`: This variable controls the maximum number of copies of your ECS Task, as a percentage of
  `desired_number_of_tasks`, that can be deployed during an update. For example, if you have 4 Tasks running at version
  1, `deployment_maximum_percent` is set to 200, and you kick off a deployment of version 2 of your Task, ECS will
  first deploy 4 Tasks at version 2, wait for them to come up, and then it'll undeploy the 4 Tasks at version 1. Note
  that this only works if your ECS cluster has capacity--that is, EC2 instances with the available memory, CPU, ports,
  etc requested by your Tasks, which might mean maintaining several empty EC2 instances just for deployment.
* `deployment_minimum_healthy_percent`: This variable controls the minimum number of copies of your ECS Task, as a
  percentage of `desired_number_of_tasks`, that must stay running during an update. For example, if you have 4 Tasks running
  at version 1, you set `deployment_minimum_healthy_percent` to 50, and you kick off a deployment of version 2 of your
  Task, ECS will first undeploy 2 Tasks at version 1, then deploy 2 Tasks at version 2 in their place, and then repeat
  the process again with the remaining 2 tasks. This allows you to roll out new versions without having to keep spare
  EC2 instances, but it also means the availability of your service is somewhat reduced during rollouts.


## How do I do a canary deployment?

A [canary deployment](http://martinfowler.com/bliki/CanaryRelease.html) is a way to test new versions of your Docker
containers in a way that limits the damage any bugs could do. The idea is to deploy the new version onto just a single
server (meanwhile, the old versions are running elsewhere) and to test that new version and compare it to the old
versions. If everything is working well, you roll out the new version everywhere. If there are any problems, they only
affect a small percentage of users, and you can quickly fix them by rolling back the new version.

To do a canary deployment with this module, you need to specify two parameters:

* `ecs_task_definition_canary`: The JSON text of the ECS Task Definition to be run for the canary. This defines the
  Docker container(s) to be run along with all their properties.
* `desired_number_of_canary_tasks_to_run`: The number of ECS Tasks to run for the canary. You should typically set
  this to 1.

Here's an example that has 10 versions of the original ECS Task running and adds 1 Task to try out a canary:

```hcl
module "ecs_service" {
  ecs_task_container_definitions = local.container_definition
  desired_number_of_tasks        = 10

  ecs_task_definition_canary            = local.canary_container_definition
  desired_number_of_canary_tasks_to_run = 1

  # (... all other params omitted ...)
}
```

If this canary has any issues, set `desired_number_of_canary_tasks_to_run` to 0. If the canary works well and you
want to deploy the new version across the whole cluster, update `local.container_definition` with the new version of
the Docker container and set `desired_number_of_canary_tasks_to_run` back to 0.


## How does canary deployment work?

The way we do canary deployments with this module is to create a second ECS Service just for the canary that runs
`desired_number_of_canary_tasks_to_run` instances of your canary ECS Task. This ECS Service registers with the same ELB
or service registry (if you're using one), so some percentage of user requests will randomly hit the canary, and the
rest will go to the original ECS Tasks. For example, if you had 9 ECS Tasks and you deployed 1 canary ECS Task, then
each request would have a 90% chance of hitting the original version of your Docker container and a 10% chance of
hitting the canary version.

Therefore, there are two caveats with using canary deployments:

1. Do not do canary deployments with user-visible changes. For example, if your Docker container is a frontend service
   and the new Docker image version changes the UI, then a user may see a different version of the UI every time they
   refresh the page, which could be a jarring experience. You can still use canary deployments with frontend Docker
   containers so long as you wrap UI changes in feature toggles and don't enable those toggles until the new version is
   rolled out across the entire cluster (i.e. this is known as a [dark
   launch](http://tech.co/the-dark-launch-how-googlefacebook-release-new-features-2016-04)).
1. Ensure the new version of your Docker container is backwards compatible with the old version. For example, if the
   Docker container runs schema migrations when it boots, make sure the new schema works correctly with the old version
   of the Docker container, since both will be running simultaneously. Backwards compatibility is always a good idea
   with deployments, but it becomes a hard requirement with canary deployments.


## How do you add additional IAM policies to the ECS Service?

This module creates an [IAM Role for the ECS
Tasks](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html) run by the ECS Service. Any
custom IAM Policies needed by this ECS Service should be attached to that IAM Role.

To do this in Terraform, you can use the
[aws_iam_role_policy](https://www.terraform.io/docs/providers/aws/r/iam_role_policy.html) or
[aws_iam_policy_attachment](https://www.terraform.io/docs/providers/aws/r/iam_policy_attachment.html) resources, and set
the `role` property to the Terraform output of this module called `ecs_task_iam_role_name`. For example, here is how you
can allow the ECS Service in this cluster to access an S3 bucket:

```hcl
module "ecs_service" {
  # (arguments omitted)
}

resource "aws_iam_role_policy" "access_s3_bucket" {
    name   = "access_s3_bucket"
    role   = module.ecs_service.ecs_task_iam_role_name
    policy = data.aws_iam_policy_document.access_s3_bucket.json
}

data "aws_iam_policy_document" "access_s3_bucket" {
  statement {
    effect = "Allow"
    actions = ["s3:GetObject"]
    resources = ["arn:aws:s3:::examplebucket/*"]
  }
}
```


## How do I use Fargate?

A Fargate ECS service automatically manages and scales your cluster as needed without you needing to manage the
underlying EC2 instances or clusters. Fargate lets you focus on designing and building your applications instead of
managing the infrastructure that runs them, with Fargate, all you have to do is package your application in containers,
specify the CPU and memory requirements, define networking and IAM policies, and launch the application.

To deploy your ECS service using Fargate, you need to set the following inputs:

- `launch_type` should be set to `FARGATE`.
- Fargate currently only works with the `awsvpc` network mode. This means that you need to set
  `ecs_task_definition_network_mode` to `"awsvpc"` and configure the service network using
  `ecs_service_network_configuration`.
- You must specify `task_cpu` and `task_memory`. See [the official documentation for information on how to configure
  this](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html#fargate-tasks-size).



## How do you scale an ECS Service?

To scale an ECS service in response to higher load, you have two options:

1. **Scale the number of ECS Tasks**: To do this, you first create one or
   more [`aws_appautoscaling_policy`](https://www.terraform.io/docs/providers/aws/r/appautoscaling_policy.html)
   resources that define how to scale the number of ECS Tasks up or down. These should be associated with the
   [`aws_appautoscaling_target`](https://www.terraform.io/docs/providers/aws/r/appautoscaling_target.html) that is created
   by this module (output `service_app_autoscaling_target_arn`). Finally, you create one or more
   [`aws_cloudwatch_metric_alarm`](https://www.terraform.io/docs/providers/aws/r/cloudwatch_metric_alarm.html) resources
   that trigger your `aws_appautoscaling_policy` resources when certain metrics cross specific thresholds (e.g. when
   CPU usage is over 90%).
1. **Scale the number of ECS Instances and Tasks**: If your ECS Cluster doesn't have enough spare capacity, then not
   only will you have to scale the number of ECS Tasks as described above, but you'll also have to increase the
   size of the cluster by scaling the number of ECS Instances. To do that, you create one or more
   [`aws_autoscaling_policy`](https://www.terraform.io/docs/providers/aws/r/autoscaling_policy.html) resources with the
   `autoscaling_group_name` parameter set to the `ecs_cluster_asg_name` output of the `ecs-cluster` module. Next, you
   create one or more
   [`aws_cloudwatch_metric_alarm`](https://www.terraform.io/docs/providers/aws/r/cloudwatch_metric_alarm.html) resources
   that trigger your `aws_autoscaling_policy` resources when certain metrics cross specific thresholds (e.g. when
   CPU usage is over 90%).

See the [docker-service-with-autoscaling example](/examples/docker-service-with-autoscaling) for sample code.


## How do I associate the ECS Service with a CLB?

To associate the ECS service with an existing CLB, you need to first ensure the CLB exists. Then, you need to pass in
the following inputs to the module:

- `clb_name` should be set to the name of the CLB. This ensures the ECS service will register against the correct CLB.
- `clb_container_name` and `clb_container_port` should be set to the name of the container (as defined in the task
  container definition json) and port of the container. This ensures the CLB routes to the correct container if an ECS
  task has multiple containers.


## How do I associate the ECS Service with an ALB or NLB?

In AWS, to create an ECS Service with an ALB or NLB, we need the following resources:

- ALB or NLB
  - [ALB/NLB itself](https://www.terraform.io/docs/providers/aws/r/lb.html): This is the load balancer that receives
    inbound requests and routes them to our ECS Service.
  - [Load Balancer Listener](https://www.terraform.io/docs/providers/aws/r/lb_listener.html): An ALB/NLB will only
    listen for incoming traffic on ports for which there is a Load Balancer Listener defined. For example, if you want
    the ALB/NLB to accept traffic on port 80, you must define an Listener for port 80.
  - [ALB Listener Rule (only for ALB)](https://www.terraform.io/docs/providers/aws/r/lb_listener_rule.html): Once an ALB
    Listener receives traffic, which [Target
    Group](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html) (Docker
    containers) should it route the requests to? We must define ALB Listener Rules that route inbound requests
    based on either their hostname (e.g. `gruntwork.io` vs `amazon.com`), their path (e.g. `/foo` vs. `/bar`), or both.
    Note that for NLBs, there is only one target so this should be set directly on the listener.
  - [Target Group](https://www.terraform.io/docs/providers/aws/r/lb_target_group.html): The ALB Listener Rule (or LB
    Listener for NLB) routes requests by determining a "Target Group". It then picks one of the
    [Targets](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html#registered-targets)
    in the Target Group (typically, a Docker container or EC2 Instance) as the final destination for the request.

- ECS Cluster
  - [ECS Cluster itself](https://www.terraform.io/docs/providers/aws/r/ecs_cluster.html): The ECS Cluster is where all
    our Docker containers are run.

- ECS Service
  - [ECS Task Definition](https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html): To define which Docker
    image we want to run, how much memory/CPU to allocate it, which `docker run` commmand to use, environment variables,
    and [every other aspect of the Docker container configuration](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html),
    we create an "ECS Task Definition". The idea behind the name is that an ECS Cluster could, in theory, run many types
    of tasks, and Docker is just one such type. Therefore, rather than calling tasks "Docker containers", Amazon uses
    the name "ECS Task".
  - [ECS Service itself](https://www.terraform.io/docs/providers/aws/r/ecs_service.html): When we want to run multiple
    ECS Tasks as part of a single service (i.e. run multiple Docker containers as part of a single service), enable
    auto-restart if a container fails, and enable the ELB to automatically discover newly launched ECS Tasks, we create
    an "ECS Service".

To clarify the relationship between these entities:

When creating your ALB/NLB, ECS Cluster, and ECS Service for the first time:
  - First create your ALB/NLB (see module
    [alb](https://github.com/gruntwork-io/terraform-aws-load-balancer/tree/main/modules/alb) for ALBs and the [aws_lb
    resource](https://www.terraform.io/docs/providers/aws/r/lb.html))
  - Then create your ECS Cluster (see module [ecs-cluster](../ecs-cluster) for EC2 based clusters and [aws_ecs_cluster resource](https://www.terraform.io/docs/providers/aws/d/ecs_cluster.html) for Fargate)
  - Finally, create your ECS Service (this module!)
  - For ALBs, register listener rules to setup routing rules for your service. For NLBs, create the listener so that it
    routes to the target group of the service using [aws_lb_listener
    resource](https://www.terraform.io/docs/providers/aws/r/lb_listener.html).

When creating a new ECS Service that uses existing ALBs or NLBs and an existing ECS Cluster, you will need to set the
following inputs:
  - If creating the LB and ECS service in the same module, `dependencies` should include the ALB arn so that the module
    waits for the LB to be created.
  - `elb_target_groups` should be set to a map of keys to objects with one mapping per desired target group. The keys in the map can be any arbitrary name and are used to link the outputs with the inputs. The values of the map are an object containing these attributes:
    - If you use `alb` as the key then you'll reference the ARN of the resulting target group like this `module.ecs_service.target_group_arns["alb"]`
    - `name` should be set to a string so that it is not null. This ensures the module creates a target
    group for the ECS service.
    - `container_name` and `container_port` should be set to the name of the container (as defined in the task container
      definition json) and port of the container. This ensures the CLB routes to the correct container if an ECS task
      has multiple containers.
    - `protocol` should be set to match the protocol of the LB (ex: "HTTPS" or "HTTP" for an ALB) so that it is not null.
    - `health_check_protocol` should be set to match the protocol of the ECS service (ex: "HTTPS" or "HTTP" for a typical web-based service) so that it is not null.
    - `load_balancing_algorithm_type` should be set to either "round_robin" or "least_outstanding_requests". It is "round_robin" by default.
  - `elb_target_group_vpc_id` should be set to the VPC where the ALB lives.

Note that:
  - An ECS Cluster may have one or more ECS Services
  - An ECS Service may be associated with zero or one ALBs/NLBs
  - An ALB/NLB may be shared among multiple ECS Services
  - An ALB has zero or more ALB Listeners
  - Each ALB Listener has zero or more ALB Listener Rules
  - Each NLB Listener has zero Listener Rules
  - A Target Group may receive traffic from zero or more ALBs/NLBs

### Why doesn't this module create [ALB Listener Rules](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html#listener-rules) directly?

In the first version of this module, we attempted to hide the creation of ALB Listener Rules from users. Our thought
process was that the module's API should simplify as much as possible what was actually happening. But in practice we
found that there was more variation than we expected in the different routing rules that customers required, that
supporting any new ALB Listener Rule type (e.g. host-based routing) was cumbersome, and that by wrapping so much
complexity, we ultimately created more confusion, not less.

For this reason, the intent of this module is now about creating an ECS Service that is *ready* to be routed to. But to
complete the configuration, the Terraform code that calls this module should directly create its own set of Terraform
[lb_listener_rule](https://www.terraform.io/docs/providers/aws/r/lb_listener_rule.html) resources to meet the specific
needs of your ECS Cluster.



## How do I setup Service Discovery?

To setup ECS Service Discovery using this module, you need to first create a Service Discovery DNS Namespace (Private or
Public) that the Service Discovery feature can use to manage DNS records for the ECS Service. You can use the
[aws_service_discovery_private_dns_namespace
resource](https://www.terraform.io/docs/providers/aws/r/service_discovery_private_dns_namespace.html)
(for private DNS namespaces) and the
[aws_service_discovery_public_dns_namespace resource](https://www.terraform.io/docs/providers/aws/r/service_discovery_public_dns_namespace.html)
(for public DNS namespaces).

Once the namespace is created, you need to pass in the following inputs to the module:

- Service Discovery currently only works with the `awsvpc` network mode. This means that you need to set
  `ecs_task_definition_network_mode` to `"awsvpc"` and configure the service network using
  `ecs_service_network_configuration`.
- `use_service_discovery` should be set to `true`. This ensures the module will connect the ECS service with the
  provided registry information.
- `discovery_namespace_id` should be set to the ID of the DNS namespace.
- `discovery_name` should be set to the string you wish to use as the DNS subdomain.

Additionally, for public DNS namespaces, you will also need to provide the ID of the Route 53 Hosted Zone that is
associated with the registrar for the domain. When you create a public DNS namespace, it createss a new Hosted Zone that
is not associated with the registrar. This means that DNS calls outside of the VPC will not actually resolve to the ECS
service. To allow the ECS service DNS queries to resolve, we need to create an alias record on the Hosted Zone that is
associated with the registrar to route to the namespace DNS record. This module will create this record for you if you
provide the following inputs:

- `discovery_use_public_dns` should be set to `true`.
- `discovery_original_public_route53_zone_id` should be set to the ID of the Route 53 Hosted Zone that is associated
  with the registrar.
- `discovery_public_dns_namespace_route53_zone_id` should be set to the ID of the Hosted Zone that is associated with
  the DNS namespace.
  


## How do I set up App Mesh?

To set up App Mesh using this module, you must first create a mesh, a virtual service, and a virtual node or virtual router. Creation of these resources
is documented in AWS App Mesh [Getting Started documentation](https://docs.aws.amazon.com/app-mesh/latest/userguide/getting-started-ecs.html). [Terraform modules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appmesh_mesh) are available for all App Mesh resources. 

With those resources set up, the Envoy container can be added to `container_definitions`.

```terraform
container_definitions = [
  {
    name        = "envoy_proxy",
    image       = "840364872350.dkr.ecr.us-west-2.amazonaws.com/aws-appmesh-envoy:v1.19.0.0-prod",
    essential   = true,
    environment = [{
      name  = "APPMESH_RESOURCE_ARN",
      value = "arn:aws:appmesh:us-west-2:111122223333:mesh/apps/virtualNode/serviceB"
    }],
    healthCheck = {
      command = [
        "CMD-SHELL",
        "curl -s http://localhost:9901/server_info | grep state | grep -q LIVE"
      ],
      startPeriod = 10,
      interval    = 5,
      timeout     = 2,
      retries     = 3
    },
    user        = "1337"
  },
  {
    # App container
    # ...
    dependsOn = [{
      containerName = "envoy_proxy"
      condition     = "HEALTHY"
    }]
  }
]

```

The `proxy_configuration` variable needs to be configured as follows:

```terraform
proxy_configuration = {
  type           = "APPMESH"
  container_name = "envoy_proxy"
  properties = {
    AppPorts         = "8080"
    EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
    IgnoredUID       = "1337"
    ProxyEgressPort  = 15001
    ProxyIngressPort = 15000
  }
}
```

See the [AWS documentation](https://docs.aws.amazon.com/app-mesh/latest/userguide/getting-started-ecs.html#update-services) for container and proxy configurations. See the "Task definition json" section for more information.



## Known Issues

### Switching the value of `var.use_auto_scaling`

If you switch `var.use_auto_scaling` from true to false or vice versa, Terraform will attempt to destroy and
re-create the `aws_ecs_service` which has a chain of dependencies that eventually lead to destroying and re-creating
the ECS Service, which will lead to downtime. This is because we conditionally create Terraform resources depending on
the value of`var.use_auto_scaling`, and Terraform can't fully incorporate this concept into its dependency graph.

Fortunately, there's a workaround using manual state manipulation. We'll tell Terraform that the old resource is now
the new one as follows.

```
# If you are changing var.use_auto_scaling from TRUE to FALSE:
terraform state mv module.ecs_service.aws_ecs_service.service_with_auto_scaling module.ecs_service.aws_ecs_service.service_without_auto_scaling

# If you are changing var.use_auto_scaling from FALSE to TRUE:
terraform state mv module.ecs_service.aws_ecs_service.service_without_auto_scaling module.ecs_service.aws_ecs_service.service_with_auto_scaling
```

Now run `terragrunt plan` to confirm that Terraform will only make modifications.

### Gotchas with Service Discovery

* The ECS Service Discovery feature is not yet available in all regions.
For a list of regions where this feature is enabled, please see the [AWS ECS Service Discovery documentation][2].
* The discovery name is not necessarily the same as the name of your service. You can have a different name by which you want to discover your service.
* You can enable ECS Service Discovery only during the creation of your ECS service, not when updating it.
* The network mode of the task definition affects the behavior and configuration of ECS Service Discovery DNS Records.
    * Service discovery with `SRV` DNS records are not yet supported by this module. This means that tasks defined with with `host` or `bridge` network modes that can only be used with this type of record are also not supported.
    * For enabling service discovery, this module uses the `awsvpc` network mode. AWS will attach an Elastic Network Interface to your task, so you have to be aware that EC2 instance types have a [limit of how many ENIs can be attached to them][3].
* For service discovery with public DNS: The hostname is public (e.g. your-company.com), but it still points to a private IP address. Querying a public hostname that points to a private IP address might sometimes yield in empty results and you might be required to force reading from a specific nameserver (such as an amazon name server like ns-67.awsdns-08.com or google's public nameserver), for example: `dig +short @8.8.8.8 my-service.my-company.com`
* In the `aws_lb_target_group`, the `port = 80` field is merely a placeholder. The actual port is determined dynamically when a container launches, but the resource requires a value. The `port = 80` argument can be safely ignored.

## Related Concepts

### ECS clusters

See the [ecs-cluster module](../ecs-cluster).

### ECS services and tasks

See the [ecs-service module](../ecs-service).

### Route 53 Auto Naming Service

Amazon Route 53 auto naming service automates the process of:
* Creating a public or private namespace within a new or existing hosted zone
* Providing a service with the DNS Records configuration and optional health checks

The latter will be used in the Service Registry of your ECS Service Discovery, and it is the only type of service currently supported for this.

Important considerations:
* Public namespaces are accessible on the internet and need the domain to be registered already
* Private namespaces are accessible only within your VPC and can be queried immediately
* For cleaning up, deregistering the instances from the auto naming service will trigger an automatic deletion of resources in AWS. However, the namespaces themselves are not deleted. Namespaces must be deleted manually and that is only allowed once all services in that namespace no longer exist.

For more information on Route 53 Auto Naming Service, please see the AWS documentation on [Using Auto Naming for Service Discovery][4].

[1]:http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html
[2]:https://docs.aws.amazon.com/AmazonECS/latest/developerguide/create-service-discovery.html
[3]:https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI
[4]:https://docs.aws.amazon.com/Route53/latest/APIReference/overview-service-discovery.html
