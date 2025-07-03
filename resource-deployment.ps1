# --- General Naming & Location ---
$RESOURCE_GROUP_NAME="myAksMySQLRG" # Name of the resource group
$LOCATION="westus2"                   # Azure region (e.g., westus2, eastus, westeurope)
# --- Private DNS Zone Details ---
$PRIVATE_DNS_ZONE_NAME="privatelink.mysql.database.azure.com"
# --- VNet & Subnet Details ---
$VNET_NAME="myAksMySQLVNet"
$VNET_CIDR="10.0.0.0/16"

$AKS_SUBNET_NAME="aks-subnet"
$AKS_SUBNET_CIDR="10.0.1.0/24" # Recommended /24 or larger for AKS nodes

$MYSQL_PE_SUBNET_NAME="mysql-pe-subnet" # Subnet for MySQL Private Endpoint
$MYSQL_PE_SUBNET_CIDR="10.0.2.0/24" # Private Endpoint subnet should be large enough

# --- Azure Database for MySQL - Flexible Server Details ---
$MYSQL_SERVER_NAME="myflexmysql-19-06-2025"
$MYSQL_ADMIN_USER="mysqladmin"
$MYSQL_ADMIN_PASSWORD="YourStrongPassword123!" # IMPORTANT: Replace with a strong password!
$MYSQL_DATABASE_NAME="wordpress_db"

# --- AKS Cluster Details ---
$AKS_CLUSTER_NAME="mysecureakscluster2025"
$AKS_NODE_COUNT=1 # Number of worker nodes
$AKS_VM_SIZE="standard_a2_v2" # VM size for worker nodes (adjust as needed)
$ACR_NAME="myregistry2025azurecr"



# Check if the resource group exists
$resourceGroup = az group exists --name $RESOURCE_GROUP_NAME | ConvertFrom-Json
if ($resourceGroup) {
    Write-Host "Resource group '$RESOURCE_GROUP_NAME' already exists."
} else {
    Write-Host "Resource group '$RESOURCE_GROUP_NAME' does not exist. Creating it..."
    az group create --name $RESOURCE_GROUP_NAME --location $LOCATION
}


Write-Host "Creating VNet $VNET_NAME with subnets..."

# Create the VNet
$vnetExists = az network vnet show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $VNET_NAME `
    --query "id" -o tsv 2>$null

if ($vnetExists) {
    Write-Host "Virtual network '$VNET_NAME' already exists."
} else {
    Write-Host "Virtual network '$VNET_NAME' does not exist. Creating it..."
    az network vnet create `
        --resource-group $RESOURCE_GROUP_NAME `
        --name $VNET_NAME `
        --address-prefixes $VNET_CIDR `
        --location $LOCATION
}


# Create AKS Subnet
$subnetExists = az network vnet subnet show `
    --resource-group $RESOURCE_GROUP_NAME `
    --vnet-name $VNET_NAME `
    --name $AKS_SUBNET_NAME `
    --query "id" -o tsv 2>$null

if ($subnetExists) {
    Write-Host "Subnet '$AKS_SUBNET_NAME' already exists."
} else {
    Write-Host "Subnet '$AKS_SUBNET_NAME' does not exist. Creating it..."
    az network vnet subnet create `
        --resource-group $RESOURCE_GROUP_NAME `
        --vnet-name $VNET_NAME `
        --name $AKS_SUBNET_NAME `
        --address-prefixes $AKS_SUBNET_CIDR
}


# Create MySQL Private Endpoint Subnet
# NOTE: The Private Endpoint subnet should NOT have a network security group (NSG) associated,
#       and should NOT have service endpoints enabled if you're using Private Endpoints.

$subnetExists = az network vnet subnet show `
    --resource-group $RESOURCE_GROUP_NAME `
    --vnet-name $VNET_NAME `
    --name $MYSQL_PE_SUBNET_NAME `
    --query "id" -o tsv 2>$null

if ($subnetExists) {
    Write-Host "Subnet '$AKS_SUBNET_NAME' already exists."
} else {
    Write-Host "Subnet '$MYSQL_PE_SUBNET_NAME' does not exist. Creating it..."
    az network vnet subnet create `
        --resource-group $RESOURCE_GROUP_NAME `
        --vnet-name $VNET_NAME `
        --name $MYSQL_PE_SUBNET_NAME `
        --address-prefixes $MYSQL_PE_SUBNET_CIDR `
        --disable-private-endpoint-network-policies true
}

