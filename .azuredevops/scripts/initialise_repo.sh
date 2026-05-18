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

echo "=== initialise_repo.sh ==="
echo "repo_name=${repo_name}"
echo "project_type=${project_type}"
echo "mlops_version=${mlops_version}"
echo "template_repo=${template_repo}"
echo "infrastructure_version=${infrastructure_version}"
echo "cwd=$(pwd)"
ls -la

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

git config --global user.email "hosted.agent@dev.azure.com"
git config --global user.name "Azure Pipeline"

mkdir -p files_to_keep files_to_delete

# Portable replacement for `cp --parents -r` (GNU coreutils only; not
# available in macOS BSD cp or some Windows Git Bash builds). Preserves the
# leading path component the rest of the script expects.
mkdir -p "files_to_keep/infrastructure"
cp -r "${template_repo}/infrastructure/${infrastructure_version}" "files_to_keep/infrastructure/"
mkdir -p "files_to_keep/${project_type}"
cp -r "${template_repo}/${project_type}/${mlops_version}" "files_to_keep/${project_type}/"
cp "${template_repo}/config-infra-dev.yml" files_to_keep/
cp "${template_repo}/config-infra-prod.yml" files_to_keep/

# Best-effort cleanup of the template checkout; not fatal if already empty.
mv "${template_repo}"/* files_to_delete/ 2>/dev/null || true

cd "${repo_name}"
git checkout -b main
cd ..

# Clear the target repo working tree while preserving .git so we can commit.
find "${repo_name}" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
mv files_to_keep/* "${repo_name}/"
cd "${repo_name}"

# Move files to appropriate level
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
