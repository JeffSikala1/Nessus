variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The location for the resources"
  type        = string
}

variable "vm_name" {
  description = "The name of the virtual machine"
  type        = string
}

variable "vm_size" {
  description = "The size of the virtual machine"
  type        = string
}

variable "admin_username" {
  description = "The admin username for the virtual machine"
  type        = string
}

variable "admin_password" {
  description = "The admin password for the virtual machine (only for Windows VMs)"
  type        = string
  default     = ""
}

variable "ssh_username" {
  description = "The SSH username for the virtual machine (only for Linux VMs)"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "The SSH public key for the virtual machine (only for Linux VMs)"
  type        = string
  default     = ""
}

variable "os_type" {
  description = "The operating system type of the virtual machine (Windows or Linux)"
  type        = string
}

variable "script_url" {
  description = "The URL of the script to run on the virtual machine"
  type        = string
  default = "https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents/downloads/23248/download?i_agree_to_tenable_license_agreement=true"
}

variable "script_path" {
  description = "The path to the script on the virtual machine"
  type        = string
  default     = "C:\\Temp\\InstallNessusAgent.ps1"
}

variable "storage_account_name" {
  description = "The name of the storage account"
  type        = string
}

variable "storage_account_key" {
  description = "The key of the storage account"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet"
  type        = string
}