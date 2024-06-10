output "ssh_private_key" {
  description = "The private key for the linux VMs"
  value       = module.ssh_key.ssh_private_key
}

output "windows_vm_ip" {
  value = module.nessus_windows.private_ip
}

output "linux_vm_ips" {
  value = [for vm in module.nessus_linux : vm.private_ip]
}