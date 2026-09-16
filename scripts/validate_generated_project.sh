#!/usr/bin/env bash

set -euo pipefail

project_dir=${1:-}
expected_project_template_url=${EXPECTED_PROJECT_TEMPLATE_URL:-https://github.com/pgabriel-01/mlops-project-template}
expected_project_template_ref=${EXPECTED_PROJECT_TEMPLATE_REF:-164e880c0c01df9d81b539a26d11fbb55a86c6b0}
expected_mlops_templates_repository=${EXPECTED_MLOPS_TEMPLATES_REPOSITORY:-pgabriel-01/mlops-templates}
expected_mlops_templates_ref=${EXPECTED_MLOPS_TEMPLATES_REF:-8dbe32cab29268ef128ece88ef994927648fc70f}

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
require_path "mlops/azureml/deploy/batch/score.py"
require_path "mlops/online-runtime/Dockerfile"
require_path "mlops/online-runtime/requirements.txt"
require_path "infrastructure/main.bicep"
require_path "infrastructure/manifests/azureml-inference-namespace.yaml"
require_path "infrastructure/modules/aks_aml_inference.bicep"
require_path "infrastructure/modules/aks_run_command_role.bicep"
require_path "infrastructure/modules/aml_computecluster.bicep"
require_path "infrastructure/modules/aml_environment.bicep"
require_path "infrastructure/modules/aml_kubernetes_compute.bicep"
require_path "infrastructure/modules/aml_kubernetes_identity.bicep"
require_path "infrastructure/modules/aml_workspace.bicep"
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
  "publish-online-runtime.yml"
  "deploy-batch-endpoint.yml"
  "runner-smoke-test.yml"
)

for workflow in "${expected_workflows[@]}"; do
  require_path ".github/workflows/$workflow"
done

workflow_count=$(find "$project_dir/.github/workflows" -maxdepth 1 -type f -name '*.yml' | wc -l | tr -d ' ')
if [ "$workflow_count" -ne "${#expected_workflows[@]}" ]; then
  fail "Expected only the seven selected Python SDK v2 GitHub workflows; found $workflow_count"
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

if ! grep -Fq 'scoring_code_directory: mlops/azureml/deploy/batch' \
  "$project_dir/.github/workflows/deploy-batch-endpoint.yml" ||
  ! grep -Fq 'scoring_script: score.py' \
    "$project_dir/.github/workflows/deploy-batch-endpoint.yml" ||
  ! grep -Fq 'request_batch_file: data/taxi-batch.csv' \
    "$project_dir/.github/workflows/deploy-batch-endpoint.yml" ||
  ! grep -Fq 'default: azureml://registries/azureml/environments/sklearn-1.5/versions/53' \
    "$project_dir/.github/workflows/deploy-batch-endpoint.yml"; then
  fail "Batch workflow must provide checked-in scoring code, live input, and the immutable curated environment"
fi

python3 - "$project_dir/mlops/azureml/deploy/batch/score.py" <<'PY' || failures=$((failures + 1))
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1])
tree = ast.parse(path.read_text(encoding="utf-8"))
functions = {
    node.name: node
    for node in tree.body
    if isinstance(node, ast.FunctionDef)
}
source = path.read_text(encoding="utf-8")
errors = []
if "init" not in functions or "run" not in functions:
    errors.append("batch scoring source must define init() and run(mini_batch)")
for required in (
    "AZUREML_MODEL_DIR",
    "mlflow.pyfunc.load_model",
    "pd.read_csv",
    "pd.read_parquet",
    "pd.concat",
    "if not mini_batch",
    "if result.empty",
):
    if required not in source:
        errors.append(f"batch scoring source is missing {required}")
if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)
PY

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

if ! grep -Fq "resource trustedAccess 'Microsoft.ContainerService/managedClusters/trustedAccessRoleBindings@" \
  "$project_dir/infrastructure/modules/aks_aml_inference.bicep" ||
  ! grep -Fq "'Microsoft.MachineLearningServices/workspaces/mlworkload'" \
    "$project_dir/infrastructure/modules/aks_aml_inference.bicep" ||
  ! grep -Fq "allowInsecureConnections: 'False'" \
    "$project_dir/infrastructure/modules/aks_aml_inference.bicep" ||
  ! grep -Fq 'sslCertPemFile: extensionTlsCertPem' \
    "$project_dir/infrastructure/modules/aks_aml_inference.bicep" ||
  ! grep -Fq 'sslKeyPemFile: extensionTlsKeyPem' \
    "$project_dir/infrastructure/modules/aks_aml_inference.bicep" ||
  ! grep -Fq "kind: 'AzureCLI'" \
    "$project_dir/infrastructure/modules/aks_aml_inference.bicep" ||
  ! grep -Fq 'az aks command invoke' \
    "$project_dir/infrastructure/modules/aks_aml_inference.bicep"; then
  fail "Private AKS inference must retain Trusted Access, namespace bootstrap, and protected TLS configuration"
fi

if ! grep -Fq "disableLocalAuth: true" \
  "$project_dir/infrastructure/modules/aml_kubernetes_compute.bicep" ||
  ! grep -Fq "publicNetworkAccess: enableNetworkIsolation ? 'Disabled' : 'Enabled'" \
    "$project_dir/infrastructure/modules/aml_workspace.bicep" ||
  ! grep -Fq 'allowSharedKeyAccess: false' \
    "$project_dir/infrastructure/modules/storage_account.bicep"; then
  fail "Private AML compute, workspace networking, and storage local-auth policies changed"
fi

