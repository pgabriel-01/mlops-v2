#!/usr/bin/env bash

# Fail fast on errors, undefined vars, or any failing command in a pipeline.
# Without this the script silently continues past missing files and produces
# an empty target repository while the pipeline reports success.
set -euo pipefail

repo_name=$1
project_type=$2
mlops_version=$3
template_repo=$4
#infrastructure_version=bicep #options: terraform / bicep
infrastructure_version=$5 #options: terraform / bicep
network_mode=${6:-public}
deployment_environment=${7:-dev}
variable_group_name=${8:-AUTO}
mlops_templates_ref=${9:-refs/heads/main}
platform_service_connection=${10:-AUTO}
workload_service_connection=${11:-AUTO}
managed_devops_pool_name=${12:-AUTO}
managed_devops_pool_alias=${13:-AUTO}
managed_devops_pool_resource_group=${14:-AUTO}
managed_devops_pool_location=${15:-REPLACE_WITH_AZURE_REGION}
managed_devops_pool_vm_sku=${16:-Standard_D2ads_v5}
managed_devops_pool_image=${17:-ubuntu-24.04}
managed_devops_pool_maximum_concurrency=${18:-2}
platform_virtual_network_name=${19:-AUTO}
platform_vnet_address_prefix=${20:-10.20.0.0/16}
managed_devops_pool_subnet_address_prefix=${21:-10.20.1.0/24}
private_endpoint_subnet_address_prefix=${22:-10.20.2.0/24}
terraform_state_storage_account_name=${23:-REPLACE_WITH_GLOBALLY_UNIQUE_STORAGE_NAME}
terraform_state_container_name=${24:-default}
dev_center_project_resource_id=${25:-REPLACE_WITH_DEV_CENTER_PROJECT_RESOURCE_ID}

echo "=== initialise_repo.sh ==="
echo "repo_name=${repo_name}"
echo "project_type=${project_type}"
echo "mlops_version=${mlops_version}"
echo "template_repo=${template_repo}"
echo "infrastructure_version=${infrastructure_version}"
echo "network_mode=${network_mode}"
echo "deployment_environment=${deployment_environment}"
echo "cwd=$(pwd)"
ls -la

case "${network_mode}" in
  public|private) ;;
  *)
    echo "ERROR: network_mode must be 'public' or 'private', got '${network_mode}'." >&2
    exit 1
    ;;
esac

case "${deployment_environment}" in
  dev|test|prod) ;;
  *)
    echo "ERROR: deployment_environment must be 'dev', 'test', or 'prod', got '${deployment_environment}'." >&2
    exit 1
    ;;
esac

case "${deployment_environment}" in
  dev) environment_title=Dev ;;
  test) environment_title=Test ;;
  prod) environment_title=Prod ;;
esac
[[ "${variable_group_name}" == "AUTO" ]] && variable_group_name="mlops-${deployment_environment}"
[[ "${platform_service_connection}" == "AUTO" ]] && platform_service_connection="Azure-ARM-${environment_title}-Platform"
[[ "${workload_service_connection}" == "AUTO" ]] && workload_service_connection="Azure-ARM-${environment_title}"
[[ "${managed_devops_pool_name}" == "AUTO" ]] && managed_devops_pool_name="mlops-${deployment_environment}-private"
[[ "${managed_devops_pool_alias}" == "AUTO" ]] && managed_devops_pool_alias="${managed_devops_pool_name}"
[[ "${managed_devops_pool_resource_group}" == "AUTO" ]] && managed_devops_pool_resource_group="rg-mlops-${deployment_environment}-mdp"
[[ "${platform_virtual_network_name}" == "AUTO" ]] && platform_virtual_network_name="vnet-mlops-${deployment_environment}-platform"

if [[ "${network_mode}" == "private" && "${infrastructure_version}" != "terraform" ]]; then
  echo "ERROR: private network mode currently requires infrastructure_version=terraform." >&2
  exit 1
fi

if [[ "${network_mode}" == "private" ]]; then
  for required_value in \
    "${variable_group_name}" \
    "${mlops_templates_ref}" \
    "${platform_service_connection}" \
    "${workload_service_connection}" \
    "${managed_devops_pool_name}" \
    "${managed_devops_pool_alias}" \
    "${managed_devops_pool_resource_group}" \
    "${managed_devops_pool_location}" \
    "${managed_devops_pool_vm_sku}" \
    "${managed_devops_pool_image}" \
    "${managed_devops_pool_maximum_concurrency}" \
    "${platform_virtual_network_name}" \
    "${platform_vnet_address_prefix}" \
    "${managed_devops_pool_subnet_address_prefix}" \
    "${private_endpoint_subnet_address_prefix}" \
    "${terraform_state_storage_account_name}" \
    "${terraform_state_container_name}" \
    "${dev_center_project_resource_id}"
  do
    if [[ -z "${required_value}" ]]; then
      echo "ERROR: private network mode requires all platform, workload, and Managed DevOps Pool settings." >&2
      exit 1
    fi
  done
