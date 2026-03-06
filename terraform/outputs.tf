output "app_vm_ip" {
  description = "Internal IP of app-vm (vpc-platform)"
  value       = google_compute_instance.app_vm.network_interface[0].network_ip
}

output "data_vm_ip" {
  description = "Internal IP of data-vm (vpc-data)"
  value       = google_compute_instance.data_vm.network_interface[0].network_ip
}

output "security_vm_ip" {
  description = "Internal IP of security-vm (vpc-security)"
  value       = google_compute_instance.security_vm.network_interface[0].network_ip
}

output "peering_platform_data" {
  description = "platform ↔ data peering state"
  value       = google_compute_network_peering.platform_to_data.state
}

output "peering_data_security" {
  description = "data ↔ security peering state"
  value       = google_compute_network_peering.data_to_security.state
}
