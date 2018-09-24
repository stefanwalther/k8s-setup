#!/usr/bin/env bash

set -euo pipefail
#IFS=$'\n\t'

source ./shared/shared.sh

env_file=
cluster_name=
resource_group_name=
location=
storage=
node_count=2
kubernetes_version="1.9.1"
node_vm_size="Standard_DS2_v2"

function _get_args {
  while getopts ":e:" opt; do
    case $opt in
      e) env_file="$OPTARG"
      ;;
      \?) echo "Invalid option -$OPTARG" >&2
      ;;
    esac
  done
}

function _init {

  echo "$SEP"
  _get_args $*

  if [ ! -z "$env_file" ]
  then
    if [ ! -f ${env_file} ]; then
      echo -e "${red}File does not exist: ${env_file}${nocolor}\n"
      exit 1
    else
      load_env_from_file ${env_file}
    fi
  else
    echo "> No environment-variable file set, so use the ones being available ..."
  fi

  # Required variables, set bei either env-vars or the .env file.
  # All other settings are defined by default values.
  vars=(
    CLUSTER_NAME
    RESOURCE_GROUP_NAME
    LOCATION
  )

  validate_required_env_vars "${vars[@]}"

  # Initialize local vars
  cluster_name=${CLUSTER_NAME}
  resource_group_name=${RESOURCE_GROUP_NAME}
  location=${LOCATION:-$location}
  storage=${STORAGE:-$storage}
  node_count=${NODE_COUNT:-$node_count}
  kubernetes_version=${KUBERNETES_VERSION:-$kubernetes_version}
  node_vm_size=${NODE_VM_SIZE:=$node_vm_size}

}

function _debug_values {
  echo "$SEP"
  echo -e "${green}> Using the following values:${nocolor}\n"

  echo -e "     - cluster_name: $cluster_name"
  echo -e "     - resource_group_name: $resource_group_name"
  echo -e "     - location: $location"
  echo -e "     - node_count: $node_count"
  echo -e "     - kubernetes_version: $kubernetes_version"
  echo -e "     - node_vm_size: $node_vm_size"
  echo -e ""
}


function _az_ensure_aks_services {

  echo "$SEP"
  echo -e "${green}> az: Check required AKS services ...${nocolor}\n"

  skip=0
  containerServiceRegState=$(az provider show -n Microsoft.ContainerService | jq -r .registrationState )
  computeRegState=$(az provider show -n Microsoft.Compute |  jq -r .registrationState )

  if [ "$containerServiceRegState" != "Registered" ]; then
    skip=1
    echo -e "     ${red}[Error]\tContainer service is not registered (State: ${containerServiceRegState})${nocolor}"
    echo -e "            \tRun <az provider register -n Microsoft.ContainerService> to register the Container service."
  else
    echo -e "     [OK] Container service is registered"
  fi

  if [ "$computeRegState" != "Registered" ]; then
    skip=1
    echo -e "     ${red}[Error]\tCompute service is not registered (State: ${computeRegState})${nocolor}"
    echo -e "            \tRun <az provider register -n Microsoft.Compute> to register the Compute service."
  else
    echo -e "     [OK] Compute service is registered"
  fi

  if [ "$skip" == "1" ]; then
    echo -e ""
    echo -e "${red}We cannot proceed, the above mentioned services are not in state <Registered> as required.${nocolor}\n"
    exit 1
  fi
  echo -e " "

}

## Create the resource group
## Obviously no need to delete and re-create, just works if we create if, even if already exists ...
function _az_rg_create {
  echo "$SEP"
  echo -e "${green}> az: Create az resource group ...${nocolor}\n"
  az group create --name $resource_group_name --location $location
}

## Create the cluster
##  => no need to delete if already existing, if existing, the existing one will be updated.
function _az_cluster_create {
  echo "$SEP"
  echo -e "${green}> az: Create az cluster ...${nocolor}\n"

  az aks create \
    --resource-group $resource_group_name \
    --no-wait \
    --name $cluster_name \
    --node-count $node_count \
    --generate-ssh-keys \
    --kubernetes-version $kubernetes_version \
    --node-vm-size $node_vm_size

}

function _az_cluster_wait_created {
  echo "$SEP"
  echo -e "${green}> az: Waiting for the k8s cluster to be created ...${nocolor}\n"
  echo "Note, this typically takes about 10-15 mins or so ..."
  echo ""
  echo "Status: "

  az aks wait \
    --name $cluster_name \
    --resource-group $resource_group_name \
    --created \
    --interval 1

  echo -e "> The cluster has been created successfully!"
}

function _az_fetch_credentials {
  az aks get-credentials \
    --name $cluster_name \
    --resource-group $resource_group_name
}

function _az_storage_add {
  echo "$SEP"
  echo -e "${green}> az: Add storage account ...${nocolor}\n"
  g="MC_""$resource_group_name""_""$cluster_name""_""$location"

  az storage account create \
    -g $g \
    -n $storage \
    --sku Standard_LRS
}

## *******************************************************************************
## Delete methods
## *******************************************************************************

function _az_cl_delete {
  echo "$SEP"
  echo "> az: Delete the k8s cluster ..."
  az aks delete --no-wait --yes --resource-group $resource_group_name --name $cluster_name
}

function _az_cl_wait_deleted {
  echo "$SEP"
  echo "> Waiting for the k8s cluster to be deleted ..."
  echo "    Note, this typically takes about 10-15 mins or so ..."
  echo "Status: "
  az aks wait --name $cluster_name --resource-group $resource_group_name --deleted --interval 1
}


## *******************************************************************************
## External interfaces
## *******************************************************************************

function help {
  echo -e "Help ... to be added here ... sorry ;-)"
}

function up {

  _init $*
  _debug_values
  _az_ensure_aks_services
  _az_rg_create
  _az_cluster_create
  _az_cluster_wait_created

  _az_fetch_credentials
  _az_storage_add
}

# See here: https://stackify.com/azure-container-service-kubernetes/
function down {
  _init $*
  _az_cl_delete
  _az_cl_wait_deleted

  # Todo: We might have to delete other left-overs, such as:
  # - storage account (?)
  # - resource group

  # Todo: down_confirmation
}

function create_env {
cat > azure-aks.env << EOF
CLUSTER_NAME="<name-of-your-cluster>"
RESOURCE_GROUP_NAME="<name-of-the-resource-group>"
LOCATION="<azure-location>"
STORAGE="<azure-storage>"
EOF
}


## *******************************************************************************
## External interface to the script to run `./<name>.sh exec <function>`
## *******************************************************************************
exec() {
  echo "Executing <$1> ..."
  $1
}

# Allows to call a function based on arguments passed to the script
if [ -z "$1" ]; then
  help
else
  $*
fi
