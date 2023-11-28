# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# These variables must be set.
# ---------------------------------------------------------------------------------------------------------------------

variable "service_name" {
  description = "The name of the service. This is used to namespace all resources created by this module."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the ECS Cluster where this service should run."
  type        = string
}

variable "ecs_task_container_definitions" {
  description = "The JSON text of the ECS Task Container Definitions. This portion of the ECS Task Definition defines the Docker container(s) to be run along with all their properties. It should adhere to the format described at https://goo.gl/ob5U3g."
  type        = string
}

variable "desired_number_of_tasks" {
  description = "How many copies of the Task to run across the cluster."
  type        = number
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables are configurable, but have reasonable defaults set.
# ---------------------------------------------------------------------------------------------------------------------

variable "wait_for_steady_state" {
  description = "If true, Terraform will wait for the service to reach a steady state—as in, the ECS tasks you wanted are actually deployed—before 'apply' is considered complete."
  type        = bool
  default     = false
}

variable "capacity_provider_strategy" {
  description = "The capacity provider strategy to use for the service. Note that the capacity providers have to be present on ECS cluster before deploying ECS service. When provided, var.launch_type is ignored."
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = number
  }))
  default = []

  # Example:
  # capacity_provider_strategy = [
  #    {
  #      capacity_provider = "FARGATE"
  #      weight            = 1
  #      base              = 2
  #    },
  #    {
  #      capacity_provider = "FARGATE_SPOT"
  #      weight            = 2
  #      base              = null
  #    },
  # ]
}

variable "enable_execute_command" {
  description = "Specifies whether to enable Amazon ECS Exec for the tasks within the service."
  type        = bool
  default     = false
}

variable "launch_type" {
  description = "The launch type of the ECS service. Defaults to null, which will result in using the default capacity provider strategyfrom the ECS cluster. Valid value must be one of EC2 or FARGATE. When using FARGATE, you must set the network mode to awsvpc and configure it. When using EC2, you can configure the placement strategy using the variables ordered_placement_strategy, placement_constraint_type, placement_constraint_expression. This variable is ignored if var.capacity_provider_strategy is provided."
  type        = string
  default     = null
}

variable "custom_iam_role_name_prefix" {
  description = "Prefix for name of the IAM role used by the ECS task. If not provide, will be set to var.service_name."
  type        = string
  default     = null
}

variable "custom_task_execution_name_prefix" {
  description = "Prefix for name of task execution IAM role and policy that grants access to CloudWatch and ECR. If not provide, will be set to var.service_name."
  type        = string
  default     = null
}

variable "custom_ecs_service_role_name" {
  description = "Custom name to use for the ECS service IAM role that is created. Note that this service IAM role is only needed when the ECS service is being used with an ELB. If blank (default), the name will be set to var.service_name."
  type        = string
  default     = null
}

variable "volumes" {
  description = "(Optional) A map of volume blocks that containers in your task may use. The key should be the name of the volume and the value should be a map compatible with https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html#volume-block-arguments, but not including the name parameter."
  # Ideally, this would be a map of (string, object), but object does not support optional properties, whereas the
  # volume definition supports a number of optional properties. We can't use a map(any) either, as that would require
  # the values to all have the same type, and due to optional parameters, that wouldn't work either. So, we have to
  # lamely fall back to any.
  type    = any
  default = {}

  # Example:
  # volumes = {
  #   datadog = {
  #     host_path = "/var/run/datadog"
  #   }
  #
  #   logs = {
  #     host_path = "/var/log"
  #     docker_volume_configuration = {
  #       scope         = "shared"
  #       autoprovision = true
  #       driver        = "local"
  #     }
  #   }
  # }
}

