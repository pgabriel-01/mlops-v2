#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

create_template_fixture() {
  local template_dir=$1

  mkdir -p \
    "$template_dir/infrastructure/terraform/devops-pipelines" \
    "$template_dir/classical/aml-cli-v2/data-science" \
    "$template_dir/classical/aml-cli-v2/data" \
    "$template_dir/classical/aml-cli-v2/mlops/devops-pipelines" \
    "$template_dir/classical/aml-cli-v2/mlops/github-actions"

  printf 'trigger: none\n' > "$template_dir/infrastructure/terraform/devops-pipelines/platform-ado-bootstrap.yml"
  printf 'trigger: none\n' > "$template_dir/infrastructure/terraform/devops-pipelines/tf-ado-deploy-infra.yml"
  printf 'terraform {}\n' > "$template_dir/infrastructure/terraform/main.tf"
  printf 'sample\n' > "$template_dir/classical/aml-cli-v2/data-science/train.py"
  printf 'sample\n' > "$template_dir/classical/aml-cli-v2/data/data.csv"
  printf 'trigger: none\n' > "$template_dir/classical/aml-cli-v2/mlops/devops-pipelines/deploy-model-training-pipeline.yml"
  printf 'trigger: none\n' > "$template_dir/classical/aml-cli-v2/mlops/devops-pipelines/deploy-online-endpoint-pipeline.yml"
  printf 'trigger: none\n' > "$template_dir/classical/aml-cli-v2/mlops/devops-pipelines/deploy-batch-endpoint-pipeline.yml"
  printf 'name: unused\n' > "$template_dir/classical/aml-cli-v2/mlops/github-actions/unused.yml"

  for environment in common dev test prod; do
    printf 'variables:\n  environment: %s\n' "$environment" > "$template_dir/config-infra-$environment.yml"
  done
}

run_generation() {
  local mode=$1
  local root="$work_dir/$mode"
  local template_dir="$root/mlops-project-template"
  local target_dir="$root/generated-project"

  mkdir -p "$target_dir"
  create_template_fixture "$template_dir"

  (
    cd "$root"
    MLOPS_FACTORY_SKIP_GIT=true bash "$script_dir/initialise_repo.sh" \
      generated-project \
      classical \
      aml-cli-v2 \
      mlops-project-template \
      terraform \
      "$mode" \
      dev \
      AUTO \
      refs/tags/v1.0.0 \
      AUTO \
      AUTO \
      AUTO \
      AUTO \
      AUTO \
      eastus2 \
      Standard_D2ads_v5 \
      ubuntu-24.04 \
      2 \
      vnet-mlops-dev-platform \
      10.20.0.0/16 \
      10.20.1.0/24 \
      10.20.2.0/24 \
      stmlopsdevtf0001 \
      default \
      /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-devcenter/providers/Microsoft.DevCenter/projects/mlops
  )

  test -f "$target_dir/config-infra-common.yml"
  test -f "$target_dir/config-infra-dev.yml"
  test -f "$target_dir/config-infra-test.yml"
  test -f "$target_dir/config-infra-prod.yml"
  grep -q "variable_group_name: 'mlops-dev'" "$target_dir/config-factory-dev.yml"
  grep -q "mlops_templates_ref: 'refs/tags/v1.0.0'" "$target_dir/config-factory-dev.yml"
  grep -q "managed_devops_pool_alias: 'mlops-dev-private'" "$target_dir/config-factory-dev.yml"
  grep -q "dev_center_project_resource_id: '/subscriptions/" "$target_dir/config-factory-dev.yml"
  grep -Fq '$(azure_subscription_id)' "$target_dir/config-factory-dev.yml"
  grep -Fq '$(cicd_principal_object_id)' "$target_dir/config-factory-dev.yml"

  if [[ "$mode" == "private" ]]; then
    test -f "$target_dir/infrastructure/terraform/devops-pipelines/platform-ado-bootstrap.yml"
    test -f "$target_dir/classical/aml-cli-v2/mlops/devops-pipelines/deploy-model-training-pipeline.yml"
    test ! -e "$target_dir/classical/aml-cli-v2/mlops/github-actions"
  else
    test -f "$target_dir/infrastructure/devops-pipelines/tf-ado-deploy-infra.yml"
    test -f "$target_dir/mlops/devops-pipelines/deploy-model-training-pipeline.yml"
    test -f "$target_dir/data-science/train.py"
    test ! -e "$target_dir/classical"
  fi
}

run_pipeline_registration_test() {
  local mode=$1
  local target_dir="$work_dir/$mode/generated-project"
  local fake_bin="$work_dir/fake-bin"
  local az_log="$work_dir/az-$mode.log"

  mkdir -p "$fake_bin"
  cat > "$fake_bin/az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "pipelines queue list"* ]]; then
  printf '7\n'
else
  printf '%s\n' "$*" >> "$AZ_LOG"
fi
EOF
  chmod +x "$fake_bin/az"

  (
    cd "$work_dir/$mode"
    PATH="$fake_bin:$PATH" AZ_LOG="$az_log" \
      bash "$script_dir/create_ado_pipelines.sh" \
        generated-project mlops-v2 "$mode" dev classical aml-cli-v2
  )

  if [[ "$mode" == "private" ]]; then
    test "$(grep -c '^pipelines create ' "$az_log")" -eq 5
    grep -q -- '--name 00-dev-platform-bootstrap' "$az_log"
    grep -q -- '--name 10-tf-ado-deploy-infra' "$az_log"
    grep -q -- '--name 20-deploy-model-training-pipeline' "$az_log"
    test "$(grep -n -- '--name 00-dev-platform-bootstrap' "$az_log" | cut -d: -f1)" \
      -lt "$(grep -n -- '--name 10-tf-ado-deploy-infra' "$az_log" | cut -d: -f1)"
    test "$(grep -n -- '--name 10-tf-ado-deploy-infra' "$az_log" | cut -d: -f1)" \
      -lt "$(grep -n -- '--name 20-deploy-model-training-pipeline' "$az_log" | cut -d: -f1)"
  else
    test "$(grep -c '^pipelines create ' "$az_log")" -eq 4
    grep -q -- '--name tf-ado-deploy-infra' "$az_log"
    grep -q -- '--name deploy-model-training-pipeline' "$az_log"
    if grep -q -- '--name 00-' "$az_log" || grep -q -- '--name 10-' "$az_log" || grep -q -- '--name 20-' "$az_log"; then
      echo "Public pipeline names must remain unprefixed." >&2
      exit 1
    fi
  fi
  test -d "$target_dir"
}

run_generation public
run_generation private
run_pipeline_registration_test public
run_pipeline_registration_test private

printf 'Factory generation tests passed.\n'
