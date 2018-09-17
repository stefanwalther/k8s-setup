#!/usr/bin/env bash

source ./shared/shared.sh

s3_bucket_name=
s3_bucket_region=
kops_cluster_name=
kops_state_store=
env_file=

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

function _check_aws_credentials {
  aws sts get-caller-identity
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


  vars=(
        S3_BUCKET_NAME
        S3_BUCKET_REGION
        KOPS_CLUSTER_NAME
        NODE_COUNT
        NODE_SIZE
      )

  validate_required_env_vars "${vars[@]}"

  ## Initialize local vars
  s3_bucket_name=${S3_BUCKET_NAME}
  s3_bucket_region=${S3_BUCKET_REGION}
  kops_cluster_name=${KOPS_CLUSTER_NAME}
  kops_state_store=s3://${s3_bucket_name}
  node_count=${NODE_COUNT}
  node_size="${NODE_SIZE}"
}

function up {

  _init $*

  echo "$SEP"
  echo -e "${green}> Ensure that we have an S3 bucket ...${nocolor}"
  _create_bucket
  _ensure_bucket_versioning

  echo "$SEP"
  echo -e "${green}> Create a cluster definition ...${nocolor}"
  echo -e "${light_gray}"
  _create_cluster_definition
  echo -e "${nocolor}"

  echo "$SEP"
  echo -e "${green}> Create the cluster ...${nocolor}"
  echo -e "${light_gray}"
  _create
  echo -e "${nocolor}"

  echo "$SEP"
  echo -e "${green}> Wait for the cluster to be ready ...${nocolor}"
  echo -e "${light_gray}"
  _wait_cluster_ready
  echo -e "${nocolor}"
  exit 0

  echo "$SEP"
  echo -e "${green}> Deploy the k8s dashboard ...${nocolor}"
  echo -e "${light_gray}"
  _deploy_k8s_dashboard
  _echo_access_dashboard
  echo -e "${nocolor}"

}

function _create_bucket {

  if [ "$s3_bucket_region" == "us-east-1" ]; then
    aws s3api create-bucket \
    --bucket ${s3_bucket_name} \
    --region ${s3_bucket_region} \
    &> /dev/null
  else
    aws s3api create-bucket \
      --bucket ${s3_bucket_name} \
      --region ${s3_bucket_region} \
      --create-bucket-configuration LocationConstraint=${s3_bucket_region} \
      &> /dev/null
  fi
}

function create_env {
cat > aws-kops.env << EOF
S3_BUCKET_NAME="<your-s3-bucket-name>"
S3_BUCKET_REGION="<your-s3-bucket-region>"
KOPS_CLUSTER_NAME="foo.k8s.local"
NODE_COUNT=3
NODE_SIZE="t2.medium"
EOF
}

function _delete_bucket {
  aws s3api delete-bucket \
    --bucket ${s3_bucket_name}
}

function _delete_bucket_versioning {
  aws s3api delete-objects \
    --bucket ${s3_bucket_name} \
    --delete "$(aws s3api list-object-versions --bucket ${s3_bucket_name} | jq '{Objects: [.Versions[] | {Key:.Key, VersionId : .VersionId}], Quiet: false}')"
}

function _ensure_bucket_versioning {
  aws s3api put-bucket-versioning \
    --bucket ${s3_bucket_name} \
    --versioning-configuration Status=Enabled
}

function _create_cluster_definition {
  kops create cluster \
    --node-count=${node_count} \
    --node-size=${node_size} \
    --zones=$(aws ec2 describe-availability-zones --zone-names --query 'AvailabilityZones[0]'.ZoneName) \
    --name=${kops_cluster_name} \
    --state=${kops_state_store}
}

function _review_cluster {
  kops edit cluster --name ${kops_cluster_name}
}

function _create {
  kops update cluster \
    --name ${kops_cluster_name} \
    --state ${kops_state_store} \
    --yes
}

function _edit {
  kops edit cluster \
    --name ${kops_cluster_name}
}

function destroy {

  _init $*

  echo "$SEP"
  echo -e "${green}> Deleting the cluster ...${nocolor}"
  echo -e "${light_gray}"
  kops delete cluster \
    --name=${kops_cluster_name} \
    --state=${kops_state_store} \
    --yes
  end
  echo -e "${nocolor}"
}

function _get_cluster {
  kops get cluster
}

function _validate {
  kops validate cluster \
    --name ${kops_cluster_name}
}

function _get_nodes {
  kubectl get nodes #--show-labels
}

function _get_system_components {
  kubectl -n kube-system get po
}

function init_helm {
  kubectl create serviceaccount \
    --namespace kube-system tiller
  kubectl create clusterrolebinding tiller-cluster-rule \
    --clusterrole=cluster-admin \
    --serviceaccount=kube-system:tiller
  helm init
  kubectl patch deploy \
    --namespace kube-system tiller-deploy \
    -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
}

function _deploy_k8s_dashboard {
  kubectl apply \
    -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
}

function _get_admin_pwd {
  kops get secrets kube \
    --type secret -oplaintext
}

function _echo_admin_pwd {
  echo "Admin password: $(_get_admin_pwd)"
}

function _get_k8s_master {
  api_server=$(kubectl config view --minify | grep server | cut -f 2- -d ":" | tr -d " ")
  echo "${api_server}"
}

function _get_admin_service_token {
  kops get secrets admin --type secret -oplaintext
}

function _echo_admin_service_token {
  echo "Admin service token: $(_get_admin_service_token)"
}

function _get_cluster_info {
  kubectl cluster-info
}

function _echo_access_dashboard {

  echo "The k8s master is available at: $(_get_k8s_master)"
  echo ""
  echo "Access the k8s dashboard at: $(_get_k8s_master)/ui"
  echo ""
  echo "Use the following information to get access to the dashboard"
  echo -e "\tUser: admin"
  echo -e "\tPassword: $(_get_admin_pwd)"
  echo ""
  echo "Then use the following token:"
  echo -e "\t$(_echo_admin_service_token)"
  echo ""

}

function _wait_cluster_ready {
  max_wait=900

  echo ""
  echo "> Trying to validate the created cluster ... wait a bit ..."
  echo ""
  while [[ $max_wait -gt 0 ]]; do
    kops validate cluster --name=${kops_cluster_name} --state=${kops_state_store} 2> /dev/null && break || echo "Waiting ..." && sleep 10
    max_wait=$((max_wait - 10))
    echo "Waited 10 seconds. Still waiting max. $(show_time ${max_wait}).";
    echo "---"
  done

  if [[ $max_wait -le 0 ]]; then
    echo -e "${red}> Timeout: cluster does not validate after 15 minutes!${nocolor}";
    exit 1;
  fi
}

function help {
  echo -e "./aws-kops.sh help:"
  echo -e ""
  echo -e "Commands:"
  echo -e "\t ./aws-kops.sh up - Create a new k8s cluster."
  echo -e "\t ./aws-kops.sh destroy - Destroy the given k8s cluster."
  echo -e "\t ./aws-kops.sh create_env - Create a file to set the environment variables."
  echo -e ""
  echo -e "Further instructions: https://github.com/stefanwalther/k8s-setup"
  echo -e ""
}

function down {
  destroy
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
