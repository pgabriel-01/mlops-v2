#!/usr/bin/env bash

set -euo pipefail

project_dir=${1:-}

if [ -z "$project_dir" ] || [ ! -d "$project_dir" ]; then
  echo "Usage: $0 <generated-project-directory>" >&2
  exit 2
fi

failures=0

fail() {
  echo "ERROR: $*" >&2
  failures=$((failures + 1))
}

require_path() {
  if [ ! -e "$project_dir/$1" ]; then
    fail "Missing required path: $1"
  fi
}

require_path ".mlops-generation.json"
require_path ".github/workflows"
require_path "data-science"
require_path "data"
require_path "mlops/azureml"
require_path "infrastructure/main.bicep"
require_path "config-infra-dev.yml"
require_path "config-infra-test.yml"
require_path "config-infra-prod.yml"

expected_workflows=(
  "deploy-infrastructure.yml"
  "train-register-model.yml"
  "deploy-online-endpoint.yml"
  "deploy-batch-endpoint.yml"
)

for workflow in "${expected_workflows[@]}"; do
  require_path ".github/workflows/$workflow"
done

workflow_count=$(find "$project_dir/.github/workflows" -maxdepth 1 -type f -name '*.yml' | wc -l | tr -d ' ')
if [ "$workflow_count" -ne "${#expected_workflows[@]}" ]; then
  fail "Expected only the four selected Python SDK v2 GitHub workflows; found $workflow_count"
fi

if find "$project_dir" -path "$project_dir/.git" -prune -o \
  \( -type d -name terraform -o -type d -name devops-pipelines -o -type f -name '*.tf' \) \
  -print -quit | grep -q .; then
  fail "Terraform or Azure DevOps assets remain in the generated project"
fi

if grep -R -I -q \
  -e '__MLOPS_TEMPLATES_' \
  -e 'AzureCLI@' \
  -e 'Bash@' \
  -e 'ado_service_connection' \
  -e 'managed_devops_pool' \
  "$project_dir" --exclude-dir=.git; then
  fail "Unresolved placeholders or Azure DevOps-specific configuration remain"
fi

if grep -R -I -q \
  -e '/Users/' \
  -e '/home/' \
  "$project_dir" --exclude-dir=.git; then
  fail "Local paths remain"
fi

if grep -R -I -E -q \
  -e 'AZURE_CREDENTIALS[[:space:]]*[:=]' \
  -e 'secrets\.AZURE_CREDENTIALS' \
  -e 'client[_-]?secret[[:space:]]*[:=]' \
  "$project_dir" --exclude-dir=.git; then
  fail "Credential-shaped values remain"
fi

if grep -R -I -E -q \
  '/subscriptions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/resourceGroups/' \
  "$project_dir" --exclude-dir=.git; then
  fail "A live Azure resource ID remains in the generated project"
fi

for environment in dev test prod; do
  config_file="$project_dir/config-infra-$environment.yml"

  if [ -f "$config_file" ]; then
    if ! grep -Eq '^runner_hub_vnet_resource_id:[[:space:]]*(""|'\'\'')[[:space:]]*$' "$config_file"; then
      fail "config-infra-$environment.yml must leave runner_hub_vnet_resource_id empty"
    fi

    if ! grep -Eq '^manage_runner_hub_to_workload_peering:[[:space:]]*false[[:space:]]*$' "$config_file"; then
      fail "config-infra-$environment.yml must default reciprocal runner-hub peering ownership to false"
    fi
  fi
done

if ! grep -Eq '"project_template_commit": "[0-9a-f]{40}"' "$project_dir/.mlops-generation.json"; then
  fail "Project template provenance is not pinned to a full commit SHA"
fi

if ! grep -Eq '"mlops_templates_git_ref": "[0-9a-f]{40}"' "$project_dir/.mlops-generation.json"; then
  fail "Reusable workflow provenance is not pinned to a full commit SHA"
fi

if [ "$failures" -ne 0 ]; then
  echo "Generated project validation failed with $failures error(s)." >&2
  exit 1
fi

echo "Generated project validation passed: $project_dir"
