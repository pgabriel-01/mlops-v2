#!/usr/bin/env bash

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

project_dir=${1:-}
expected_project_template_url=${EXPECTED_PROJECT_TEMPLATE_URL:-https://github.com/pgabriel-01/mlops-project-template}
expected_project_template_ref=${EXPECTED_PROJECT_TEMPLATE_REF:-60fd56455926b2e1391334cc7b292a84d273b3c4}
expected_mlops_templates_repository=${EXPECTED_MLOPS_TEMPLATES_REPOSITORY:-pgabriel-01/mlops-templates}
expected_mlops_templates_ref=${EXPECTED_MLOPS_TEMPLATES_REF:-70b7ce23a9cb905b528fc4cbc1a375eabf893a0c}

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

for path in \
  .mlops-generation.json \
  README.md \
  config-infra-dev.yml \
  config-infra-test.yml \
  config-infra-prod.yml \
  data-science \
  infrastructure/assets/dev-jumpbox-bootstrap.pub \
  infrastructure/main.bicep \
  infrastructure/modules/aml_computecluster.bicep \
  infrastructure/modules/aml_online_endpoint_identity.bicep \
  infrastructure/modules/aml_workspace.bicep \
  infrastructure/modules/bastion.bicep \
  infrastructure/modules/key_vault.bicep \
  infrastructure/modules/private_dns_zone_vnet_link.bicep \
  infrastructure/modules/private_dns_zones.bicep \
  infrastructure/modules/storage_account.bicep \
  infrastructure/modules/vnet.bicep \
  mlops/azureml/deploy/batch/score.py \
  mlops/azureml/deploy/online/code/score.py \
  mlops/azureml/deploy/online/deploy.py \
  mlops/azureml/deploy/online/deployment_lock.py \
  mlops/azureml/deploy/online/requirements.txt \
  mlops/azureml/train/job.yml \
  mlops/scripts/check_legacy_bastion.py \
  mlops/scripts/export_config.py \
  mlops/scripts/project_config.py \
  mlops/scripts/render_bicep_parameters.py \
  mlops/scripts/validate_project.py \
  runner-bootstrap/helm/runner-set-values.yaml \
  runner-bootstrap/image/Dockerfile \
  runner-bootstrap/infrastructure/main.bicep \
  runner-bootstrap/scripts/deployment_config.sh \
  runner-bootstrap/scripts/install_arc.sh \
  runner-bootstrap/scripts/invoke_aks_command.py \
  runner-bootstrap/scripts/preflight.sh \
  runner-bootstrap/scripts/provision.sh \
  runner-bootstrap/tests/test_validate_compute_quota.py; do
  require_path "$path"
done

for retired in \
  infrastructure/manifests/azureml-inference-namespace.yaml \
  infrastructure/modules/aks_aml_inference.bicep \
  infrastructure/modules/aks_run_command_role.bicep \
  infrastructure/modules/aml_environment.bicep \
  infrastructure/modules/aml_kubernetes_compute.bicep \
  infrastructure/modules/aml_kubernetes_identity.bicep; do
  if [ -e "$project_dir/$retired" ]; then
    fail "Retired private AKS inference asset remains: $retired"
  fi
done

if [ -e "$project_dir/classical" ] ||
  [ -e "$project_dir/cv" ] ||
  [ -e "$project_dir/nlp" ]; then
  fail "Source selector directories remain in the generated project"
fi

metadata_file=$(mktemp "${TMPDIR:-/tmp}/mlops-generation.XXXXXX")
trap 'rm -f "$metadata_file"' EXIT

if ! python3 - "$project_dir" \
  "$expected_project_template_url" \
  "$expected_project_template_ref" \
  "$expected_mlops_templates_repository" \
  "$expected_mlops_templates_ref" >"$metadata_file" <<'PY'
import json
import ipaddress
import re
import sys
import unicodedata
from pathlib import Path

project_dir = Path(sys.argv[1])
RFC1918_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)
expected_url, expected_ref, expected_repository, expected_templates_ref = sys.argv[2:]
metadata = json.loads((project_dir / ".mlops-generation.json").read_text(encoding="utf-8"))

