#!/bin/bash

# Check if jq and curl are installed
if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null
then
    echo "jq and curl must be installed. Please install them before running this script."
    exit 1
fi

# Variables
storageAccountName="azagentdeploy001"
storageContainerName="scripts"
allowed_vms_csv="AzureVirtualMachines.csv"
local_csv_path="/tmp/$allowed_vms_csv"
subscriptionId="your-subscription-id"  # Replace with your actual subscription ID

# Switch to the correct subscription
az account set --subscription "$subscriptionId"

# Get the storage account key
storageAccountKey=$(az storage account keys list --resource-group rg-inf-scripts-001 --account-name $storageAccountName --query "[0].value" --output tsv)

# Check if the storage account key was retrieved successfully
if [ -z "$storageAccountKey" ]; then
    echo "Failed to retrieve storage account key."
    exit 1
fi

# Export the environment variables for storage account
export AZURE_STORAGE_ACCOUNT=$storageAccountName
export AZURE_STORAGE_KEY=$storageAccountKey

# Generate SAS token for the storage account
sas_token=$(az storage account generate-sas \
    --account-name "$storageAccountName" \
    --permissions rl \
    --resource-types sco \
    --services b \
    --expiry $(date -u -d '1 day' +%Y-%m-%dT%H:%MZ) \
    --output tsv)

# Check if the SAS token was generated successfully
if [ -z "$sas_token" ]; then
    echo "Failed to generate SAS token for the storage account."
    exit 1
fi

# Download the allowed VMs CSV file from Azure Storage
csv_url="https://$storageAccountName.blob.core.windows.net/$storageContainerName/$allowed_vms_csv?$sas_token"
echo "Downloading CSV from URL: $csv_url"

curl -o $local_csv_path "$csv_url"

# Check if the CSV file was downloaded successfully
if [ ! -f "$local_csv_path" ]; then
    echo "Failed to download the CSV file from Azure Storage."
    exit 1
fi

# Function to read allowed VMs from the CSV file
read_allowed_vms() {
    allowed_vms=()
    while IFS=, read -r name type subscription resourceGroup location status operatingSystem size publicIpAddress disks
    do
        # Skip the header row
        if [[ "$name" != "NAME" ]]; then
            allowed_vms+=("$name")
        fi
    done < "$local_csv_path"
}

# Nessus Agent filenames
nessusAgentWindows="NessusAgent-10.6.4-x64.msi"
nessusAgentUbuntu="NessusAgent-10.6.4-ubuntu1404_amd64.deb"
nessusAgentRHEL="NessusAgent-10.6.4-el8.x86_64.rpm"

# Function to install Nessus Agent on Windows VM
install_nessus_agent_windows() {
    vmName=$1
    resourceGroup=$2

    # Create the InstallNessusAgent.ps1 script content
    installScriptContent=$(cat <<EOT
powershell -Command "Invoke-WebRequest -Uri 'https://$storageAccountName.blob.core.windows.net/$storageContainerName/$nessusAgentWindows?$sas_token' -OutFile 'C:\\Users\\nessus\\$nessusAgentWindows'; Start-Process msiexec.exe -ArgumentList '/i C:\\Users\\nessus\\$nessusAgentWindows /quiet /norestart' -Wait"
EOT
)

    # Escape JSON characters
    installScriptContent=$(echo "$installScriptContent" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # Use Custom Script Extension to execute the script
    az vm extension set \
        --resource-group "$resourceGroup" \
        --vm-name "$vmName" \
        --name CustomScriptExtension \
        --publisher Microsoft.Compute \
        --version 1.10 \
        --settings "{\"commandToExecute\": \"$installScriptContent\"}"
}

# Function to install Nessus Agent on Ubuntu VM
install_nessus_agent_ubuntu() {
    vmName=$1
    resourceGroup=$2

    # Create the install script content
    installScriptContent=$(cat <<EOT
#!/bin/bash
wget -O /tmp/$nessusAgentUbuntu "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$nessusAgentUbuntu?$sas_token"
sudo dpkg -i /tmp/$nessusAgentUbuntu
EOT
)

    # Escape JSON characters
    installScriptContent=$(echo "$installScriptContent" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # Use Custom Script Extension to execute the script
    az vm extension set \
        --resource-group "$resourceGroup" \
        --vm-name "$vmName" \
        --name CustomScript \
        --publisher Microsoft.Azure.Extensions \
        --version 2.0 \
        --settings "{\"commandToExecute\": \"$installScriptContent\"}"
}

# Function to install Nessus Agent on RHEL VM
install_nessus_agent_rhel() {
    vmName=$1
    resourceGroup=$2

    # Create the install script content
    installScriptContent=$(cat <<EOT
#!/bin/bash
sudo yum install -y wget
sudo yum install -y rpm
wget -O /tmp/$nessusAgentRHEL "https://$storageAccountName.blob.core.windows.net/$storageContainerName/$nessusAgentRHEL?$sas_token"
sudo rpm -ivh /tmp/$nessusAgentRHEL
EOT
)

    # Escape JSON characters
    installScriptContent=$(echo "$installScriptContent" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # Use Custom Script Extension to execute the script
    az vm extension set \
        --resource-group "$resourceGroup" \
        --vm-name "$vmName" \
        --name CustomScript \
        --publisher Microsoft.Azure.Extensions \
        --version 2.0 \
        --settings "{\"commandToExecute\": \"$installScriptContent\"}"
}

# Read the list of allowed VMs from the CSV file
read_allowed_vms

# Get list of all subscriptions
subscriptions=$(az account list --query "[?state=='Enabled'].id" -o tsv)

# Loop through each subscription
for subscription in $subscriptions; do
    az account set --subscription "$subscription"

    # Get list of all VMs in the subscription
    vms=$(az vm list --query "[].{name:name, resourceGroup:resourceGroup, osType:storageProfile.osDisk.osType}" -o json)

    # Loop through the VMs and install Nessus Agent
    for vm in $(echo "$vms" | jq -c '.[]'); do
        vmName=$(echo "$vm" | jq -r '.name')
        resourceGroup=$(echo "$vm" | jq -r '.resourceGroup')
        osType=$(echo "$vm" | jq -r '.osType')

        echo "Processing VM: $vmName, Resource Group: $resourceGroup, OS Type: $osType"

        # Check if VM is in the allowed list
        if [[ " ${allowed_vms[@]} " =~ " ${vmName} " ]]; then
            if [ "$osType" == "Windows" ]; then
                install_nessus_agent_windows "$vmName" "$resourceGroup"
            elif [ "$osType" == "Linux" ]; then
                # Check if Ubuntu or RHEL
                osInfo=$(az vm run-command invoke -g "$resourceGroup" -n "$vmName" \
                    --command-id RunShellScript \
                    --scripts "cat /etc/*release" \
                    --query "value[0].message" -o tsv | tr -d '\r')

                if [[ "$osInfo" == *"Ubuntu"* ]]; then
                    install_nessus_agent_ubuntu "$vmName" "$resourceGroup"
                elif [[ "$osInfo" == *"Red Hat"* ]] || [[ "$osInfo" == *"CentOS"* ]]; then
                    install_nessus_agent_rhel "$vmName" "$resourceGroup"
                else
                    echo "Unsupported or unknown Linux distribution for VM: $vmName"
                fi
            fi
        else
            echo "VM $vmName is not in the allowed list, skipping..."
        fi
    done
done