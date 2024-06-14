#!/bin/bash

# Connect to Azure
az login

# Define the resource group and VMs
resourceGroup="NessusVMsResourceGroup"
vmNames=("NessusVM1" "NessusVM2" "NessusVM3")

# Nessus Agent URL
nessusAgentUrl="https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents/downloads/23248/download?i_agree_to_tenable_license_agreement=true"
downloadPath="/tmp"

# Function to install Nessus Agent on Windows VM
install_nessus_agent_windows() {
    vmName=$1
    installScriptPath="${downloadPath}/InstallNessusAgent.ps1"

    # Create the InstallNessusAgent.ps1 script content
    cat <<EOT > "$installScriptPath"
Invoke-WebRequest -Uri '$nessusAgentUrl' -OutFile '$downloadPath\\NessusAgent.msi'
Start-Process msiexec.exe -ArgumentList '/i $downloadPath\\NessusAgent.msi /quiet' -Wait
EOT

    # Use Custom Script Extension to execute the script
    az vm extension set \
        --resource-group "$resourceGroup" \
        --vm-name "$vmName" \
        --name CustomScriptExtension \
        --publisher Microsoft.Compute \
        --version 1.10 \
        --settings "{\"fileUris\": [\"$installScriptPath\"]}" \
        --protected-settings "{\"commandToExecute\": \"powershell -ExecutionPolicy Unrestricted -File C:\\\\Temp\\\\InstallNessusAgent.ps1\"}"
}

# Function to install Nessus Agent on Linux VM
install_nessus_agent_linux() {
    vmName=$1
    sshUser="Nessus"
    privateKeyPath="/Users/jeff/.ssh/id_rsa"

    # Get private IP address for the VM
    vmPrivateIP=$(az vm nic show --resource-group "$resourceGroup" --vm-name "$vmName" --nic "$vmName-nic" --query "ipConfigurations[0].privateIpAddress" -o tsv)

    # Commands to download and install Nessus Agent
    ssh -i "$privateKeyPath" "$sshUser@$vmPrivateIP" "wget -O /tmp/NessusAgent.sh $nessusAgentUrl && sudo bash /tmp/NessusAgent.sh"
}

# Loop through the VMs and install Nessus Agent
for vmName in "${vmNames[@]}"; do
    osType=$(az vm get-instance-view --resource-group "$resourceGroup" --name "$vmName" --query "storageProfile.osDisk.osType" -o tsv)

    if [ "$osType" == "Windows" ]; then
        install_nessus_agent_windows "$vmName"
    elif [ "$osType" == "Linux" ]; then
        install_nessus_agent_linux "$vmName"
    fi
done
