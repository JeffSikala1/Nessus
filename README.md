# Nessus Deployment with Terraform

This project sets up a deployment of Nessus agents on VMs in Azure using Terraform. The configuration includes both Windows and Linux VMs. The Linux VMs use Ubuntu as the base image, while the Windows VM uses a standard Windows Server 2019 image.

## Table of Contents

- [Prerequisites](#prerequisites)
- [File Structure](#file-structure)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Notes](#notes)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed
- Azure CLI installed and configured (`az login`)
- An Azure subscription with sufficient quota for the desired VM sizes

## File Structure

```
├── DeployNessusToVMs.ps1
└── terraform
├── main.tf
├── modules
│ ├── ssh
│ │ ├── main.tf
│ │ └── outputs.tf
│ └── vm
│ ├── main.tf
│ ├── outputs.tf
│ └── variables.tf
├── outputs.tf
├── providers.tf
├── variables.tf
└── terraform.tfstate
```


## Configuration

### Variables

The `variables.tf` file in the `terraform` directory defines the configurable parameters for this deployment. Key variables include:

- `resource_group_name`: The name of the resource group to create.
- `location`: The Azure region to deploy resources.
- `vm_size`: The size of the VMs to deploy.
- `linux_vm_names`: A list of names for the Linux VMs.

### Example `variables.tf`

```hcl
variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
  default     = "East US"
}

variable "vm_size" {
  description = "The size of the virtual machine"
  type        = string
  default     = "Standard_B1ms"
}

variable "linux_vm_names" {
  description = "The names of the Linux VMs"
  type        = list(string)
  default     = ["NessusVM1", "NessusVM2", "NessusVM3"]
}

```
### Notes

`- Ensure that the DeployNessusToVMs.ps1 script is present in the root directory of the project.`

`- The PowerShell script is uploaded to an Azure Storage account and then executed on the Windows VM using the Custom Script Extension.`

`- The Linux VMs use Ubuntu as the base image and set up SSH keys for authentication.`