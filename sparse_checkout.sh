infrastructure_version=${infrastructure_version:-terraform}   #options: terraform / bicep
project_type=${project_type:-classical}   #options: classical / cv / nlp
mlops_version=${mlops_version:-aml-cli-v2}   #options: aml-cli-v2 / python-sdk-v1 / python-sdk-v2 / rai-aml-cli-v2
orchestration=${orchestration:-azure-devops}   #options: github-actions / azure-devops
git_folder_location=${git_folder_location:-'<local path>'}   #replace with the local root folder location where you want to create the project folder
project_name=${project_name:-Mlops-Test}   #replace with your project name
workload_name=${workload_name:-}   #human-readable workload display name
workload_namespace=${workload_namespace:-}   #lowercase Azure-safe workload namespace
dev_vnet_cidr=${dev_vnet_cidr:-}   #non-overlapping private Dev workload VNet CIDR
test_vnet_cidr=${test_vnet_cidr:-}   #non-overlapping private Test workload VNet CIDR
prod_vnet_cidr=${prod_vnet_cidr:-}   #non-overlapping private Prod workload VNet CIDR
dev_environment_name=${dev_environment_name:-Dev}
test_environment_name=${test_environment_name:-Test}
prod_environment_name=${prod_environment_name:-Prod}
github_org_name=${github_org_name:-orgname}   #replace with your github org name
project_template_github_url=${project_template_github_url:-https://github.com/pgabriel-01/mlops-project-template}   #replace with the url for the project template for your organization, or use the validated default
project_template_git_ref=${project_template_git_ref:-60fd56455926b2e1391334cc7b292a84d273b3c4}   #branch, tag, or immutable commit SHA
mlops_templates_repository=${mlops_templates_repository:-pgabriel-01/mlops-templates}   #owner/repository used by reusable GitHub workflows
mlops_templates_git_ref=${mlops_templates_git_ref:-70b7ce23a9cb905b528fc4cbc1a375eabf893a0c}   #use an immutable commit SHA for repeatable generation
create_github_repository=${create_github_repository:-true}   #set to false for local generation and validation

set -euo pipefail
generator_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
customize_managed_online=false

case "$infrastructure_version" in terraform|bicep) ;; *) echo "Unsupported infrastructure_version: $infrastructure_version" >&2; exit 1 ;; esac
case "$project_type" in classical|cv|nlp) ;; *) echo "Unsupported project_type: $project_type" >&2; exit 1 ;; esac
case "$mlops_version" in aml-cli-v2|python-sdk-v1|python-sdk-v2|rai-aml-cli-v2) ;; *) echo "Unsupported mlops_version: $mlops_version" >&2; exit 1 ;; esac
case "$orchestration" in github-actions|azure-devops) ;; *) echo "Unsupported orchestration: $orchestration" >&2; exit 1 ;; esac
case "$create_github_repository" in true|false) ;; *) echo "create_github_repository must be true or false" >&2; exit 1 ;; esac

if [ "$infrastructure_version" = bicep ] &&
  [ "$project_type" = classical ] &&
  [ "$mlops_version" = python-sdk-v2 ]; then
  customize_managed_online=true

  if [ -z "$workload_name" ]; then
    echo "workload_name is required for the classical Python SDK v2 Bicep pattern" >&2
    exit 1
  fi

  if [[ "$workload_name" == *$'\n'* ]]; then
    echo "workload_name must be a single-line value" >&2
    exit 1
  fi

  if ! [[ "$workload_namespace" =~ ^[a-z][a-z0-9]{1,15}$ ]]; then
    echo "workload_namespace must be 2-16 lowercase alphanumeric characters and start with a letter" >&2
    exit 1
  fi

  for cidr_name in dev_vnet_cidr test_vnet_cidr prod_vnet_cidr; do
    if [ -z "${!cidr_name}" ]; then
      echo "$cidr_name is required and must not overlap any peered VNet" >&2
      exit 1
    fi
  done
fi

