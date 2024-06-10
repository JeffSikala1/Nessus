# Create a resource group
resource "azurerm_resource_group" "nessus_vms_rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create a virtual network
resource "azurerm_virtual_network" "nessus_vnet" {
  name                = "nessus-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.nessus_vms_rg.location
  resource_group_name = azurerm_resource_group.nessus_vms_rg.name
}

# Create a subnet
resource "azurerm_subnet" "vm_subnet" {
  name                 = "vm-subnet"
  resource_group_name  = azurerm_resource_group.nessus_vms_rg.name
  virtual_network_name = azurerm_virtual_network.nessus_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create a storage account
resource "azurerm_storage_account" "nessus_storage" {
  name                     = "nessusstoragacct" # Will need to update this to be globally unique
  resource_group_name      = azurerm_resource_group.nessus_vms_rg.name
  location                 = azurerm_resource_group.nessus_vms_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create a storage container
resource "azurerm_storage_container" "nessus_container" {
  name                  = "nessuscontainer"
  storage_account_name  = azurerm_storage_account.nessus_storage.name
  container_access_type = "blob"
}

# Upload the PowerShell script to the storage container
resource "azurerm_storage_blob" "nessus_script" {
  name                   = "DeployNessusToVMs.ps1"
  storage_account_name   = azurerm_storage_account.nessus_storage.name
  storage_container_name = azurerm_storage_container.nessus_container.name
  type                   = "Block"
  source                 = "../DeployNessusToVMs.ps1"
}

# Create a module for SSH keys
module "ssh_key" {
  source = "./modules/ssh"
}

# Module for Windows master Nessus VM
module "nessus_windows" {
  source              = "./modules/vm"
  resource_group_name = azurerm_resource_group.nessus_vms_rg.name
  vm_name             = "NessusWindowsVM"
  location            = var.location
  vm_size             = "Standard_B1ms" 
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  os_type             = "Windows"
  script_url          = "https://${azurerm_storage_account.nessus_storage.name}.blob.core.windows.net/${azurerm_storage_container.nessus_container.name}/DeployNessusToVMs.ps1"
  script_path         = "C:\\Temp\\DeployNessusToVMs.ps1"
  storage_account_name = azurerm_storage_account.nessus_storage.name
  storage_account_key  = azurerm_storage_account.nessus_storage.primary_access_key
  subnet_id            = azurerm_subnet.vm_subnet.id
}

# Module for Linux Nessus VMs
module "nessus_linux" {
  source              = "./modules/vm"
  for_each            = toset(var.linux_vm_names)
  resource_group_name = azurerm_resource_group.nessus_vms_rg.name
  vm_name             = each.value
  vm_size             = "Standard_B1ms" 
  ssh_username        = module.ssh_key.ssh_user
  ssh_public_key      = module.ssh_key.ssh_public_key
  os_type             = "Linux"
  admin_username      = var.admin_username
  location            = var.location
  script_url          = "https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents/downloads/23248/download?i_agree_to_tenable_license_agreement=true"
  script_path         = "/tmp/DeployNessusToVMs.ps1"
  storage_account_name = azurerm_storage_account.nessus_storage.name
  storage_account_key  = azurerm_storage_account.nessus_storage.primary_access_key
  subnet_id            = azurerm_subnet.vm_subnet.id
}

# Assign the Contributor role to the service principal on the resource group
resource "azurerm_role_assignment" "sp_assignment" {
  principal_id        = data.azurerm_client_config.current.object_id
  role_definition_name = "Contributor"
  scope               = azurerm_resource_group.nessus_vms_rg.id
}