variable "efs_volumes" {
  description = "(Optional) A map of EFS volumes that containers in your task may use. Each item in the list should be a map compatible with https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html#efs-volume-configuration-arguments."
  type = map(object({
    file_system_id          = string # required
    container_path          = string # required
    root_directory          = string
    transit_encryption      = string
    transit_encryption_port = number
    access_point_id         = string
    iam                     = string
  }))
  default = {}

  # Example:
  # efs_volumes = {
  #   jenkins = {
  #     file_system_id          = "fs-a1bc234d"
  #     container_path          = "/efs"
  #     root_directory          = "/jenkins"
  #     transit_encryption      = "ENABLED"
  #     transit_encryption_port = 2999
  #     access_point_id         = "fsap-123a4b5c5d7891234"
  #     iam                     = "ENABLED"
  #   }
  # }
}

variable "service_tags" {
  description = "A map of tags to apply to the ECS service. Each item in this list should be a map with the parameters key and value."
  type        = map(string)
  default     = {}
  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }
}

variable "task_definition_tags" {
  description = "A map of tags to apply to the task definition. Each item in this list should be a map with the parameters key and value."
  type        = map(string)
  default     = {}
  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }
}

variable "lb_target_group_tags" {
  description = "A map of tags to apply to the elb target group. Each item in this list should be a map with the parameters key and value."
  type        = map(string)
  default     = {}
  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }
}

variable "platform_version" {
  description = "The platform version on which to run your service. Only applicable for launch_type set to FARGATE. Defaults to LATEST."
  type        = string
  default     = null
}

variable "propagate_tags" {
  description = "Whether tags should be propogated to the tasks from the service or from the task definition. Valid values are SERVICE and TASK_DEFINITION. Defaults to SERVICE. If set to null, no tags are created for tasks."
  type        = string
  default     = "SERVICE"
}

variable "additional_task_assume_role_policy_principals" {
  description = "A list of additional principals who can assume the task and task execution roles"
  type        = list(string)
  default     = []
}

# Network configuration

variable "ecs_task_definition_network_mode" {
  description = "The Docker networking mode to use for the containers in the task. The valid values are none, bridge, awsvpc, and host"
  type        = string
  default     = "bridge"
}

variable "ecs_service_network_configuration" {
  description = "The configuration to use when setting up the VPC network mode. Required and only used if ecs_task_definition_network_mode is awsvpc."
  type = object({
    subnets          = list(string)
    security_groups  = list(string)
    assign_public_ip = bool
  })
  default = null
}

# Canary configuration

variable "desired_number_of_canary_tasks_to_run" {
  description = "How many Tasks to run of the var.ecs_task_definition_canary to deploy for a canary deployment. Typically, only 0 or 1 should be used."
  type        = number
  default     = 0
}

variable "ecs_task_definition_canary" {
  description = "The JSON text of the ECS Task Definition to be run for the canary. This defines the Docker container(s) to be run along with all their properties. It should adhere to the format described at https://goo.gl/ob5U3g."
  type        = string
  default     = "[{ \"name\":\"not-used\" }]"
}

# Autoscaling configuration

variable "use_auto_scaling" {
  description = "Set this variable to 'true' to tell the ECS service to ignore var.desired_number_of_tasks and instead use auto scaling to determine how many Tasks of this service to run."
  type        = bool
  default     = false
}

variable "min_number_of_tasks" {
  description = "The minimum number of ECS Task instances of the ECS Service to run. Auto scaling will never scale in below this number. Must be set when var.use_auto_scaling is true."
  type        = number
  default     = null
}

variable "max_number_of_tasks" {
  description = "The maximum number of ECS Task instances of the ECS Service to run. Auto scaling will never scale out above this number. Must be set when var.use_auto_scaling is true."
  type        = number
  default     = null
}

variable "deployment_maximum_percent" {
  description = "The upper limit, as a percentage of var.desired_number_of_tasks, of the number of running tasks that can be running in a service during a deployment. Setting this to more than 100 means that during deployment, ECS will deploy new instances of a Task before undeploying the old ones."
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "The lower limit, as a percentage of var.desired_number_of_tasks, of the number of running tasks that must remain running and healthy in a service during a deployment. Setting this to less than 100 means that during deployment, ECS may undeploy old instances of a Task before deploying new ones."
  type        = number
  default     = 100
}

