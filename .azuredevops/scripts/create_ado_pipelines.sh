#!/usr/bin/env bash

set -euo pipefail

repo_name=$1
project_name=$2
network_mode=${3:-public}
deployment_environment=${4:-dev}
project_type=${5:-classical}
mlops_version=${6:-aml-cli-v2}
path_to_mlops_pipelines=mlops/devops-pipelines

case "$network_mode" in
    public|private) ;;
    *)
        echo "ERROR: network_mode must be 'public' or 'private', got '$network_mode'." >&2
        exit 1
        ;;
esac

case "$deployment_environment" in
    dev|test|prod) ;;
    *)
        echo "ERROR: deployment_environment must be 'dev', 'test', or 'prod', got '$deployment_environment'." >&2
        exit 1
        ;;
esac

if [ "$network_mode" = "private" ]; then
    path_to_infrastructure_pipelines=infrastructure/terraform/devops-pipelines
    path_to_mlops_pipelines="$project_type/$mlops_version/mlops/devops-pipelines"
elif [ -d "$repo_name/infrastructure/devops-pipelines" ]; then
    path_to_infrastructure_pipelines=infrastructure/devops-pipelines
elif [ -d "$repo_name/infrastructure/pipelines" ]; then
    path_to_infrastructure_pipelines=infrastructure/pipelines
else
    echo "ERROR: no infrastructure pipeline directory found in '$repo_name'." >&2
    exit 1
fi

# Resolve the agent queue ID for the hosted "Azure Pipelines" pool. Without
# --queue-id, `az pipelines create` may fail with "Could not queue the build
# because there were validation errors or warnings" on newly-provisioned ADO
# projects where the default queue association has not yet been established.
# Override by exporting AGENT_POOL_NAME before running this script if you use
# a self-hosted pool.
agent_pool_name="${AGENT_POOL_NAME:-Azure Pipelines}"
queue_id=$(az pipelines queue list \
    --project "$project_name" \
    --query "[?name=='$agent_pool_name'].id | [0]" \
    -o tsv || true)

if [ -z "$queue_id" ]; then
    echo "WARNING: Could not resolve queue ID for agent pool '$agent_pool_name'." >&2
    echo "Pipelines will be created without --queue-id; first run may need to be triggered manually." >&2
fi

cd "$repo_name"

create_pipeline_folder() {
    local folder_path=$1
    local create_output

    if ! create_output=$(az pipelines folder create \
        --path "$folder_path" \
        --project "$project_name" 2>&1); then
        if [[ "$create_output" != *"already exists"* ]]; then
            echo "$create_output" >&2
            return 1
        fi
    fi
}

create_pipeline_folder "$repo_name"
create_pipeline_folder "$repo_name/infrastructure"
create_pipeline_folder "$repo_name/mlops"

if [ "$network_mode" = "private" ]; then
    platform_pipeline_file="$path_to_infrastructure_pipelines/platform-ado-bootstrap.yml"
    if [ ! -f "$platform_pipeline_file" ]; then
        echo "ERROR: private network mode requires '$platform_pipeline_file'." >&2
        exit 1
    fi

    az pipelines create \
        --name "00-${deployment_environment}-platform-bootstrap" \
        --detect true \
        --description "Bootstrap private platform networking and Managed DevOps Pool" \
        --repository "$repo_name" \
        --branch main \
        --yml-path "$platform_pipeline_file" \
        --project "$project_name" \
        --repository-type tfsgit \
        --skip-first-run true \
        --folder-path "$repo_name/infrastructure" \
        ${queue_id:+--queue-id $queue_id}
fi

infra_pipeline_files=$(find "$path_to_infrastructure_pipelines" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
if [ -z "$infra_pipeline_files" ]; then
    echo "ERROR: no infrastructure pipelines found in '$path_to_infrastructure_pipelines'." >&2
    exit 1
fi

while IFS= read -r file
do
    pipeline_name=$(basename "$file")
    if [ "$pipeline_name" = "platform-ado-bootstrap.yml" ]; then
        continue
    fi
    if [ "$network_mode" = "private" ]; then
        registered_pipeline_name="10-${pipeline_name%.*}"
    else
        registered_pipeline_name="${pipeline_name%.*}"
    fi
    az pipelines create \
        --name "$registered_pipeline_name" \
        --detect true \
        --description "Automatically created pipeline for infra $file" \
        --repository "$repo_name" \
        --branch main \
        --yml-path "$file" \
        --project "$project_name" \
        --repository-type tfsgit \
        --skip-first-run true \
        --folder-path "$repo_name/infrastructure" \
        ${queue_id:+--queue-id $queue_id}
done <<< "$infra_pipeline_files"

mlops_pipeline_files=$(find "$path_to_mlops_pipelines" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
if [ -z "$mlops_pipeline_files" ]; then
    echo "ERROR: no MLOps pipelines found in '$path_to_mlops_pipelines'." >&2
    exit 1
fi

while IFS= read -r file
do
    pipeline_name=$(basename "$file")
    if [ "$network_mode" = "private" ]; then
        registered_pipeline_name="20-${pipeline_name%.*}"
    else
        registered_pipeline_name="${pipeline_name%.*}"
    fi
    az pipelines create \
        --name "$registered_pipeline_name" \
        --detect true \
        --description "Automatically created pipeline for MLOps $file" \
        --repository "$repo_name" \
        --branch main \
        --yml-path "$file" \
        --project "$project_name" \
        --repository-type tfsgit \
        --skip-first-run true \
        --folder-path "$repo_name/mlops" \
        ${queue_id:+--queue-id $queue_id}
done <<< "$mlops_pipeline_files"