fi

for ado_name in \
  "${variable_group_name}" \
  "${platform_service_connection}" \
  "${workload_service_connection}" \
  "${managed_devops_pool_alias}"
do
  if [[ ! "${ado_name}" =~ ^[A-Za-z0-9._-]+([ ][A-Za-z0-9._-]+)*$ ]]; then
    echo "ERROR: Azure DevOps names may contain only letters, numbers, spaces, periods, underscores, and hyphens: '${ado_name}'." >&2
    exit 1
  fi
done

for azure_name in \
  "${managed_devops_pool_name}" \
  "${managed_devops_pool_resource_group}" \
  "${managed_devops_pool_location}" \
  "${managed_devops_pool_vm_sku}" \
  "${managed_devops_pool_image}" \
  "${platform_virtual_network_name}" \
  "${terraform_state_storage_account_name}" \
  "${terraform_state_container_name}"
do
  if [[ ! "${azure_name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: Azure resource settings may contain only letters, numbers, periods, underscores, and hyphens: '${azure_name}'." >&2
    exit 1
  fi
done

if [[ ! "${managed_devops_pool_maximum_concurrency}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: managed_devops_pool_maximum_concurrency must be a positive integer." >&2
  exit 1
fi

for cidr in \
  "${platform_vnet_address_prefix}" \
  "${managed_devops_pool_subnet_address_prefix}" \
  "${private_endpoint_subnet_address_prefix}"
do
  if [[ ! "${cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "ERROR: invalid CIDR value '${cidr}'." >&2
    exit 1
  fi
done

if [[ "${network_mode}" == "private" && "${dev_center_project_resource_id}" == REPLACE_WITH_* ]]; then
  echo "ERROR: private network mode requires devCenterProjectResourceId." >&2
  exit 1
fi

if [[ "${network_mode}" == "private" && "${managed_devops_pool_location}" == REPLACE_WITH_* ]]; then
  echo "ERROR: private network mode requires managedDevOpsPoolLocation." >&2
  exit 1
fi

if [[ "${network_mode}" == "private" && "${terraform_state_storage_account_name}" == REPLACE_WITH_* ]]; then
  echo "ERROR: private network mode requires terraformStateStorageAccountName." >&2
  exit 1
fi

if [[ "${network_mode}" == "private" && ! "${dev_center_project_resource_id}" =~ ^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.DevCenter/projects/[^/]+$ ]]; then
  echo "ERROR: devCenterProjectResourceId is not a Dev Center project resource ID." >&2
  exit 1
fi

if [[ ! "${mlops_templates_ref}" =~ ^refs/(heads|tags)/[A-Za-z0-9._/-]+$ && ! "${mlops_templates_ref}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "ERROR: mlops_templates_ref must be a refs/heads/* ref, refs/tags/* ref, or 40-character commit SHA." >&2
  exit 1
fi

# Validate required source directories before we start mutating anything.
# The Azure DevOps multi-repo checkout lays out repos as siblings of the
# checkout root; if either repo is missing here, fail with a clear message.
if [ ! -d "${template_repo}" ]; then
  echo "ERROR: template repo directory '${template_repo}' not found in $(pwd)." >&2
  echo "Hint: confirm 'checkout: <template_repo>' is declared in the pipeline and that" >&2
  echo "      the repository name matches the value passed to this script." >&2
  exit 1
fi
if [ ! -d "${repo_name}" ]; then
  echo "ERROR: target repo directory '${repo_name}' not found in $(pwd)." >&2
  echo "Hint: the target repo must be created and checked out before this step runs." >&2
  exit 1
fi
if [ ! -d "${template_repo}/infrastructure/${infrastructure_version}" ]; then
  echo "ERROR: '${template_repo}/infrastructure/${infrastructure_version}' not found." >&2
  exit 1
fi
if [ ! -d "${template_repo}/${project_type}/${mlops_version}" ]; then
  echo "ERROR: '${template_repo}/${project_type}/${mlops_version}' not found." >&2
  exit 1
fi
if [[ "${network_mode}" == "private" && ! -f "${template_repo}/infrastructure/terraform/devops-pipelines/platform-ado-bootstrap.yml" ]]; then
  echo "ERROR: private network mode requires the project-template entrypoint" >&2
  echo "       '${template_repo}/infrastructure/terraform/devops-pipelines/platform-ado-bootstrap.yml'." >&2
  exit 1
fi

if [[ "${MLOPS_FACTORY_SKIP_GIT:-false}" != "true" ]]; then
  git config --global user.email "hosted.agent@dev.azure.com"
  git config --global user.name "Azure Pipeline"
fi

mkdir -p files_to_keep files_to_delete

# Portable replacement for `cp --parents -r` (GNU coreutils only; not
# available in macOS BSD cp or some Windows Git Bash builds). Preserves the
# leading path component the rest of the script expects.
mkdir -p "files_to_keep/infrastructure"
cp -r "${template_repo}/infrastructure/${infrastructure_version}" "files_to_keep/infrastructure/"
mkdir -p "files_to_keep/${project_type}"
cp -r "${template_repo}/${project_type}/${mlops_version}" "files_to_keep/${project_type}/"
for environment_config in common dev test prod; do
  config_file="${template_repo}/config-infra-${environment_config}.yml"
  if [[ -f "${config_file}" ]]; then
    cp "${config_file}" files_to_keep/
  elif [[ "${network_mode}" == "private" || "${environment_config}" == "dev" || "${environment_config}" == "prod" ]]; then
    echo "ERROR: required environment config '${config_file}' was not found." >&2
    exit 1
  fi
done

cat > "files_to_keep/config-factory-${deployment_environment}.yml" <<EOF
# Generated by Azure/mlops-v2. Project and reusable implementation assets
# remain owned by mlops-project-template and mlops-templates.
variables:
  network_mode: '${network_mode}'
  deployment_environment: '${deployment_environment}'
  azure_subscription_id: '\$(azure_subscription_id)'
  variable_group_name: '${variable_group_name}'
  mlops_templates_ref: '${mlops_templates_ref}'
  platform_service_connection_name: '${platform_service_connection}'
  workload_service_connection_name: '${workload_service_connection}'
  managed_devops_pool_name: '${managed_devops_pool_name}'
  managed_devops_pool_alias: '${managed_devops_pool_alias}'
  managed_devops_pool_resource_group: '${managed_devops_pool_resource_group}'
  managed_devops_pool_location: '${managed_devops_pool_location}'
  managed_devops_pool_vm_sku: '${managed_devops_pool_vm_sku}'
  managed_devops_pool_image: '${managed_devops_pool_image}'
  managed_devops_pool_maximum_concurrency: '${managed_devops_pool_maximum_concurrency}'
  platform_virtual_network_name: '${platform_virtual_network_name}'
  platform_vnet_address_prefix: '${platform_vnet_address_prefix}'
  managed_devops_pool_subnet_address_prefix: '${managed_devops_pool_subnet_address_prefix}'
  private_endpoint_subnet_address_prefix: '${private_endpoint_subnet_address_prefix}'
  terraform_state_storage_account_name: '${terraform_state_storage_account_name}'
  terraform_state_container_name: '${terraform_state_container_name}'
  dev_center_project_resource_id: '${dev_center_project_resource_id}'
  cicd_principal_object_id: '\$(cicd_principal_object_id)'
  devops_infrastructure_principal_object_id: '\$(devops_infrastructure_principal_object_id)'
EOF

# Best-effort cleanup of the template checkout; not fatal if already empty.
mv "${template_repo}"/* files_to_delete/ 2>/dev/null || true

if [[ "${MLOPS_FACTORY_SKIP_GIT:-false}" != "true" ]]; then
  cd "${repo_name}"
  git checkout -b main
  cd ..
fi

# Clear the target repo working tree while preserving .git so we can commit.
find "${repo_name}" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
mv files_to_keep/* "${repo_name}/"
cd "${repo_name}"

if [[ "${network_mode}" == "public" ]]; then
  # Preserve the legacy generated-project layout for existing public projects.
  mv "${project_type}/${mlops_version}/data-science" data-science
  mv "${project_type}/${mlops_version}/mlops" mlops
  mv "${project_type}/${mlops_version}/data" data

  if [[ "${mlops_version}" == "python-sdk" ]]; then
    echo "python-sdk"
    mv "${project_type}/${mlops_version}/config-aml.yml" config-aml.yml
  fi

  rm -rf "${project_type}"
  rm -rf mlops/github-actions

  mv "infrastructure/${infrastructure_version}" "${infrastructure_version}"
  rm -rf infrastructure
  mv "${infrastructure_version}" infrastructure
else
  # Private mode preserves the project-template paths consumed by its
  # environment-aware platform, Terraform, and workload pipelines.
  rm -rf "${project_type}/${mlops_version}/mlops/github-actions"
  if [[ ! -f "infrastructure/terraform/devops-pipelines/platform-ado-bootstrap.yml" ]]; then
    echo "ERROR: generated private project is missing platform-ado-bootstrap.yml." >&2
    exit 1
  fi
fi

if [[ "${MLOPS_FACTORY_SKIP_GIT:-false}" != "true" ]]; then
  git add .

  # Refuse to push an empty repo. If staging is empty here, the copy steps
  # silently dropped everything and we'd be creating a false-positive success.
  if git diff --cached --quiet; then
    echo "ERROR: no files staged for initial commit; target repository would be empty." >&2
    echo "Hint: re-run with diagnostics above and check the cp/mv steps." >&2
    exit 1
  fi

  git commit -m 'initial commit'
  git remote -v
  git push --set-upstream origin main
fi
