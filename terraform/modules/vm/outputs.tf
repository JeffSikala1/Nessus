output "private_ip" {
  description = "The private IP address of the VM"
  value       = azurerm_network_interface.vm_nic.private_ip_address 
}