variable "deployment_controller" {
  description = "Type of deployment controller, possible values: CODE_DEPLOY, ECS, EXTERNAL"
  type        = string
  default     = null
}

# Circuit Breaker configuration

variable "deployment_circuit_breaker" {
  description = "Set enable to 'true' to prevent the task from attempting to continuously redeploy after a failed health check. Set rollback to 'true' to also automatically roll back to the last successful deployment. If this setting is used, both 'enable' and 'rollback' are required fields."
  type = object({
    enable   = bool
    rollback = bool
  })
  default = null
}

variable "proxy_configuration" {
  description = "Configuration block for the App Mesh proxy. The only supported value for `type` is \"APPMESH\". Use the name of the Envoy proxy container from `container_definitions` as the `container_name`. `properties` is a map of network configuration parameters to provide the Container Network Interface (CNI) plugin."
  type = object({
    type           = string
    container_name = string
    properties     = map(string)
  })
  default = null

  # Example:
  # proxy_configuration = {
  #   type           = "APPMESH"
  #   container_name = "applicationContainerName"
  #   properties = {
  #     AppPorts         = "8080"
  #     EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
  #     IgnoredUID       = "1337"
  #     ProxyEgressPort  = 15001
  #     ProxyIngressPort = 15000
  #   }
  # }
}

# Service Discovery configuration

variable "use_service_discovery" {
  description = "Set this variable to 'true' to setup service discovery for the ECS service by automatically registering the task IPs to a registry that is created within this module. Currently this is only supported with the 'awsvpc' networking mode."
  type        = bool
  default     = false
}

variable "discovery_namespace_id" {
  description = "The id of the previously created namespace for service discovery. It will be used to form the service discovery address along with the discovery name in <discovery_name>.<namespace_name>. So if your discovery name is 'my-service' and your namespace name is 'my-company-staging.local', the hostname for the service will be 'my-service.my-company-staging.local'. Only used if var.use_service_discovery is true."
  type        = string
  default     = null
}

variable "discovery_name" {
  description = "The name by which the service can be discovered. It will be used to form the service discovery address along with the namespace name in <discovery_name>.<namespace_name>. So if your discovery name is 'my-service' and your namespace name is 'my-company-staging.local', the hostname for the service will be 'my-service.my-company-staging.local'. Only used if var.use_service_discovery is true."
  type        = string
  default     = null
}

variable "discovery_custom_health_check_failure_threshold" {
  description = "The number of 30-second intervals that you want service discovery to wait before it changes the health status of a service instance. Maximum value of 10. Only used if var.use_service_discovery is true."
  type        = number
  default     = 1
}

variable "discovery_dns_ttl" {
  description = "The amount of time, in seconds, that you want DNS resolvers to cache the settings for this resource record set. Only used if var.use_service_discovery is true."
  type        = number
  default     = 60
}

variable "discovery_dns_routing_policy" {
  description = "The routing policy that you want to apply to all records that Route 53 creates when you register an instance and specify the service. Valid Values: MULTIVALUE, WEIGHTED. Only used if var.use_service_discovery is true."
  type        = string
  default     = "MULTIVALUE"
}

variable "discovery_use_public_dns" {
  description = "Set this variable to 'true' when using public DNS namespaces. Only used if var.use_service_discovery is true."
  type        = bool
  default     = false
}

variable "discovery_original_public_route53_zone_id" {
  description = "The ID of the original Route 53 Hosted Zone where associated with the domain registrar. Only used if var.discovery_use_public_dns is true."
  type        = string
  default     = null
}

variable "discovery_public_dns_namespace_route53_zone_id" {
  description = "The ID of the new Route 53 Hosted Zone created for the public DNS namespace. Only used if var.discovery_use_public_dns is true."
  type        = string
  default     = null
}

variable "discovery_alias_record_evaluate_target_health" {
  description = "Check alias target health before routing to the service. Only used if var.discovery_use_public_dns is true."
  type        = bool
  default     = true
}


