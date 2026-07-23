################################################################################
# 出力定義
################################################################################

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.main.id
}

output "lb_ip_addresses" {
  description = "Load Balancer IP addresses"
  value       = oci_load_balancer_load_balancer.main.ip_address_details
}

output "lb_id" {
  description = "Load Balancer OCID"
  value       = oci_load_balancer_load_balancer.main.id
}

output "container_instance_id" {
  description = "Container Instance OCID"
  value       = oci_container_instances_container_instance.app.id
}

output "container_instance_state" {
  description = "Container Instance state"
  value       = oci_container_instances_container_instance.app.state
}

output "db_system_id" {
  description = "Database System OCID"
  value       = oci_psql_db_system.main.id
}