if ! grep -Fq 'tls_ca_key_vault_secret_id:' \
  "$project_dir/.github/workflows/deploy-online-endpoint.yml" ||
  ! grep -Fq 'endpoint_uami_resource_id:' \
    "$project_dir/.github/workflows/deploy-online-endpoint.yml" ||
  ! grep -Fq 'uses: azure/login@a457da9ea143d694b1b9c7c869ebb04ebe844ef5' \
    "$project_dir/.github/workflows/publish-online-runtime.yml" ||
  ! grep -Fq 'immutable_image="$login_server/mlops/online-runtime@$digest"' \
    "$project_dir/.github/workflows/publish-online-runtime.yml" ||
  ! grep -Eq '^FROM .+@sha256:[0-9a-f]{64}$' \
    "$project_dir/mlops/online-runtime/Dockerfile"; then
  fail "Private online deployment must retain CA trust, managed identity, OIDC, and digest-pinned runtime publication"
fi

python3 - "$project_dir/infrastructure/main.bicep" \
  "$project_dir/infrastructure/modules/aml_workspace.bicep" <<'PY' || failures=$((failures + 1))
import sys
from pathlib import Path

main_path, workspace_path = map(Path, sys.argv[1:])
main = main_path.read_text(encoding="utf-8")
workspace = workspace_path.read_text(encoding="utf-8")

errors = []
if "managedNetwork" in workspace:
    errors.append("AML workspace must use the custom VNet path without managedNetwork")
if "serverlessComputeSettings" in workspace:
    errors.append("AML workspace must not set serverlessComputeSettings")
if "computeSubnetId" in workspace:
    errors.append("AML workspace module must not accept computeSubnetId")

mlw_start = main.find("module mlw './modules/aml_workspace.bicep'")
mlw_end = main.find("module peMlw ", mlw_start)
if mlw_start == -1 or mlw_end == -1:
    errors.append("AML workspace module invocation was not found")
elif "computeSubnetId" in main[mlw_start:mlw_end]:
    errors.append("AML workspace invocation must not pass computeSubnetId")

mlwcc_start = main.find("module mlwcc './modules/aml_computecluster.bicep'")
mlwcc_end = main.find("module amlReg ", mlwcc_start)
if mlwcc_start == -1 or mlwcc_end == -1:
    errors.append("AML compute cluster module invocation was not found")
elif "subnetId: enableVNet ? vnet!.outputs.computeSubnetId : ''" not in main[mlwcc_start:mlwcc_end]:
    errors.append("AML compute cluster must retain the compute subnet")
elif "dependsOn: [\n    peMlw\n  ]" not in main[mlwcc_start:mlwcc_end]:
    errors.append("AML compute cluster must explicitly depend on the workspace private endpoint")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)
PY

expected_workflow_source="$expected_mlops_templates_repository/.github/workflows/python-sdk-v2-"
workflow_source_count=$(grep -R -I -F -h "uses: $expected_workflow_source" \
  "$project_dir/.github/workflows"/*.yml | wc -l | tr -d ' ')
if [ "$workflow_source_count" -ne 3 ]; then
  fail "Expected three Python SDK v2 reusable workflows from $expected_mlops_templates_repository"
fi

if grep -R -I -F -h "uses: $expected_workflow_source" \
  "$project_dir/.github/workflows"/*.yml |
  grep -F -v -q "@$expected_mlops_templates_ref"; then
  fail "Python SDK v2 reusable workflows are not pinned to $expected_mlops_templates_ref"
fi

sdk_ref_count=$(grep -R -I -F -h "sdk_ref: $expected_mlops_templates_ref" \
  "$project_dir/.github/workflows"/*.yml | wc -l | tr -d ' ')
if [ "$sdk_ref_count" -ne 3 ]; then
  fail "Expected three Python SDK v2 SDK checkouts pinned to $expected_mlops_templates_ref"
fi

templates_checkout=$(mktemp -d "${TMPDIR:-/tmp}/mlops-templates-contract.XXXXXX")
trap 'rm -rf "$templates_checkout"' EXIT
if ! git -C "$templates_checkout" init -q ||
  ! git -C "$templates_checkout" remote add origin \
    "https://github.com/$expected_mlops_templates_repository.git" ||
  ! git -C "$templates_checkout" fetch -q --depth 1 origin \
    "$expected_mlops_templates_ref" ||
  ! git -C "$templates_checkout" checkout -q FETCH_HEAD -- \
    .github/workflows/python-sdk-v2-batch.yml \
    .github/workflows/python-sdk-v2-online.yml \
    src/python-sdk-v2/aml_client.py \
    src/python-sdk-v2/create_batch_deployment.py; then
  fail "Unable to inspect the pinned mlops-templates source contract"
else
  if ! grep -Fq 'CodeConfiguration' \
    "$templates_checkout/src/python-sdk-v2/create_batch_deployment.py" ||
    ! grep -Fq 'verify_live_deployment(' \
      "$templates_checkout/src/python-sdk-v2/create_batch_deployment.py" ||
    ! grep -Fq 'refusing to invoke a deployment that could synthesize an anonymous' \
      "$templates_checkout/src/python-sdk-v2/create_batch_deployment.py" ||
    ! grep -Fq 'AzureCliCredential()' \
      "$templates_checkout/src/python-sdk-v2/aml_client.py" ||
    ! grep -Fq 'use_private_ca_bundle' \
      "$templates_checkout/src/python-sdk-v2/aml_client.py" ||
    ! grep -Fq 'id-token: write' \
      "$templates_checkout/.github/workflows/python-sdk-v2-batch.yml" ||
    ! grep -Fq 'id-token: write' \
      "$templates_checkout/.github/workflows/python-sdk-v2-online.yml"; then
    fail "Pinned mlops-templates source lacks explicit batch code, live verification, OIDC, or private CA contracts"
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "Generated project validation failed with $failures error(s)." >&2
  exit 1
fi

echo "Generated project validation passed: $project_dir"