errors = []
expected_source = {
    "infrastructure_version": "bicep",
    "project_type": "classical",
    "mlops_version": "python-sdk-v2",
    "project_template_github_url": expected_url,
    "project_template_git_ref": expected_ref,
    "project_template_commit": expected_ref,
    "mlops_templates_repository": expected_repository,
    "mlops_templates_git_ref": expected_templates_ref,
}
for key, expected in expected_source.items():
    if metadata.get(key) != expected:
        errors.append(f"provenance {key} must be {expected!r}, got {metadata.get(key)!r}")

workload_name = metadata.get("workload_name")
namespace = metadata.get("workload_namespace")
environment_names = metadata.get("environment_names")
environment_vnet_cidrs = metadata.get("environment_vnet_cidrs")
orchestration = metadata.get("orchestration")

if not isinstance(workload_name, str) or not workload_name.strip():
    errors.append("workload_name must be a non-empty string")
elif len(workload_name) > 256 or any(
    unicodedata.category(character).startswith("C") for character in workload_name
):
    errors.append("workload_name exceeds tag limits or contains control characters")
if not isinstance(namespace, str) or not re.fullmatch(r"[a-z][a-z0-9]{1,15}", namespace):
    errors.append("workload_namespace must be a 2-16 character lowercase Azure-safe name")
if orchestration not in {"github-actions", "azure-devops"}:
    errors.append(f"unsupported orchestration provenance: {orchestration!r}")
if (
    not isinstance(environment_names, dict)
    or set(environment_names) != {"dev", "test", "prod"}
    or any(not isinstance(value, str) or not value for value in environment_names.values())
):
    errors.append("environment_names must map dev/test/prod to three unique non-empty names")
else:
    normalized_environment_names = set()
    for environment, value in environment_names.items():
        if len(value) > 255 or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._ -]{0,254}", value):
            errors.append(f"{environment} environment name uses unsupported characters or length")
        normalized = value.casefold()
        if normalized in normalized_environment_names:
            errors.append("environment_names collide under GitHub case-insensitive comparison")
        normalized_environment_names.add(normalized)

network_cidrs = {}
environment_networks = {}
if (
    not isinstance(environment_vnet_cidrs, dict)
    or set(environment_vnet_cidrs) != {"dev", "test", "prod"}
):
    errors.append("environment_vnet_cidrs must map dev/test/prod to explicit CIDRs")
else:
    for environment, value in environment_vnet_cidrs.items():
        try:
            network = ipaddress.ip_network(value, strict=True)
            if not isinstance(network, ipaddress.IPv4Network):
                raise ValueError("must be IPv4")
            if not any(network.subnet_of(parent) for parent in RFC1918_NETWORKS):
                raise ValueError("must be contained in RFC1918 space")
            if network.prefixlen > 21:
                raise ValueError("must be /21 or larger")
            environment_networks[environment] = network
            subnets = list(network.subnets(new_prefix=24))
            network_cidrs[environment] = {
                "vnet_address_prefix": str(network),
                "default_subnet_prefix": str(subnets[0]),
                "compute_subnet_prefix": str(subnets[1]),
                "private_endpoint_subnet_prefix": str(subnets[2]),
                "bastion_subnet_prefix": str(next(subnets[3].subnets(new_prefix=26))),
                "administration_subnet_prefix": str(next(subnets[4].subnets(new_prefix=27))),
            }
            subnet_values = [
                ipaddress.ip_network(subnet)
                for key, subnet in network_cidrs[environment].items()
                if key != "vnet_address_prefix"
            ]
            if any(not subnet.subnet_of(network) for subnet in subnet_values):
                raise ValueError("derived subnet is outside its environment VNet")
            if any(
                subnet.overlaps(other)
                for index, subnet in enumerate(subnet_values)
                for other in subnet_values[index + 1 :]
            ):
                raise ValueError("derived subnets overlap")
        except (TypeError, ValueError) as exc:
            errors.append(f"{environment} VNet CIDR is invalid: {exc}")
    for index, environment in enumerate(("dev", "test", "prod")):
        for other_environment in ("dev", "test", "prod")[index + 1 :]:
            if (
                environment in environment_networks
                and other_environment in environment_networks
                and environment_networks[environment].overlaps(
                    environment_networks[other_environment]
                )
            ):
                errors.append(
                    f"environment VNet CIDRs overlap: {environment} and {other_environment}"
                )