# Get VNet ID
$VNET_ID=$(az network vnet show `
  --resource-group $RESOURCE_GROUP_NAME `
  --name $VNET_NAME `
  --query id -o tsv)

# Create the Private DNS Zone
$privateDnsZoneExists = az network private-dns zone show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $PRIVATE_DNS_ZONE_NAME `
    --query "id" -o tsv 2>$null

if ($privateDnsZoneExists) {
    Write-Host "Private DNS zone '$PRIVATE_DNS_ZONE_NAME' already exists."
} else {
    Write-Host "Private DNS zone '$PRIVATE_DNS_ZONE_NAME' does not exist. Creating it..."
    az network private-dns zone create `
        --resource-group $RESOURCE_GROUP_NAME `
        --name $PRIVATE_DNS_ZONE_NAME
}


# Link the Private DNS Zone to your Virtual Network
$privateDnsLinkExists = az network private-dns link vnet show `
    --resource-group $RESOURCE_GROUP_NAME `
    --zone-name $PRIVATE_DNS_ZONE_NAME `
    --name "${VNET_NAME}-link" `
    --query "id" -o tsv 2>$null

if ($privateDnsLinkExists) {
    Write-Host "Private DNS link '${VNET_NAME}-link' already exists."
} else {
    # Create the private DNS link if it does not exist
    Write-Host "Private DNS link '${VNET_NAME}-link' does not exist. Creating it..."
    az network private-dns link vnet create `
        --resource-group $RESOURCE_GROUP_NAME `
        --zone-name $PRIVATE_DNS_ZONE_NAME `
        --name "${VNET_NAME}-link" `
        --virtual-network $VNET_ID `
        --registration-enabled false
}

# Get the full resource ID of the Private Endpoint subnet
$MYSQL_PE_SUBNET_ID=$(az network vnet subnet show `
  --resource-group $RESOURCE_GROUP_NAME `
  --vnet-name $VNET_NAME `
  --name $MYSQL_PE_SUBNET_NAME `
  --query id -o tsv)

# Create the MySQL Flexible Server
$mysqlServerExists = az mysql flexible-server show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $MYSQL_SERVER_NAME `
    --query "id" -o tsv 2>$null

if ($mysqlServerExists) {
    Write-Host "MySQL server '$MYSQL_SERVER_NAME' already exists."
} else {
    # Create the MySQL server if it does not exist
    Write-Host "MySQL server '$MYSQL_SERVER_NAME' does not exist. Creating it..."
    az mysql flexible-server create `
        --resource-group $RESOURCE_GROUP_NAME `
        --name $MYSQL_SERVER_NAME `
        --location $LOCATION `
        --admin-user $MYSQL_ADMIN_USER `
        --admin-password $MYSQL_ADMIN_PASSWORD `
        --sku-name Standard_D2ds_v4 `
        --tier GeneralPurpose `
        --version 8.0.21 `
        --storage-size 32 `
        --backup-retention 7 `
        --geo-redundant-backup Disabled `
        --private-dns-zone "privatelink.mysql.database.azure.com" `
        --subnet $MYSQL_PE_SUBNET_ID
}

# disable SSL
az mysql flexible-server parameter set `
    --resource-group $RESOURCE_GROUP_NAME `
    --server-name $MYSQL_SERVER_NAME `
    --name require_secure_transport `
    --value OFF



Write-Output "Creating database $MYSQL_DATABASE_NAME on MySQL server..."
$mysqlDatabaseExists = az mysql flexible-server db show `
    --resource-group $RESOURCE_GROUP_NAME `
    --server-name $MYSQL_SERVER_NAME `
    --database-name $MYSQL_DATABASE_NAME `
    --query "id" -o tsv 2>$null

if ($mysqlDatabaseExists) {
    Write-Host "Database '$MYSQL_DATABASE_NAME' already exists."
} else {
    # Create the database if it does not exist
    Write-Host "Database '$MYSQL_DATABASE_NAME' does not exist. Creating it..."
    az mysql flexible-server db create `
        --resource-group $RESOURCE_GROUP_NAME `
        --server-name $MYSQL_SERVER_NAME `
        --database-name $MYSQL_DATABASE_NAME
}
# Get MySQL FQDN for later use in AKS app config
$MYSQL_FQDN=$(az mysql flexible-server show `
  --resource-group $RESOURCE_GROUP_NAME `
  --name $MYSQL_SERVER_NAME `
  --query fullyQualifiedDomainName -o tsv)

write-host "MySQL Server FQDN: $MYSQL_FQDN"
write-host "MySQL Admin User: ${MYSQL_ADMIN_USER}@${MYSQL_SERVER_NAME}" # Format for connection string

$AKS_SUBNET_ID=$(az network vnet subnet show `
  --resource-group $RESOURCE_GROUP_NAME `
  --vnet-name $VNET_NAME `
  --name $AKS_SUBNET_NAME `
  --query id -o tsv)
# Create AKS Cluster
$aksClusterExists = az aks show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $AKS_CLUSTER_NAME `
    --query "id" -o tsv 2>$null

if ($aksClusterExists) {
    Write-Host "AKS cluster '$AKS_CLUSTER_NAME' already exists."
} else {
    Write-Host "AKS cluster '$AKS_CLUSTER_NAME' does not exist. Creating it..."
    az aks create `
        --resource-group $RESOURCE_GROUP_NAME `
        --name $AKS_CLUSTER_NAME `
        --location $LOCATION `
        --node-count $AKS_NODE_COUNT `
        --node-vm-size $AKS_VM_SIZE `
        --network-plugin azure `
        --vnet-subnet-id $AKS_SUBNET_ID `
        --dns-service-ip 10.2.0.10 `
        --service-cidr 10.2.0.0/24 `
        --generate-ssh-keys `
        --enable-managed-identity
}


write-host "Creating Azure Container Registry $ACR_NAME..."

# Create the Azure Container Registry
$acrExists = az acr show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $ACR_NAME `
    --query "id" -o tsv 2>$null

if ($acrExists) {
    Write-Host "Azure Container Registry '$ACR_NAME' already exists."
} else {
    # Create the Azure Container Registry if it does not exist
    Write-Host "Azure Container Registry '$ACR_NAME' does not exist. Creating it..."
    az acr create `
        --resource-group $RESOURCE_GROUP_NAME `
        --name $ACR_NAME `
        --location $LOCATION `
        --sku Standard `
        --admin-enabled true
}

az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --overwrite-existing
docker build -t myregistry2025azurecr.azurecr.io/custom-wordpress:v1 .
az acr login --name $ACR_NAME 
docker push myregistry2025azurecr.azurecr.io/custom-wordpress:v1
kubectl create ns wordpress
kubectl create ns cert-manager


# Get the resource ID of the AKS cluster's managed identity
# This is the Managed Identity of the cluster itself, used for control plane operations.
# For node pull access, it uses the Kubelet identity or the cluster identity if node pools are configured to use it.
# The `az aks show` command gets the managed identity ID for the *cluster*.
# For typical AKS setups, assigning AcrPull to this identity is sufficient for node pools to pull.
# If you're using a user-assigned identity for node pools, you'd target that identity's principal ID.
$AKS_MI_ID = $(az aks show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $AKS_CLUSTER_NAME `
    --query identity.principalId -o tsv)

# Get the resource ID of the ACR
$ACR_ID = $(az acr show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $ACR_NAME `
    --query id -o tsv)

# Assign the AcrPull role to the AKS cluster's managed identity on the ACR
az role assignment create `
    --assignee $AKS_MI_ID `
    --role "AcrPull" `
    --scope $ACR_ID

Write-Host "AcrPull role assigned to AKS cluster ($AKS_CLUSTER_NAME) for ACR ($ACR_NAME)."
az aks update --resource-group $RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --attach-acr $ACR_NAME
kubectl create ns wordpress

$MYSQL_FQDN = $(az mysql flexible-server show `
    --resource-group $RESOURCE_GROUP_NAME `
    --name $MYSQL_SERVER_NAME `
    --query fullyQualifiedDomainName -o tsv)

Write-Host "WORDPRESS_DB_HOST (MySQL FQDN): $MYSQL_FQDN"
