# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ECS SERVICE DISCOVERY SERVICE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_service_discovery_service" "discovery" {
  count = var.use_service_discovery ? 1 : 0

  name = var.discovery_name

  dns_config {
    namespace_id = var.discovery_namespace_id

    dns_records {
      ttl  = var.discovery_dns_ttl
      type = "A"
    }

    routing_policy = var.discovery_dns_routing_policy
  }

  health_check_custom_config {
    failure_threshold = var.discovery_custom_health_check_failure_threshold
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALIAS RECORD FOR THE SERVICE
# The public DNS namespace for AWS Service Discovery creates a new Hosted Zone that is not associated with the actual
# domain registrar. Because this new hosted zone isn't associated with the actual domain registrar, public DNS queries
# will not resolve correctly for the domains registered there. Therefore, we offer an option to create an alias record
# for the actual hosted zone asssociated with the registrar that links to the record created by the Auto Naming Service.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_route53_record" "default" {
  count   = var.discovery_use_public_dns ? 1 : 0
  zone_id = var.discovery_original_public_route53_zone_id
  name    = "${var.service_name}.${data.aws_route53_zone.registrar[0].name}"
  type    = "A"

  alias {
    name                   = "${var.service_name}.${data.aws_route53_zone.namespace[0].name}"
    zone_id                = var.discovery_public_dns_namespace_route53_zone_id
    evaluate_target_health = var.discovery_alias_record_evaluate_target_health
  }
}

data "aws_route53_zone" "registrar" {
  count   = var.discovery_use_public_dns ? 1 : 0
  zone_id = var.discovery_original_public_route53_zone_id
}

data "aws_route53_zone" "namespace" {
  count   = var.discovery_use_public_dns ? 1 : 0
  zone_id = var.discovery_public_dns_namespace_route53_zone_id
}