if not errors:
    for environment in ("dev", "test", "prod"):
        config_path = project_dir / f"config-infra-{environment}.yml"
        config = {}
        for raw_line in config_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or ":" not in line:
                continue
            key, value = line.split(":", 1)
            value = value.strip()
            if value.startswith('"') and value.endswith('"'):
                value = json.loads(value)
            config[key.strip()] = value
        expected_values = {
            "environment": environment,
            "environment_name": environment_names[environment],
            "workload_name": workload_name,
            "namespace": namespace,
            "model_name": "taxi-model",
            "batch_compute_name": "cpu-cluster",
            "private_network": "true",
            "enable_managed_online_endpoint": "true",
            "online_mlflow_no_code": "true",
        }
        if environment in network_cidrs:
            expected_values.update(network_cidrs[environment])
        for key, expected in expected_values.items():
            if config.get(key) != expected:
                errors.append(
                    f"{config_path.name} {key} must be {expected!r}, got {config.get(key)!r}"
                )
        expected_jumpbox = "true" if environment == "dev" else "false"
        if config.get("enable_dev_jumpbox") != expected_jumpbox:
            errors.append(
                f"{config_path.name} enable_dev_jumpbox must be {expected_jumpbox}"
            )

for error in errors:
    print(f"ERROR: {error}", file=sys.stderr)
if errors:
    raise SystemExit(1)

print(orchestration)
print(namespace)
print(workload_name)
print(environment_names["dev"])
print(environment_names["test"])
print(environment_names["prod"])
PY
then
  failures=$((failures + 1))
fi

if [ -s "$metadata_file" ]; then
  orchestration=$(sed -n '1p' "$metadata_file")
  namespace=$(sed -n '2p' "$metadata_file")
  workload_name=$(sed -n '3p' "$metadata_file")
  dev_environment_name=$(sed -n '4p' "$metadata_file")
  test_environment_name=$(sed -n '5p' "$metadata_file")
  prod_environment_name=$(sed -n '6p' "$metadata_file")
else
  orchestration=invalid
  namespace=invalid
  workload_name=invalid
  dev_environment_name=invalid
  test_environment_name=invalid
  prod_environment_name=invalid
fi

for suffix in batch.csv data.csv request.json; do
  require_path "data/$namespace-$suffix"
done

if grep -R -I -q -e '/Users/' "$project_dir" --exclude-dir=.git; then
  fail "Local paths remain"
fi

pipeline_roots=()
[ -d "$project_dir/.github/workflows" ] && pipeline_roots+=("$project_dir/.github/workflows")
[ -d "$project_dir/mlops/devops-pipelines" ] && pipeline_roots+=("$project_dir/mlops/devops-pipelines")
if [ "${#pipeline_roots[@]}" -gt 0 ] &&
  grep -R -I -q -e '__MLOPS_TEMPLATES_' -e 'classical/python-sdk-v2/' -e 'infrastructure/bicep/' \
    "${pipeline_roots[@]}"; then
  fail "Placeholders or source-template paths remain in generated pipeline files"
fi

if grep -R -I -E -q \
  -e 'AZURE_CREDENTIALS[[:space:]]*[:=]' \
  -e 'secrets\.AZURE_CREDENTIALS' \
  -e 'client[_-]?secret[[:space:]]*[:=]' \
  -e '/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/' \
  "$project_dir" --exclude-dir=.git; then
  fail "Credential-shaped values or live Azure resource IDs remain"
fi