# Load Balancer configuration

variable "clb_name" {
  description = "The name of a Classic Load Balancer (CLB) to associate with this service. Containers in the service will automatically register with the CLB when booting up. Set to null if using ELBv2."
  type        = string
  default     = null
}

variable "clb_container_name" {
  description = "The name of the container, as it appears in the var.task_arn Task definition, to associate with a CLB. Currently, ECS can only associate a CLB with a single container per service. Only used if clb_name is set."
  type        = string
  default     = null
}

variable "clb_container_port" {
  description = "The port on the container in var.clb_container_name to associate with an CLB. Currently, ECS can only associate a CLB with a single container per service. Only used if clb_name is set."
  type        = number
  default     = null
}

variable "elb_target_groups" {
  description = "Configurations for ELB target groups for ALBs and NLBs that should be associated with the ECS Tasks. Each entry corresponds to a separate target group. Set to the empty object ({}) if you are not using an ALB or NLB."
  # Ideally, we will use a more strict type here but since we want to support required and optional values,
  # we have to use the unsafe `any` type.
  type = any

  # `elb_target_groups` should be set to a map of keys to objects with one mapping per desired target group. The keys
  # in the map can be any arbitrary name and are used to link the outputs with the inputs. The values of the map are an
  # object containing these attributes:

  # REQUIRED:
  #
  # - name   string                          : The name of the ELB Target Group that will contain the ECS Tasks.
  #
  # - container_name   string                : The name of the container, as it appears in the var.task_arn Task
  #                                            definition, to associate with the target group.
  #
  # - container_port = number                : The port on the container to associate with the target group.
  #
  # OPTIONAL:
  #
  # - protocol   string                      : The network protocol to use for routing traffic from the ELB to the
  #                                            Targets. Must be one of TCP, TLS, UDP, TCP_UDP, HTTP or HTTPS. Note that
  #                                            when using ALBs, must be HTTP or HTTPS. Defaults to TCP.
  #
  # - protocol_version   string              : Only applicable when `protocol` is `HTTP` or `HTTPS`. The protocol version.
  #                                            Specify GRPC to send requests to targets using gRPC. Specify HTTP2 to send 
  #                                            requests to targets using HTTP/2. The default is HTTP1, which sends 
  #                                            requests to targets using HTTP/1.1
  #
  # - health_check_protocol   string         : The protocol the ELB uses when performing health checks on Targets. Must
  #                                            be one of TCP, TLS, UDP, TCP_UDP, HTTP or HTTPS. Note that when using
  #                                            ALBs, must be HTTP or HTTPS. Defaults to TCP.
  #
  # - load_balancing_algorithm_type   string : Determine how the load balancer selects targets when routing requests.
  #                                            Allowed values are `round_robin` or `least_outstanding_requests` for
  #                                            ALBs. Defaults to `round_robin` for ALBs. Defaults to `null` for NLBs.
  #
  # Example:
  # elb_target_groups = {
  #   nlb = {
  #     name                          = var.service_name
  #     container_name                = var.service_name
  #     container_port                = var.http_port
  #     protocol                      = "TCP"
  #     health_check_protocol         = "TCP"
  #     load_balancing_algorithm_type = null
  #   },
  #   alb = {
  #     name                          = var.service_name
  #     container_name                = var.container_name
  #     container_port                = var.container_http_port
  #     protocol                      = "HTTP"
  #     health_check_protocol         = "HTTP"
  #     load_balancing_algorithm_type = "round_robin"
  #   }
  # }
  default = {}
}

variable "elb_target_group_vpc_id" {
  description = "The ID of the VPC in which to create the target group. Only used if var.elb_target_group_name is set."
  type        = string
  default     = null
}

variable "elb_target_group_deregistration_delay" {
  description = "The amount of time for Elastic Load Balancing to wait before changing the state of a deregistering target from draining to unused. The range is 0-3600 seconds. Only used if var.elb_target_group_name is set."
  type        = number
  default     = 300
}

