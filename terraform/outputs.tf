output "vpc_platform_id" {
  description = "Platform VPC ID"
  value       = google_compute_network.vpc_platform.id
}

output "vpc_data_id" {
  description = "Data VPC ID"
  value       = google_compute_network.vpc_data.id
}

output "app_vm_internal_ip" {
  description = "Internal IP of app-vm"
  value       = google_compute_instance.app_vm.network_interface[0].network_ip
}

output "db_vm_internal_ip" {
  description = "Internal IP of db-vm"
  value       = google_compute_instance.db_vm.network_interface[0].network_ip
}

output "vpc_connector_id" {
  description = "VPC Access Connector ID"
  value       = google_vpc_access_connector.connector.id
}

output "psc_endpoint_ip" {
  description = "Private Service Connect endpoint IP"
  value       = google_compute_address.psc_address.address
}

output "peering_status" {
  description = "VPC Peering status"
  value       = google_compute_network_peering.platform_to_data.state
}

output "cloud_run_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.my_api.uri
}
