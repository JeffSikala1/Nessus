#!/bin/bash

# Variables
link_key="7c6550695733027a0d9278094ea0eb0ce63de5ba34ab7ac94d00ee48bca872ae"
nessus_groups="All"

# Function to link Nessus Agent on Windows VM
link_nessus_agent_windows() {
    vmName=$1
    resourceGroup=$2
    nessus_server=$3

    # Create the LinkNessusAgent.ps1 script content
    linkScriptContent=$(cat <<EOT
msiexec /i "C:\\Users\\nessus\\NessusAgent-10.6.4-x64.msi" NESSUS_GROUPS="$nessus_groups" NESSUS_SERVER="$nessus_server" NESSUS_KEY=$link_key /qn
EOT
)

    # Escape JSON characters
    linkScriptContent=$(echo "$linkScriptContent" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # Use Custom Script Extension to execute the script
    az vm extension set \
        --resource-group "$resourceGroup" \
        --vm-name "$vmName" \
        --name CustomScriptExtension \
        --publisher Microsoft.Compute \
        --version 1.10 \
        --settings "{\"commandToExecute\": \"$linkScriptContent\"}"
}

# Function to link Nessus Agent on Linux VM
link_nessus_agent_linux() {
    vmName=$1
    resourceGroup=$2
    nessus_server=$3

    # Create the link script content
    linkScriptContent=$(cat <<EOT
#!/bin/bash
/opt/nessus_agent/sbin/nessuscli agent link --key=$link_key --name=$vmName --groups="$nessus_groups" --host=$nessus_server
/sbin/service nessusagent start
systemctl enable nessusagent
EOT
)

    # Escape JSON characters
    linkScriptContent=$(echo "$linkScriptContent" | sed 's/\\/\\\\/g' | sed 's/"/\\\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # Use Custom Script Extension to execute the script
    az vm extension set \
        --resource-group "$resourceGroup" \
        --vm-name "$vmName" \
        --name CustomScript \
        --publisher Microsoft.Azure.Extensions \
        --version 2.0 \
        --settings "{\"commandToExecute\": \"$linkScriptContent\"}"
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    local resource_group=$2
    vm_status=$(az vm get-instance-view --name "$vm_name" --resource-group "$resource_group" --query "instanceView.statuses[?code=='PowerState/running'] | [0]" -o tsv)
    if [[ -n "$vm_status" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get the private IP address of a VM
get_private_ip() {
    local vm_name=$1
    local resource_group=$2
    local subscription=$3
    az vm show -d -g "$resource_group" --subscription "$subscription" -n "$vm_name" --query privateIps -o tsv
}

# Get list of all subscriptions
subscriptions=$(az account list --query "[?state=='Enabled'].id" -o tsv)

# Loop through each subscription
for subscription in $subscriptions; do
    az account set --subscription "$subscription"

    # Get list of all VMs in the subscription
    vms=$(az vm list --query "[].{name:name, resourceGroup:resourceGroup, osType:storageProfile.osDisk.osType}" -o json)

    # Loop through the VMs and link Nessus Agent
    for vm in $(echo "$vms" | jq -c '.[]'); do
        vmName=$(echo "$vm" | jq -r '.name' | xargs)
        resourceGroup=$(echo "$vm" | jq -r '.resourceGroup' | xargs)
        osType=$(echo "$vm" | jq -r '.osType' | xargs)

        echo "Processing VM: $vmName, Resource Group: $resourceGroup, OS Type: $osType"

        if is_vm_running "$vmName" "$resourceGroup"; then
            nessus_server=$(get_private_ip "$vmName" "$resourceGroup" "$subscription")
            if [ "$osType" == "Windows" ]; then
                link_nessus_agent_windows "$vmName" "$resourceGroup" "$nessus_server"
            elif [ "$osType" == "Linux" ]; then
                link_nessus_agent_linux "$vmName" "$resourceGroup" "$nessus_server"
            else
                echo "Unsupported OS type for VM: $vmName"
            fi
        else
            echo "VM $vmName is not running. Skipping linking."
        fi
    done
done