variable "elb_slow_start" {
  description = "The amount time for targets to warm up before the load balancer sends them a full share of requests. The range is 30-900 seconds or 0 to disable. The default value is 0 seconds. Only used if var.elb_target_group_name is set."
  type        = number
  default     = 0
}

variable "use_alb_sticky_sessions" {
  description = "If true, the ALB will use use Sticky Sessions as described at https://goo.gl/VLcNbk. Only used if var.elb_target_group_name is set. Note that this can only be true when associating with an ALB. This cannot be used with CLBs or NLBs."
  type        = bool
  default     = false
}

variable "alb_sticky_session_type" {
  description = "The type of Sticky Sessions to use. See https://goo.gl/MNwqNu for possible values. Only used if var.elb_target_group_name is set."
  type        = string
  default     = "lb_cookie"
}

variable "alb_sticky_session_cookie_duration" {
  description = "The time period, in seconds, during which requests from a client should be routed to the same Target. After this time period expires, the load balancer-generated cookie is considered stale. The acceptable range is 1 second to 1 week (604800 seconds). The default value is 1 day (86400 seconds). Only used if var.elb_target_group_name is set."
  type        = number
  default     = 86400
}

variable "elb_role_permissions_boundary_arn" {
  description = "The ARN of the policy that is used to set the permissions boundary for the IAM role for the ELB."
  type        = string
  default     = null
}

### LB Health Check configurations

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown, up to 2,147,483,647. Only valid for services configured to use load balancers."
  type        = number
  default     = 0
}

variable "health_check_enabled" {
  description = "If true, enable health checks on the target group. Only applies to ELBv2. For CLBs, health checks are not configurable."
  type        = bool
  default     = true
}

variable "health_check_interval" {
  description = "The approximate amount of time, in seconds, between health checks of an individual Target. Minimum value 5 seconds, Maximum value 300 seconds."
  type        = number
  default     = 30
}

variable "health_check_path" {
  description = "The ping path that is the destination on the Targets for health checks. Required when using ALBs."
  type        = string
  default     = "/"
}

variable "health_check_port" {
  description = "The port the ELB uses when performing health checks on Targets. The default is to use the port on which each target receives traffic from the load balancer, indicated by the value 'traffic-port'."
  type        = string
  default     = "traffic-port"
}

variable "health_check_timeout" {
  description = "The amount of time, in seconds, during which no response from a Target means a failed health check. The acceptable range is 2 to 60 seconds."
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "The number of consecutive successful health checks required before considering an unhealthy Target healthy. The acceptable range is 2 to 10."
  type        = number
  default     = 5
}

variable "health_check_unhealthy_threshold" {
  description = "The number of consecutive failed health checks required before considering a target unhealthy. The acceptable range is 2 to 10. For NLBs, this value must be the same as the health_check_healthy_threshold."
  type        = number
  default     = 2
}

variable "health_check_matcher" {
  description = "The HTTP codes to use when checking for a successful response from a Target. You can specify multiple values (e.g. '200,202') or a range of values (e.g. '200-299'). Required when using ALBs."
  type        = string
  default     = "200"
}

variable "runtime_platform" {
  description = "Define runtime platform options"
  type = object({
    operating_system_family = string
    cpu_architecture        = string
  })
  default = null
}


# ---------------------------------------------------------------------------------------------------------------------
# ECS TASK PLACEMENT PARAMETERS
# These variables are used to determine where ecs tasks should be placed on a cluster.
#
# https://www.terraform.io/docs/providers/aws/r/ecs_service.html#placement_strategy-1
# https://www.terraform.io/docs/providers/aws/r/ecs_service.html#placement_constraints-1
#
# Since placement_strategy and placement_constraint are inline blocks and you can't use count to make them conditional,
# we give some sane defaults here
# ---------------------------------------------------------------------------------------------------------------------

