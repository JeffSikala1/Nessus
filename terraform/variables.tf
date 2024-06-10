variable "resource_group_name" {
    description = "The name of the resource group in which to create the resources"
    type        = string
    default     = "NessusVMsRG"  
}

variable "location" {
    description = "The region the resources will be created"
    type        = string
    default     = "East US"
}

variable "vm_size" {
    description = "The size of the VM"
    type        = string
    default     = "Standard_D4s_v3"
}

variable "admin_username" {
    description = "The username for the windows VM"
    type        = string
    default     = "nessusadmin"
}

variable "admin_password" {
    description = "The password for the windows VM"
    type        = string
    default     = "P@ssw0rd1234!"
}

variable "linux_vm_names" {
    description = "The names of the linux VMs"
    type        = list(string)
    default     = ["NessusVM1", "NessusVM2", "NessusVM3"]
}

variable "ssh_username" {
  description = "The SSH username for the Linux VMs"
  type        = string
  default     = "nessus"
}