# Connect to Azure
Connect-AzAccount

# Define the resource group and VMs
$resourceGroup = "NessusVMsResourceGroup"
$vmNames = @("NessusVM1", "NessusVM2", "NessusVM3")

# Nessus Agent URL
$nessusAgentUrl = "https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents/downloads/23248/download?i_agree_to_tenable_license_agreement=true"
$downloadPath = "C:\Temp"

# Create the InstallNessusAgent.ps1 script content
$installScriptContent = @"
Invoke-WebRequest -Uri '$nessusAgentUrl' -OutFile '$downloadPath\NessusAgent.msi'
Start-Process msiexec.exe -ArgumentList '/i $downloadPath\NessusAgent.msi /quiet' -Wait
"@

# Save the InstallNessusAgent.ps1 script to the download path
$installScriptPath = "$downloadPath\InstallNessusAgent.ps1"
$installScriptContent | Set-Content -Path $installScriptPath

# Loop through the VMs and install Nessus Agent
foreach ($vmName in $vmNames) {
    $vm = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName

    if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {
        # Use Custom Script Extension to execute the script
        $extensionName = "CustomScriptExtension"
        $publisher = "Microsoft.Compute"
        $version = "1.10"
        $publicConfig = @{
            "fileUris" = @($installScriptPath)
        }
        $privateConfig = @{
            "commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File C:\\Temp\\InstallNessusAgent.ps1"
        }

        Set-AzVMExtension -ResourceGroupName $resourceGroup -VMName $vmName -Name $extensionName -Publisher $publisher -ExtensionType $extensionName -TypeHandlerVersion $version -Settings $publicConfig -ProtectedSettings $privateConfig -Location $vm.Location
    }
}

# For Linux VMs
$sshUser = "Nessus"
$privateKeyPath = "/Users/jeff/.ssh/id_rsa"

# Loop through the VMs and install Nessus Agent
foreach ($vmName in $vmNames) {
    $vm = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName

    if ($vm.StorageProfile.OsDisk.OsType -eq "Linux") {
        # Get private IP address for the VM
        $vmPrivateIP = (Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name $vm.NetworkProfile.NetworkInterfaces[0].Id.Split('/')[-1]).IpConfigurations[0].PrivateIpAddress

        # Commands to download and install Nessus Agent
        $commands = @(
            "wget -O /tmp/NessusAgent.sh $nessusAgentUrl",
            "sudo bash /tmp/NessusAgent.sh"
        )

        foreach ($command in $commands) {
            # Execute the command on the Linux VM using SSH
            ssh -i $privateKeyPath $sshUser@$vmPrivateIP $command
        }
    }
}