variable "ordered_placement_strategy" {
  type = list(object({
    type  = string
    field = string
  }))
  default = [
    {
      type  = "binpack"
      field = "cpu"
    }
  ]
  description = "Service level strategy rules that are taken into consideration during task placement. List from top to bottom in order of precedence. Updates to this configuration will take effect next task deployment unless force_new_deployment is enabled. The maximum number of ordered_placement_strategy blocks is 5."
  validation {
    condition     = length(var.ordered_placement_strategy) <= 5
    error_message = "The maximum number of ordered_placement_strategy blocks is 5."
  }

}

variable "placement_constraint_type" {
  type    = string
  default = "memberOf"
}

variable "placement_constraint_expression" {
  type    = string
  default = "attribute:ecs.ami-id != 'ami-fake'"
}

variable "task_cpu" {
  description = "The CPU units for the instances that Fargate will spin up. Options here: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html#fargate-tasks-size. Required when using FARGATE launch type."
  type        = number
  default     = null
}

variable "task_memory" {
  description = "The memory units for the instances that Fargate will spin up. Options here: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html#fargate-tasks-size. Required when using FARGATE launch type."
  type        = number
  default     = null
}

variable "task_ephemeral_storage" {
  description = "Ephemeral storage size for Fargate tasks. See: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_definition_ephemeralStorage"
  default     = null
  type        = number
}

variable "task_role_permissions_boundary_arn" {
  description = "The ARN of the policy that is used to set the permissions boundary for the IAM role for the ECS task."
  type        = string
  default     = null
}

variable "task_execution_role_permissions_boundary_arn" {
  description = "The ARN of the policy that is used to set the permissions boundary for the IAM role for the ECS task execution."
  type        = string
  default     = null
}

variable "existing_ecs_task_role_name" {
  description = "The name of the existing task role to be used in place of creating a new role."
  default     = null
}

variable "existing_ecs_task_execution_role_name" {
  description = "The name of the existing task execution role to be used in place of creating a new role."
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# ECS DEPLOYMENT CHECK OPTIONS
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_ecs_deployment_check" {
  description = "Whether or not to enable the ECS deployment check binary to make terraform wait for the task to be deployed. See ecs_deploy_check_binaries for more details. You must install the companion binary before the check can be used. Refer to the README for more details."
  type        = bool
  default     = true
}

variable "deployment_check_timeout_seconds" {
  description = "Seconds to wait before timing out each check for verifying ECS service deployment. See ecs_deploy_check_binaries for more details."
  type        = number
  default     = 600
}

variable "deployment_check_loglevel" {
  description = "Set the logging level of the deployment check script. You can set this to `error`, `warn`, or `info`, in increasing verbosity."
  type        = string
  default     = "info"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE DEPENDENCIES
# Workaround Terraform limitation where there is no module depends_on.
# See https://github.com/hashicorp/terraform/issues/1178 for more details.
# This can be used to make sure the module resources are created after other bootstrapping resources have been created.
# For example, in GKE, the default permissions are such that you do not have enough authorization to be able to create
# additional Roles in the system. Therefore, you need to first create a ClusterRoleBinding to promote your account
# before you can apply this module. In this use case, you can pass in the ClusterRoleBinding as a dependency into this
# module:
# dependencies = ["${kubernetes_cluster_role_binding.user.metadata.0.name}"]
# ---------------------------------------------------------------------------------------------------------------------

variable "dependencies" {
  description = "Create a dependency between the resources in this module to the interpolated values in this list (and thus the source resources). In other words, the resources in this module will now depend on the resources backing the values in this list such that those resources need to be created before the resources in this module, and the resources in this module need to be destroyed before the resources in the list."
  type        = list(string)
  default     = []
}

# Workaround Terraform limitation to wait for external listener rules to be created first and after allow creation of
# ECS cluster and avoid race conditions.
# listener_rule_ids = [ aws_alb_listener_rule.host_based_example.id ]
variable "listener_rule_ids" {
  description = "Listener rules list required first to be provisioned before creation of ECS cluster."
  type        = list(string)
  default     = []
}
