#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/mlops-v2-shared-dns.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

subscription_id=00000000-0000-0000-0000-000000000000
runner_hub_vnet_resource_id="/subscriptions/$subscription_id/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
shared_private_dns_zone_resource_ids=$(
  python3 - "$subscription_id" <<'PY'
import json
import sys

subscription_id = sys.argv[1]
zones = (
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.dfs.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.azurecr.io",
    "privatelink.api.azureml.ms",
    "privatelink.notebooks.azure.net",
)
print(
    json.dumps(
        {
            zone: (
                f"/subscriptions/{subscription_id}/resourceGroups/rg-dns/providers/"
                f"Microsoft.Network/privateDnsZones/{zone}"
            )
            for zone in zones
        },
        separators=(",", ":"),
        sort_keys=True,
    )
)
PY
)

for orchestration in github-actions azure-devops; do
  for copy in first second; do
    output_root="$temporary_root/$orchestration-$copy"
    mkdir -p "$output_root"
    infrastructure_version=bicep \
      project_type=classical \
      mlops_version=python-sdk-v2 \
      orchestration="$orchestration" \
      git_folder_location="$output_root" \
      project_name=generated \
      workload_name='Taxi Fare Prediction' \
      workload_namespace=taxifare \
      dev_vnet_cidr=10.242.0.0/16 \
      test_vnet_cidr=10.243.0.0/16 \
      prod_vnet_cidr=10.244.0.0/16 \
      dev_runner_hub_vnet_resource_id="$runner_hub_vnet_resource_id" \
      test_runner_hub_vnet_resource_id="$runner_hub_vnet_resource_id" \
      prod_runner_hub_vnet_resource_id="$runner_hub_vnet_resource_id" \
      dev_shared_private_dns_zone_resource_ids="$shared_private_dns_zone_resource_ids" \
      test_shared_private_dns_zone_resource_ids="$shared_private_dns_zone_resource_ids" \
      prod_shared_private_dns_zone_resource_ids="$shared_private_dns_zone_resource_ids" \
      create_github_repository=false \
      bash "$repository_root/sparse_checkout.sh"
    "$repository_root/scripts/validate_generated_project.sh" \
      "$output_root/generated"
  done

  first_project="$temporary_root/$orchestration-first/generated"
  second_project="$temporary_root/$orchestration-second/generated"
  diff -qr --exclude=.git "$first_project" "$second_project"
  first_tree=$(git -C "$first_project" rev-parse HEAD^{tree})
  second_tree=$(git -C "$second_project" rev-parse HEAD^{tree})
  if [ "$first_tree" != "$second_tree" ]; then
    echo "$orchestration generation tree mismatch: $first_tree != $second_tree" >&2
    exit 1
  fi
  echo "$orchestration generation tree: $first_tree"
done

unexpected_id_project="$temporary_root/github-actions-first/generated"
cat >>"$unexpected_id_project/config-infra-dev.yml" <<'EOF'
# unexpected_resource_id: /subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-unexpected/providers/Microsoft.Network/virtualNetworks/vnet-unexpected
EOF
if "$repository_root/scripts/validate_generated_project.sh" \
  "$unexpected_id_project" >/dev/null 2>&1; then
  echo "validator accepted an Azure resource ID outside approved config fields" >&2
  exit 1
fi