if ! [[ "$mlops_templates_repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "mlops_templates_repository must use owner/repository format" >&2
  exit 1
fi

if [ "$git_folder_location" = '<local path>' ]; then
  echo "Set git_folder_location before running the generator." >&2
  exit 1
fi

mkdir -p "$git_folder_location"
cd "$git_folder_location"

if [ -e "$project_name" ]; then
  echo "Destination already exists: $git_folder_location/$project_name" >&2
  exit 1
fi

git init -b main "$project_name"
cd "$project_name"
git remote add origin "$project_template_github_url"
git sparse-checkout init --cone
sparse_paths=("infrastructure/$infrastructure_version" "$project_type/$mlops_version")
if [ "$orchestration" = "github-actions" ]; then
  sparse_paths+=(".github/workflows")
fi
git sparse-checkout set "${sparse_paths[@]}"
git fetch --depth 1 origin "$project_template_git_ref"
git checkout --detach FETCH_HEAD
project_template_commit=$(git rev-parse HEAD)
selected_project_path="$project_type/$mlops_version"

# Move files to appropiate level
if [ -d "$selected_project_path/data-science" ]; then
  mv "$selected_project_path/data-science" data-science
else
  echo "Warning: data-science directory not found"
fi

if [ -d "$selected_project_path/mlops" ]; then
  mv "$selected_project_path/mlops" mlops
else
  echo "Warning: mlops directory not found"
fi

if [ -d "$selected_project_path/data" ]; then
  mv "$selected_project_path/data" data
else
  echo "Warning: data directory not found"
fi

if [ -d "$selected_project_path/runner-bootstrap" ]; then
  mv "$selected_project_path/runner-bootstrap" runner-bootstrap
fi

if find "$selected_project_path" -maxdepth 1 -type f -name 'config-infra-*.yml' -print -quit | grep -q .; then
  rm -f config-infra-*.yml
  find "$selected_project_path" -maxdepth 1 -type f -name 'config-infra-*.yml' \
    -exec mv {} . \;
fi

if [ -f "$selected_project_path/README.md" ]; then
  mv "$selected_project_path/README.md" README.md
fi

rm -rf "$project_type"

mv "infrastructure/$infrastructure_version" "$infrastructure_version"
rm -rf infrastructure
mv "$infrastructure_version" infrastructure

if [[ "$orchestration" == "github-actions" ]]
then
  echo "github-actions"
  rm -rf mlops/devops-pipelines
  if [ -d "mlops/github-actions" ]; then
    rm -rf .github/workflows
    mkdir -p .github/workflows/
    find mlops/github-actions -mindepth 1 -maxdepth 1 -exec mv {} .github/workflows/ \;
  else
    echo "Warning: mlops/github-actions directory not found"
    mkdir -p .github/workflows/
  fi
  rm -rf mlops/github-actions
  if [ ! -f ".github/workflows/deploy-infrastructure.yml" ]; then
    if [ -d "infrastructure/github-actions" ]; then
      find infrastructure/github-actions -mindepth 1 -maxdepth 1 -exec mv {} .github/workflows/ \;
    fi
    if [ -d "infrastructure/pipelines" ]; then
      find infrastructure/pipelines -maxdepth 1 -type f -name '*-gha-*' -exec mv {} .github/workflows/ \;
    fi
  fi
  rm -rf infrastructure/devops-pipelines
  rm -rf infrastructure/github-actions
  rm -rf infrastructure/pipelines

  while IFS= read -r file; do
    sed -i.bak \
      -e "s|__MLOPS_TEMPLATES_REPOSITORY__|$mlops_templates_repository|g" \
      -e "s|__MLOPS_TEMPLATES_REF__|$mlops_templates_git_ref|g" \
      "$file"
    rm "$file.bak"
  done < <(grep -rl -e '__MLOPS_TEMPLATES_REPOSITORY__' -e '__MLOPS_TEMPLATES_REF__' . --exclude-dir=.git || true)

  if grep -R -q -e '__MLOPS_TEMPLATES_REPOSITORY__' -e '__MLOPS_TEMPLATES_REF__' . --exclude-dir=.git; then
    echo "Unresolved mlops-templates workflow reference placeholders remain." >&2
    exit 1
  fi
fi

if [[ "$orchestration" == "azure-devops" ]]
then
  echo "azure-devops"
  rm -rf mlops/github-actions
  if [ "$customize_managed_online" = true ]; then
    rm -rf infrastructure/devops-pipelines
    rm -rf infrastructure/pipelines
  elif [ -d "infrastructure/devops-pipelines" ]; then
    find infrastructure/devops-pipelines -mindepth 1 -maxdepth 1 -exec mv {} infrastructure/ \;
    rm -rf infrastructure/devops-pipelines
  fi
  rm -rf infrastructure/github-actions
fi

if [ "$customize_managed_online" = true ]; then
  python3 "$generator_root/scripts/render_generated_project.py" \
    --project-dir "$PWD" \
    --workload-name "$workload_name" \
    --namespace "$workload_namespace" \
    --dev-environment-name "$dev_environment_name" \
    --test-environment-name "$test_environment_name" \
    --prod-environment-name "$prod_environment_name" \
    --dev-vnet-cidr "$dev_vnet_cidr" \
    --test-vnet-cidr "$test_vnet_cidr" \
    --prod-vnet-cidr "$prod_vnet_cidr" \
    --orchestration "$orchestration" \
    --ado-infrastructure-pipeline \
      "$generator_root/templates/azure-devops/deploy-infrastructure-pipeline.yml"
fi

echo "Reinitializing git repository..."
rm -rf .git
git init -b main

python3 - \
  "$customize_managed_online" \
  "$workload_name" \
  "$workload_namespace" \
  "$dev_environment_name" \
  "$test_environment_name" \
  "$prod_environment_name" \
  "$dev_vnet_cidr" \
  "$test_vnet_cidr" \
  "$prod_vnet_cidr" \
  "$infrastructure_version" \
  "$project_type" \
  "$mlops_version" \
  "$orchestration" \
  "$project_template_github_url" \
  "$project_template_git_ref" \
  "$project_template_commit" \
  "$mlops_templates_repository" \
  "$mlops_templates_git_ref" <<'PY'
import json
import sys
from pathlib import Path

(
    customize,
    workload_name,
    workload_namespace,
    dev_environment_name,
    test_environment_name,
    prod_environment_name,
    dev_vnet_cidr,
    test_vnet_cidr,
    prod_vnet_cidr,
    infrastructure_version,
    project_type,
    mlops_version,
    orchestration,
    project_template_github_url,
    project_template_git_ref,
    project_template_commit,
    mlops_templates_repository,
    mlops_templates_git_ref,
) = sys.argv[1:]

payload = {
    "infrastructure_version": infrastructure_version,
    "project_type": project_type,
    "mlops_version": mlops_version,
    "orchestration": orchestration,
    "project_template_github_url": project_template_github_url,
    "project_template_git_ref": project_template_git_ref,
    "project_template_commit": project_template_commit,
    "mlops_templates_repository": mlops_templates_repository,
    "mlops_templates_git_ref": mlops_templates_git_ref,
}
if customize == "true":
    payload = {
        "workload_name": workload_name,
        "workload_namespace": workload_namespace,
        "environment_names": {
            "dev": dev_environment_name,
            "test": test_environment_name,
            "prod": prod_environment_name,
        },
        "environment_vnet_cidrs": {
            "dev": dev_vnet_cidr,
            "test": test_vnet_cidr,
            "prod": prod_vnet_cidr,
        },
        **payload,
    }
Path(".mlops-generation.json").write_text(
    json.dumps(payload, indent=2) + "\n", encoding="utf-8"
)
PY

git add .
git commit -m 'initial commit'

if [ "$create_github_repository" = true ]; then
  echo "Creating GitHub repository..."
  gh repo create "$github_org_name/$project_name" --private --confirm

  echo "Pushing to GitHub..."
  git remote add origin "git@github.com:$github_org_name/$project_name.git"
  git push --set-upstream origin main
else
  echo "Created local project at $git_folder_location/$project_name"
fi
