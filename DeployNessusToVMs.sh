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
subscriptionId="e873319e-be73-4ac2-a683-b2c291fc4767"  # Replace with your actual subscription ID
objectId="7b4fe24b-154c-4ab2-875f-edcc2ed70bf3"  # Replace with your actual object ID

# Switch to the correct subscription
echo "Switching to subscription: $subscriptionId"
az account set --subscription "$subscriptionId"

# Verify Role Assignments
echo "Verifying role assignments for the user..."
vm_contributor_role=$(az role assignment list --assignee $objectId --role "Virtual Machine Contributor" --scope /subscriptions/$subscriptionId --query "[].roleDefinitionName" --output tsv)
storage_blob_data_contributor_role=$(az role assignment list --assignee $objectId --role "Storage Blob Data Contributor" --scope /subscriptions/$subscriptionId/resourceGroups/rg-inf-scripts-001/providers/Microsoft.Storage/storageAccounts/$storageAccountName --query "[].roleDefinitionName" --output tsv)

echo "VM Contributor Role: $vm_contributor_role"
echo "Storage Blob Data Contributor Role: $storage_blob_data_contributor_role"

if [[ "$vm_contributor_role" != "Virtual Machine Contributor" ]] || [[ "$storage_blob_data_contributor_role" != "Storage Blob Data Contributor" ]]; then
    echo "Required roles are not assigned. Please ensure the user has 'Virtual Machine Contributor' and 'Storage Blob Data Contributor' roles."
    exit 1
fi
echo "Role assignments verified."

# Get the storage account key
echo "Retrieving storage account key for: $storageAccountName"
storageAccountKey=$(az storage account keys list --resource-group rg-inf-scripts-001 --account-name $storageAccountName --query "[0].value" --output tsv)

# Check if the storage account key was retrieved successfully
if [ -z "$storageAccountKey" ]; then
    echo "Failed to retrieve storage account key."
    exit 1
fi
echo "Storage account key retrieved successfully."

# Export the environment variables for storage account
export AZURE_STORAGE_ACCOUNT=$storageAccountName
export AZURE_STORAGE_KEY=$storageAccountKey

# Generate SAS token for the storage account
echo "Generating SAS token for storage account."
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
echo "SAS token generated successfully."

# Adjust the blob service endpoint for Azure Government Cloud
blob_service_endpoint="https://$storageAccountName.blob.core.usgovcloudapi.net"

# Download the allowed VMs CSV file from Azure Storage
csv_url="$blob_service_endpoint/$storageContainerName/$allowed_vms_csv?$sas_token"
echo "Downloading CSV from URL: $csv_url"

curl -o $local_csv_path "$csv_url"

# Check if the CSV file was downloaded successfully
if [ ! -f "$local_csv_path" ]; then
    echo "Failed to download the CSV file from Azure Storage."
    exit 1
fi
echo "CSV file downloaded successfully."

# Function to read allowed VMs from the CSV file
read_allowed_vms() {
    allowed_vms=()
    while IFS=, read -r name type subscription resourceGroup location status operatingSystem size publicIpAddress disks
    do
        # Skip the header row and strip any whitespace
        if [[ "$name" != "NAME" ]]; then
            allowed_vms+=("$(echo "$name" | xargs)")
        fi
    done < "$local_csv_path"
}

# Read the list of allowed VMs from the CSV file
read_allowed_vms

# Function to check if a VM is in the allowed list (case insensitive)
is_vm_allowed() {
    local vm_name=$1
    for allowed_vm in "${allowed_vms[@]}"; do
        echo "Comparing '$vm_name' with '$allowed_vm'"  # Debug statement
        if [[ "${vm_name,,}" == "${allowed_vm,,}" ]]; then
            return 0
        fi
    done
    return 1
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
powershell -Command "Invoke-WebRequest -Uri '$blob_service_endpoint/$storageContainerName/$nessusAgentWindows?$sas_token' -OutFile 'C:\\Users\\nessus\\$nessusAgentWindows'; Start-Process msiexec.exe -ArgumentList '/i C:\\Users\\nessus\\$nessusAgentWindows /quiet /norestart' -Wait"
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
wget -O /tmp/$nessusAgentUbuntu "$blob_service_endpoint/$storageContainerName/$nessusAgentUbuntu?$sas_token"
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
wget -O /tmp/$nessusAgentRHEL "$blob_service_endpoint/$storageContainerName/$nessusAgentRHEL?$sas_token"
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

# Get list of all subscriptions
subscriptions=$(az account list --query "[?state=='Enabled'].id" -o tsv)

# Loop through each subscription
for subscription in $subscriptions; do
    az account set --subscription "$subscription"

    # Get list of all VMs in the subscription
    vms=$(az vm list --query "[].{name:name, resourceGroup:resourceGroup, osType:storageProfile.osDisk.osType}" -o json)

    # Loop through the VMs and install Nessus Agent
    for vm in $(echo "$vms" | jq -c '.[]'); do
        vmName=$(echo "$vm" | jq -r '.name' | xargs)
        resourceGroup=$(echo "$vm" | jq -r '.resourceGroup' | xargs)
        osType=$(echo "$vm" | jq -r '.osType' | xargs)

        echo "Processing VM: $vmName, Resource Group: $resource
    # Check if VM is in the allowed list
    if is_vm_allowed "$vmName"; then
        echo "VM $vmName is allowed, processing..."
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