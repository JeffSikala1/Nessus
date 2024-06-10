resource "azurerm_network_interface" "vm_nic" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

# Resource block for Linux VMs
resource "azurerm_virtual_machine" "linux_vm" {
  count                = var.os_type == "Linux" ? 1 : 0
  name                 = var.vm_name
  location             = var.location
  resource_group_name  = var.resource_group_name
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  vm_size              = var.vm_size

  os_profile {
    computer_name  = var.vm_name
    admin_username = var.admin_username
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"  #new
      key_data = var.ssh_public_key
    }
  }

  storage_os_disk {
    name              = "${var.vm_name}-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"  #new
    offer     = "UbuntuServer"  #new
    sku       = "18.04-LTS"  #new
    version   = "latest"  #new
  }

  tags = {
    environment = "test"
  }
}

# Resource block for Windows VMs
resource "azurerm_virtual_machine" "windows_vm" {
  count                = var.os_type == "Windows" ? 1 : 0
  name                 = var.vm_name
  location             = var.location
  resource_group_name  = var.resource_group_name
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  vm_size              = var.vm_size

  os_profile {
    computer_name  = var.vm_name
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_windows_config {
    provision_vm_agent = true
  }

  storage_os_disk {
    name              = "${var.vm_name}-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  tags = {
    environment = "test"
  }
}

# Custom script extension for Windows VMs
resource "azurerm_virtual_machine_extension" "custom_script_extension" {
  count                = var.os_type == "Windows" ? 1 : 0
  name                 = "${var.vm_name}-custom-script-extension"
  virtual_machine_id   = azurerm_virtual_machine.windows_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
{
  "fileUris": ["${var.script_url}"],
  "commandToExecute": "powershell -ExecutionPolicy Unrestricted -File C:\\\\Temp\\\\DeployNessusToVMs.ps1"
}
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
{
  "storageAccountName": "${var.storage_account_name}",
  "storageAccountKey": "${var.storage_account_key}"
}
PROTECTED_SETTINGS
}
