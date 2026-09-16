#!/usr/bin/env bash

set -euo pipefail

project_dir=${1:-}
expected_project_template_url=${EXPECTED_PROJECT_TEMPLATE_URL:-https://github.com/pgabriel-01/mlops-project-template}
expected_project_template_ref=${EXPECTED_PROJECT_TEMPLATE_REF:-ff0c23a99192fd9f500dcd6666a62511c4120313}
expected_mlops_templates_repository=${EXPECTED_MLOPS_TEMPLATES_REPOSITORY:-pgabriel-01/mlops-templates}
expected_mlops_templates_ref=${EXPECTED_MLOPS_TEMPLATES_REF:-be9755ccfc320fd1f2c1fb4f6b092d745d4fa6b5}

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
require_path "mlops/scripts/export_config.py"
require_path "mlops/scripts/project_config.py"
require_path "mlops/scripts/render_bicep_parameters.py"
require_path "mlops/scripts/validate_project.py"
require_path "infrastructure/main.bicep"
require_path "infrastructure/modules/key_vault.bicep"
require_path "infrastructure/modules/private_dns_zone_vnet_link.bicep"
require_path "infrastructure/modules/private_dns_zones.bicep"
require_path "runner-bootstrap/image/Dockerfile"
require_path "runner-bootstrap/helm/runner-set-values.yaml"
require_path "runner-bootstrap/infrastructure/modules/aks.bicep"
require_path "runner-bootstrap/scripts/preflight.sh"
require_path "runner-bootstrap/scripts/provision.sh"
require_path "runner-bootstrap/tests/test_validate_compute_quota.py"
require_path "config-infra-dev.yml"
require_path "config-infra-test.yml"
require_path "config-infra-prod.yml"

if [ -e "$project_dir/classical" ] || [ -e "$project_dir/cv" ] || [ -e "$project_dir/nlp" ]; then
  fail "Source selector directories remain in the generated project"
fi

expected_workflows=(
  "build-runner-image.yml"
  "deploy-infrastructure.yml"
  "train-register-model.yml"
  "deploy-online-endpoint.yml"
  "deploy-batch-endpoint.yml"
  "runner-smoke-test.yml"
)

for workflow in "${expected_workflows[@]}"; do
  require_path ".github/workflows/$workflow"
done

workflow_count=$(find "$project_dir/.github/workflows" -maxdepth 1 -type f -name '*.yml' | wc -l | tr -d ' ')
if [ "$workflow_count" -ne "${#expected_workflows[@]}" ]; then
  fail "Expected only the six selected Python SDK v2 GitHub workflows; found $workflow_count"
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
  -e 'infrastructure/bicep/' \
  -e 'classical/python-sdk-v2/' \
  "$project_dir/.github/workflows"; then
  fail "Source-template paths remain in generated GitHub workflows"
fi

if ! grep -R -I -q 'infrastructure/main\.bicep' "$project_dir/.github/workflows"; then
  fail "Generated infrastructure workflow does not reference infrastructure/main.bicep"
fi

if ! grep -R -I -q 'mlops/azureml/train/job\.yml' "$project_dir/.github/workflows"; then
  fail "Generated training workflow does not reference mlops/azureml/train/job.yml"
fi

if grep -R -I -q \
  -e '/Users/' \
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

python3 - "$project_dir/.mlops-generation.json" \
  "$expected_project_template_url" \
  "$expected_project_template_ref" \
  "$expected_mlops_templates_repository" \
  "$expected_mlops_templates_ref" <<'PY' || failures=$((failures + 1))
import json
import sys

provenance_path, project_url, project_ref, templates_repository, templates_ref = sys.argv[1:]
with open(provenance_path, encoding="utf-8") as provenance_file:
    provenance = json.load(provenance_file)

expected = {
    "infrastructure_version": "bicep",
    "project_type": "classical",
    "mlops_version": "python-sdk-v2",
    "orchestration": "github-actions",
    "project_template_github_url": project_url,
    "project_template_git_ref": project_ref,
    "project_template_commit": project_ref,
    "mlops_templates_repository": templates_repository,
    "mlops_templates_git_ref": templates_ref,
}

if provenance != expected:
    print(
        "ERROR: Generation provenance does not match the expected immutable source chain.\n"
        f"Expected: {expected}\n"
        f"Actual:   {provenance}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY

if ! grep -Eq 'param systemNodeCount int = 2' "$project_dir/runner-bootstrap/infrastructure/main.bicep" ||
  ! grep -Eq "param nodeVmSize string = 'Standard_D2ads_v6'" "$project_dir/runner-bootstrap/infrastructure/main.bicep"; then
  fail "ARC system pool must default to two Standard_D2ads_v6 nodes"
fi

if ! grep -Eq 'SYSTEM_NODE_COUNT=.*:-2' "$project_dir/runner-bootstrap/scripts/deployment_config.sh" ||
  ! grep -Fq 'self.assertEqual(result["required_vcpus"], 4)' "$project_dir/runner-bootstrap/tests/test_validate_compute_quota.py"; then
  fail "ARC provisioning and quota validation must agree on two four-vCPU system nodes"
fi

if ! grep -Fq -- '- /home/runner/run.sh' "$project_dir/runner-bootstrap/helm/runner-set-values.yaml"; then
  fail "ARC runner image must explicitly invoke /home/runner/run.sh"
fi

if ! grep -Fq "var keyVaultPrefix = take(replace(toLower(prefix), '-', ''), 5)" "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq "var keyVaultEnvironment = take(replace(toLower(env), '-', ''), 3)" "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq '@maxLength(24)' "$project_dir/infrastructure/modules/key_vault.bicep"; then
  fail "Key Vault naming must be capped at 24 characters"
fi

if ! grep -Fq 'sharedPrivateDnsZoneResourceIds object = {}' "$project_dir/infrastructure/modules/private_dns_zones.bicep" ||
  ! grep -Fq "module vnetLink './private_dns_zone_vnet_link.bicep'" "$project_dir/infrastructure/modules/private_dns_zones.bicep" ||
  ! grep -Eq "resource privateDnsZone .* existing = " "$project_dir/infrastructure/modules/private_dns_zone_vnet_link.bicep"; then
  fail "Private DNS deployment must reuse configured zones and manage workload VNet links"
fi

if [ "$failures" -ne 0 ]; then
  echo "Generated project validation failed with $failures error(s)." >&2
  exit 1
fi

echo "Generated project validation passed: $project_dir"