escaped_workload_name=${workload_name//\'/\'\'}
if ! grep -Fq "param workloadDisplayName string = '$escaped_workload_name'" \
  "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq 'Project: workloadDisplayName' "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq 'Name: workloadDisplayName' "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq '"workload_name": "workloadDisplayName"' \
    "$project_dir/mlops/scripts/render_bicep_parameters.py"; then
  fail "Workload display name is not wired through config, Bicep parameters, and tags"
fi

if ! grep -Fq -- "--model_name taxi-model" \
  "$project_dir/mlops/azureml/train/job.yml" ||
  grep -R -I -q -e 'model_name: taxifare' -e 'model_name: mlops' \
    "$project_dir" --exclude-dir=.git; then
  fail "The proven taxi-model asset contract changed"
fi

if ! grep -Fq "display_name: \"$workload_name Training\"" \
  "$project_dir/mlops/azureml/train/job.yml" ||
  ! grep -Fq "experiment_name: $namespace-training" \
    "$project_dir/mlops/azureml/train/job.yml" ||
  ! grep -Fq "table_name: ${namespace}monitoring" \
    "$project_dir/mlops/azureml/train/job.yml"; then
  fail "Training metadata is not derived from workload naming inputs"
fi

if ! python3 - "$project_dir/mlops/azureml/deploy/batch/score.py" <<'PY'
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
tree = ast.parse(source)
functions = {
    node.name
    for node in tree.body
    if isinstance(node, ast.FunctionDef)
}
required = (
    "AZUREML_MODEL_DIR",
    "mlflow.pyfunc.load_model",
    "pd.read_csv",
    "pd.read_parquet",
    "pd.concat",
    "if not mini_batch",
    "if result.empty",
)
errors = []
if not {"init", "run"}.issubset(functions):
    errors.append("batch scoring source must define init() and run(mini_batch)")
errors.extend(
    f"batch scoring source is missing {contract}"
    for contract in required
    if contract not in source
)
for error in errors:
    print(f"ERROR: {error}", file=sys.stderr)
if errors:
    raise SystemExit(1)
PY
then
  failures=$((failures + 1))
fi

if ! grep -Fq 'enableManagedOnlineEndpoint bool = true' \
  "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq "module onlineEndpointIdentity './modules/aml_online_endpoint_identity.bicep'" \
    "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq 'enableDeploymentLocks: enableManagedOnlineEndpoint' \
    "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq "managedNetworkKind: 'V1'" \
    "$project_dir/infrastructure/modules/aml_workspace.bicep" ||
  ! grep -Fq "publicNetworkAccess: enableNetworkIsolation ? 'Disabled' : 'Enabled'" \
    "$project_dir/infrastructure/modules/aml_workspace.bicep" ||
  ! grep -Fq 'allowSharedKeyAccess: false' \
    "$project_dir/infrastructure/modules/storage_account.bicep"; then
  fail "Private managed-online infrastructure or local-auth security changed"
fi

if ! grep -Fq "param enableDevJumpbox bool = env == 'dev'" \
  "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq "param devJumpboxVmSize string = 'Standard_D2s_v5'" \
    "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq "param devJumpboxUbuntuImageVersion string = '24.04.202608270'" \
    "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq "param devJumpboxAzureMlExtensionVersion string = '2.44.1'" \
    "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq "param devJumpboxAzureAiMlVersion string = '1.35.0'" \
    "$project_dir/infrastructure/main.bicep"; then
  fail "Dev-only jumpbox or immutable tool/image versions changed"
fi

if ! grep -Fq '"batch_compute_name": "imageBuildComputeName"' \
  "$project_dir/mlops/scripts/render_bicep_parameters.py" ||
  ! grep -Fq 'imageBuildCompute: imageBuildComputeName' \
    "$project_dir/infrastructure/modules/aml_workspace.bicep" ||
  ! grep -Fq 'computeClusterName: imageBuildComputeName' \
    "$project_dir/infrastructure/main.bicep"; then
  fail "Workspace imageBuildCompute and batch compute naming diverged"
fi

if ! grep -Fq 'DEV_JUMPBOX_LOGIN_GROUP_ID' \
  "$project_dir/mlops/scripts/render_bicep_parameters.py" ||
  ! grep -Fq 'uuid.UUID(dev_jumpbox_login_group_id)' \
    "$project_dir/mlops/scripts/render_bicep_parameters.py" ||
  ! grep -Fq 'canonical_group_id != dev_jumpbox_login_group_id' \
    "$project_dir/mlops/scripts/render_bicep_parameters.py"; then
  fail "Dev jumpbox login group runtime override is missing canonical UUID validation"
fi

if ! grep -Fq "var keyVaultPrefix = take(replace(toLower(prefix), '-', ''), 5)" \
  "$project_dir/infrastructure/main.bicep" ||
  ! grep -Fq '@maxLength(24)' \
    "$project_dir/infrastructure/modules/key_vault.bicep" ||
  ! grep -Fq 'sharedPrivateDnsZoneResourceIds object = {}' \
    "$project_dir/infrastructure/modules/private_dns_zones.bicep"; then
  fail "Key Vault length or shared private DNS contracts changed"
fi

if ! grep -Fq -- '- /home/runner/run.sh' \
  "$project_dir/runner-bootstrap/helm/runner-set-values.yaml" ||
  ! grep -Fq "param nodeVmSize string = 'Standard_D2ads_v6'" \
    "$project_dir/runner-bootstrap/infrastructure/main.bicep" ||
  ! grep -Eq 'SYSTEM_NODE_COUNT=.*:-2' \
    "$project_dir/runner-bootstrap/scripts/deployment_config.sh" ||
  ! grep -Fq 'response["exitCode"]' \
    "$project_dir/runner-bootstrap/scripts/invoke_aks_command.py" ||
  ! grep -Fq 'response.get("provisioningState")' \
    "$project_dir/runner-bootstrap/scripts/invoke_aks_command.py"; then
  fail "Hardened ARC runner, quota, or AKS command contracts changed"
fi

if [ "$orchestration" = github-actions ]; then
  require_path ".github/workflows"
  if [ -d "$project_dir/mlops/devops-pipelines" ]; then
    fail "Azure DevOps pipelines remain in GitHub Actions generation"
  fi

  expected_workflows=(
    build-runner-image.yml
    update-runner-image.yml
    deploy-infrastructure.yml
    train-register-model.yml
    deploy-online-endpoint.yml
    deploy-batch-endpoint.yml
    runner-smoke-test.yml
  )
  for workflow in "${expected_workflows[@]}"; do
    require_path ".github/workflows/$workflow"
  done

  for workflow in \
    deploy-infrastructure.yml \
    train-register-model.yml \
    deploy-online-endpoint.yml \
    deploy-batch-endpoint.yml; do
    path="$project_dir/.github/workflows/$workflow"
    if ! grep -Fq "description: \"$workload_name environment to target\"" "$path" ||
      ! grep -Fq "default: \"$dev_environment_name\"" "$path" ||
      ! grep -Fq "options: [\"$dev_environment_name\", \"$test_environment_name\", \"$prod_environment_name\"]" "$path"; then
      fail "$workflow does not expose the configured human environment input labels"
    fi
    for mapping in \
      "\"$dev_environment_name\") environment=dev ;;" \
      "\"$test_environment_name\") environment=test ;;" \
      "\"$prod_environment_name\") environment=prod ;;"; do
      if ! grep -Fq "$mapping" "$path"; then
        fail "$workflow is missing environment mapping: $mapping"
      fi
    done
  done

  if ! grep -Fq 'environment: ${{ needs.config.outputs.environment_name }}' \
    "$project_dir/.github/workflows/deploy-infrastructure.yml" ||
    ! grep -Fq 'environment: ${{ needs.config.outputs.environment_name }}' \
      "$project_dir/.github/workflows/train-register-model.yml" ||
    ! grep -Fq 'environment: ${{ needs.config.outputs.environment_name }}' \
      "$project_dir/.github/workflows/deploy-batch-endpoint.yml" ||
    ! grep -Fq 'environment: ${{ inputs.environment }}' \
      "$project_dir/.github/workflows/deploy-online-endpoint.yml"; then
    fail "GitHub jobs do not use the configured display labels"
  fi
  if [ "$(grep -F -c 'DEV_JUMPBOX_LOGIN_GROUP_ID: ${{ vars.DEV_JUMPBOX_LOGIN_GROUP_ID }}' \
    "$project_dir/.github/workflows/deploy-infrastructure.yml")" -ne 2 ]; then
    fail "GitHub infrastructure validation and deployment must pass the jumpbox login group variable"
  fi

  if ! grep -Fq "request_batch_file: data/$namespace-batch.csv" \
    "$project_dir/.github/workflows/deploy-batch-endpoint.yml" ||
    ! grep -Fq -- "--request-file data/$namespace-request.json" \
      "$project_dir/.github/workflows/deploy-online-endpoint.yml" ||
    ! grep -Fq 'az ml workspace provision-network' \
      "$project_dir/.github/workflows/deploy-online-endpoint.yml" ||
    ! grep -Fq -- '--alternate-deployment-name' \
      "$project_dir/.github/workflows/deploy-online-endpoint.yml"; then
    fail "GitHub batch or managed-online endpoint behavior changed"
  fi

  expected_workflow_source="$expected_mlops_templates_repository/.github/workflows/python-sdk-v2-"
  workflow_source_count=$(grep -R -I -F -h "uses: $expected_workflow_source" \
    "$project_dir/.github/workflows"/*.yml | wc -l | tr -d ' ')
  if [ "$workflow_source_count" -ne 2 ]; then
    fail "Expected two reusable Python SDK v2 workflow calls"
  fi
  if grep -R -I -F -h "uses: $expected_workflow_source" \
    "$project_dir/.github/workflows"/*.yml |
    grep -F -v -q "@$expected_mlops_templates_ref"; then
    fail "Reusable workflows are not pinned to $expected_mlops_templates_ref"
  fi

  if ! python3 "$project_dir/mlops/scripts/validate_project.py" \
    --require-resolved-templates; then
    fail "Generated project self-validation failed"
  fi
elif [ "$orchestration" = azure-devops ]; then
  if [ -d "$project_dir/.github/workflows" ]; then
    fail "GitHub workflows remain in Azure DevOps generation"
  fi
  for pipeline in \
    deploy-infrastructure-pipeline.yml \
    deploy-online-endpoint-pipeline.yml \
    deploy-batch-endpoint-pipeline.yml \
    deploy-model-training-pipeline.yml; do
    require_path "mlops/devops-pipelines/$pipeline"
  done

  infrastructure_pipeline="$project_dir/mlops/devops-pipelines/deploy-infrastructure-pipeline.yml"
  online_pipeline="$project_dir/mlops/devops-pipelines/deploy-online-endpoint-pipeline.yml"
  if ! grep -Fq 'REQUIRED_PRIVATE_SELF_HOSTED_POOL|Azure\ Pipelines|Default)' \
    "$infrastructure_pipeline" ||
    ! grep -Fq 'if [[ -z "${idToken:-}" ]]' "$infrastructure_pipeline" ||
    ! grep -Fq 'infrastructure/parameters.json' "$infrastructure_pipeline" ||
    ! grep -Fq 'condition: and(succeeded(), eq(' "$infrastructure_pipeline" ||
    ! grep -Fq 'name: devJumpboxLoginGroupId' "$infrastructure_pipeline" ||
    [ "$(grep -F -c 'DEV_JUMPBOX_LOGIN_GROUP_ID: ${{ parameters.devJumpboxLoginGroupId }}' \
      "$infrastructure_pipeline")" -ne 2 ] ||
    grep -Fq 'vmImage:' "$infrastructure_pipeline"; then
    fail "Azure DevOps infrastructure pipeline is not private, gated, and workload-identity based"
  fi
  if ! grep -Fq 'REQUIRED_PRIVATE_SELF_HOSTED_POOL|Azure\ Pipelines|Default)' \
    "$online_pipeline" ||
    ! grep -Fq 'if [[ -z "${idToken:-}" ]]' "$online_pipeline" ||
    ! grep -Fq 'az ml workspace provision-network' "$online_pipeline" ||
    ! grep -Fq -- "--request-file data/$namespace-request.json" "$online_pipeline"; then
    fail "Azure DevOps online pipeline is not private managed-online with workload identity"
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "Generated project validation failed with $failures error(s)." >&2
  exit 1
fi

echo "Generated project validation passed: $project_dir"
