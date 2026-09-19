#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import shutil
import tempfile
import unicodedata
from pathlib import Path

ENVIRONMENTS = ("dev", "test", "prod")
REQUIRED_PRIVATE_DNS_ZONES = {
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.dfs.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.azurecr.io",
    "privatelink.api.azureml.ms",
    "privatelink.notebooks.azure.net",
}
AZURE_RESOURCE_ID_PATTERN = re.compile(
    r"^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/"
    r"Microsoft\.Network/(?P<type>virtualNetworks|privateDnsZones)/(?P<name>[^/]+)$",
    re.IGNORECASE,
)
RFC1918_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)


def replace_exact(path: Path, old: str, new: str, count: int = 1) -> None:
    content = path.read_text(encoding="utf-8")
    actual = content.count(old)
    if actual != count:
        raise SystemExit(
            f"{path}: expected {count} occurrence(s) of {old!r}, found {actual}"
        )
    path.write_text(content.replace(old, new), encoding="utf-8")


def replace_first_line(path: Path, value: str) -> None:
    content = path.read_text(encoding="utf-8")
    _, separator, remainder = content.partition("\n")
    if not separator or not content.startswith("name: "):
        raise SystemExit(f"{path}: expected a workflow name on the first line")
    path.write_text(f"name: {value}\n{remainder}", encoding="utf-8")


def yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def bicep_string(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def parse_shared_zone_mapping(value: str) -> dict[str, str]:
    try:
        mapping = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ValueError(f"shared private DNS zone map is not valid JSON: {exc}") from exc
    if not isinstance(mapping, dict):
        raise ValueError("shared private DNS zone map must be a JSON object")
    for zone_name, resource_id in mapping.items():
        match = (
            AZURE_RESOURCE_ID_PATTERN.fullmatch(resource_id)
            if isinstance(resource_id, str)
            else None
        )
        if zone_name not in REQUIRED_PRIVATE_DNS_ZONES:
            raise ValueError(f"unsupported shared private DNS zone: {zone_name!r}")
        if (
            not match
            or match.group("type").casefold() != "privatednszones"
            or match.group("name").casefold() != zone_name.casefold()
        ):
            raise ValueError(f"invalid shared private DNS zone mapping for {zone_name}")
    return mapping


def validate_dns_configuration(
    runner_hub_vnet_resource_id: str, shared_zone_mapping: dict[str, str]
) -> None:
    if runner_hub_vnet_resource_id:
        match = AZURE_RESOURCE_ID_PATTERN.fullmatch(runner_hub_vnet_resource_id)
        if not match or match.group("type").casefold() != "virtualnetworks":
            raise ValueError("runner hub VNet resource ID is invalid")
    elif shared_zone_mapping:
        raise ValueError(
            "shared private DNS zone IDs require runner_hub_vnet_resource_id"
        )


def render_config(
    project_dir: Path,
    environment: str,
    environment_name: str,
    workload_name: str,
    namespace: str,
    network_cidrs: dict[str, str],
    runner_hub_vnet_resource_id: str,
    shared_private_dns_zone_resource_ids: dict[str, str],
) -> None:
    path = project_dir / f"config-infra-{environment}.yml"
    replace_exact(
        path,
        f"environment: {environment}\n",
        (
            f"environment: {environment}\n"
            f"environment_name: {yaml_string(environment_name)}\n"
            f"workload_name: {yaml_string(workload_name)}\n"
        ),
    )
    content = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"^namespace:\s*\S+\s*$",
        f"namespace: {namespace}",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one namespace setting")
    path.write_text(updated, encoding="utf-8")
    content = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'^runner_hub_vnet_resource_id:\s*.*$',
        f"runner_hub_vnet_resource_id: {yaml_string(runner_hub_vnet_resource_id)}",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"{path}: expected one runner hub VNet setting")
    path.write_text(updated, encoding="utf-8")
    shared_zones_json = json.dumps(
        shared_private_dns_zone_resource_ids, separators=(",", ":"), sort_keys=True
    )
    content = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'^shared_private_dns_zone_resource_ids:\s*.*$',
        f"shared_private_dns_zone_resource_ids: {yaml_string(shared_zones_json)}",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"{path}: expected one shared private DNS zone map")
    path.write_text(updated, encoding="utf-8")
    replacements = {
        "vnet_address_prefix": network_cidrs["vnet"],
        "default_subnet_prefix": network_cidrs["default"],
        "compute_subnet_prefix": network_cidrs["compute"],
        "private_endpoint_subnet_prefix": network_cidrs["private_endpoint"],
        "bastion_subnet_prefix": network_cidrs["bastion"],
        "administration_subnet_prefix": network_cidrs["administration"],
    }
    for key, value in replacements.items():
        content = path.read_text(encoding="utf-8")
        updated, count = re.subn(
            rf"^{re.escape(key)}:\s*\S+\s*$",
            f"{key}: {value}",
            content,
            count=1,
            flags=re.MULTILINE,
        )
        if count != 1:
            raise SystemExit(f"{path}: expected exactly one {key} setting")
        path.write_text(updated, encoding="utf-8")


def derive_network_cidrs(value: str) -> dict[str, str]:
    try:
        network = ipaddress.ip_network(value, strict=True)
    except ValueError as exc:
        raise SystemExit(f"invalid workload VNet CIDR {value!r}: {exc}") from exc
    if not isinstance(network, ipaddress.IPv4Network):
        raise SystemExit("workload VNet CIDR must be IPv4")
    if not any(network.subnet_of(parent) for parent in RFC1918_NETWORKS):
        raise SystemExit("workload VNet CIDR must be contained in RFC1918 space")
    if network.prefixlen > 21:
        raise SystemExit(
            "workload VNet CIDR must be /21 or larger to derive isolated workload subnets"
        )
    subnets = list(network.subnets(new_prefix=24))
    return {
        "vnet": str(network),
        "default": str(subnets[0]),
        "compute": str(subnets[1]),
        "private_endpoint": str(subnets[2]),
        "bastion": str(next(subnets[3].subnets(new_prefix=26))),
        "administration": str(next(subnets[4].subnets(new_prefix=27))),
    }


def validate_workload_name(value: str) -> None:
    if not value.strip():
        raise SystemExit("workload name must contain a non-whitespace character")
    if any(unicodedata.category(character).startswith("C") for character in value):
        raise SystemExit("workload name must not contain control characters")
    if len(value) > 256:
        raise SystemExit("workload name exceeds the Azure tag value limit of 256 characters")


def validate_environment_names(environment_names: dict[str, str]) -> None:
    normalized = {}
    for environment, value in environment_names.items():
        if not value or any(unicodedata.category(character).startswith("C") for character in value):
            raise SystemExit(
                f"{environment} environment name must not contain control characters"
            )
        if len(value) > 255:
            raise SystemExit(
                f"{environment} environment name exceeds GitHub's 255-character limit"
            )
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._ -]{0,254}", value):
            raise SystemExit(
                f"{environment} environment name must use only letters, digits, "
                "spaces, periods, underscores, and hyphens"
            )
        identity = unicodedata.normalize("NFKC", value).casefold()
        if identity in normalized:
            raise SystemExit(
                "GitHub Environment names must be unique after Unicode and case "
                f"normalization: {normalized[identity]!r} and {value!r}"
            )
        normalized[identity] = value


def environment_selector(environment_names: dict[str, str], pull_request: bool) -> str:
    selected = (
        "${{ github.event_name == 'pull_request' && '"
        + environment_names["dev"]
        + "' || inputs.environment }}"
        if pull_request
        else "${{ inputs.environment }}"
    )
    cases = "\n".join(
        f"            {yaml_string(environment_names[key])}) environment={key} ;;"
        for key in ENVIRONMENTS
    )
    return (
        "      - id: select\n"
        "        env:\n"
        f"          SELECTED_ENVIRONMENT: {selected}\n"
        "        run: |\n"
        '          case "$SELECTED_ENVIRONMENT" in\n'
        f"{cases}\n"
        '            *) echo "Unsupported environment: $SELECTED_ENVIRONMENT" >&2; exit 1 ;;\n'
        "          esac\n"
        '          echo "environment=$environment" >> "$GITHUB_OUTPUT"\n'
    )


def render_workflow_header(
    path: Path,
    workload_name: str,
    environment_names: dict[str, str],
    suffix: str,
) -> None:
    replace_first_line(path, yaml_string(f"{workload_name} - {suffix}"))
    replace_exact(
        path,
        "description: GitHub Environment and configuration to target",
        f"description: {yaml_string(workload_name + ' environment to target')}",
    )
    replace_exact(
        path, "default: dev", f"default: {yaml_string(environment_names['dev'])}"
    )
    replace_exact(
        path,
        "options: [dev, test, prod]",
        "options: ["
        + ", ".join(yaml_string(environment_names[key]) for key in ENVIRONMENTS)
        + "]",
    )


def render_github_workflows(
    project_dir: Path,
    workload_name: str,
    namespace: str,
    environment_names: dict[str, str],
) -> None:
    workflow_dir = project_dir / ".github" / "workflows"
    workflow_specs = {
        "deploy-batch-endpoint.yml": "Deploy, invoke, and test batch endpoint",
        "deploy-infrastructure.yml": "Deploy infrastructure",
        "deploy-online-endpoint.yml": "Deploy and test online endpoint",
        "train-register-model.yml": "Train and register model",
    }
    for name, suffix in workflow_specs.items():
        render_workflow_header(
            workflow_dir / name, workload_name, environment_names, suffix
        )

    simple_selector = environment_selector(environment_names, pull_request=False)
    for name in (
        "deploy-batch-endpoint.yml",
        "deploy-online-endpoint.yml",
        "train-register-model.yml",
    ):
        path = workflow_dir / name
        replace_exact(
            path,
            (
                "      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683\n"
                "      - id: config\n"
                "        run: python3 mlops/scripts/export_config.py "
                "config-infra-${{ inputs.environment }}.yml\n"
            ),
            (
                "      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683\n"
                f"{simple_selector}"
                "      - id: config\n"
                "        run: python3 mlops/scripts/export_config.py "
                "config-infra-${{ steps.select.outputs.environment }}.yml\n"
            ),
        )

    for name in ("deploy-batch-endpoint.yml", "train-register-model.yml"):
        path = workflow_dir / name
        replace_exact(
            path,
            "      runner: ${{ steps.config.outputs.runner }}\n",
            (
                "      runner: ${{ steps.config.outputs.runner }}\n"
                "      environment_name: ${{ steps.config.outputs.environment_name }}\n"
            ),
        )
        replace_exact(
            path,
            "      environment: ${{ inputs.environment }}\n",
            "      environment: ${{ needs.config.outputs.environment_name }}\n",
        )

    online_path = workflow_dir / "deploy-online-endpoint.yml"
    replace_exact(
        online_path,
        "      environment_name: ${{ steps.config.outputs.online_environment_name }}\n",
        (
            "      online_environment_name: "
            "${{ steps.config.outputs.online_environment_name }}\n"
        ),
    )
    replace_exact(
        online_path,
        "${{ needs.config.outputs.environment_name }}",
        "${{ needs.config.outputs.online_environment_name }}",
        count=2,
    )

    infrastructure_path = workflow_dir / "deploy-infrastructure.yml"
    replace_exact(
        infrastructure_path,
        "      environment: ${{ steps.select.outputs.environment }}\n",
        (
            "      environment: ${{ steps.select.outputs.environment }}\n"
            "      environment_name: ${{ steps.select.outputs.environment_name }}\n"
        ),
    )
    replace_exact(
        infrastructure_path,
        (
            "      - id: select\n"
            "        env:\n"
            "          SELECTED_ENVIRONMENT: "
            "${{ github.event_name == 'pull_request' && 'dev' || inputs.environment }}\n"
            '        run: echo "environment=$SELECTED_ENVIRONMENT" >> "$GITHUB_OUTPUT"\n'
        ),
        (
            environment_selector(environment_names, pull_request=True)
            + '          echo "environment_name=$SELECTED_ENVIRONMENT" >> "$GITHUB_OUTPUT"\n'
        ),
    )
    replace_exact(
        infrastructure_path,
        "    environment: ${{ needs.config.outputs.environment }}\n",
        "    environment: ${{ needs.config.outputs.environment_name }}\n",
        count=2,
    )
    for path in workflow_specs:
        workflow_path = workflow_dir / path
        content = workflow_path.read_text(encoding="utf-8")
        content = content.replace("data/taxi-batch.csv", f"data/{namespace}-batch.csv")
        content = content.replace("data/taxi-request.json", f"data/{namespace}-request.json")
        workflow_path.write_text(content, encoding="utf-8")


def render_project(
    project_dir: Path,
    workload_name: str,
    namespace: str,
    environment_names: dict[str, str],
    environment_vnet_cidrs: dict[str, str],
    runner_hub_vnet_resource_ids: dict[str, str],
    shared_private_dns_zone_resource_ids: dict[str, dict[str, str]],
    orchestration: str,
    ado_pipeline: Path,
) -> None:
    validate_environment_networks(environment_vnet_cidrs)
    with tempfile.TemporaryDirectory(
        prefix=f".{project_dir.name}-render-", dir=project_dir.parent
    ) as temporary_directory:
        staged_project = Path(temporary_directory) / project_dir.name
        shutil.copytree(
            project_dir,
            staged_project,
            copy_function=shutil.copy2,
            ignore=shutil.ignore_patterns(".git"),
        )
        _render_project_in_place(
            staged_project,
            workload_name,
            namespace,
            environment_names,
            environment_vnet_cidrs,
            runner_hub_vnet_resource_ids,
            shared_private_dns_zone_resource_ids,
            orchestration,
            ado_pipeline,
        )
        synchronize_project(staged_project, project_dir)


def project_files(root: Path) -> dict[Path, Path]:
    return {
        path.relative_to(root): path
        for path in root.rglob("*")
        if path.is_file() and ".git" not in path.relative_to(root).parts
    }


def _atomic_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        prefix=f".{destination.name}.",
        dir=destination.parent,
        delete=False,
    ) as temporary_file:
        temporary_path = Path(temporary_file.name)
    try:
        shutil.copy2(source, temporary_path)
        temporary_path.replace(destination)
    finally:
        temporary_path.unlink(missing_ok=True)


def synchronize_project(
    staged_project: Path,
    project_dir: Path,
    write_file=_atomic_copy,
) -> None:
    original_files = project_files(project_dir)
    staged_files = project_files(staged_project)
    changed_paths = sorted(
        relative_path
        for relative_path, staged_path in staged_files.items()
        if relative_path not in original_files
        or staged_path.read_bytes() != original_files[relative_path].read_bytes()
        or staged_path.stat().st_mode != original_files[relative_path].stat().st_mode
    )
    deleted_paths = sorted(set(original_files) - set(staged_files))
    affected_paths = changed_paths + deleted_paths
    if not affected_paths:
        return

    with tempfile.TemporaryDirectory(
        prefix=f".{project_dir.name}-backup-", dir=project_dir.parent
    ) as backup_directory:
        backup_root = Path(backup_directory)
        for relative_path in affected_paths:
            original_path = original_files.get(relative_path)
            if original_path is not None:
                backup_path = backup_root / relative_path
                backup_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original_path, backup_path)

        created_directories = []
        try:
            for relative_path in changed_paths:
                destination = project_dir / relative_path
                missing_parents = []
                parent = destination.parent
                while parent != project_dir and not parent.exists():
                    missing_parents.append(parent)
                    parent = parent.parent
                destination.parent.mkdir(parents=True, exist_ok=True)
                created_directories.extend(reversed(missing_parents))
                write_file(staged_files[relative_path], destination)
            for relative_path in deleted_paths:
                (project_dir / relative_path).unlink()
        except Exception:
            for relative_path in affected_paths:
                destination = project_dir / relative_path
                backup_path = backup_root / relative_path
                if backup_path.is_file():
                    _atomic_copy(backup_path, destination)
                else:
                    destination.unlink(missing_ok=True)
            for directory in reversed(created_directories):
                try:
                    directory.rmdir()
                except OSError:
                    pass
            raise


def validate_environment_networks(
    environment_vnet_cidrs: dict[str, str],
) -> None:
    networks = {}
    for environment in ENVIRONMENTS:
        value = environment_vnet_cidrs[environment]
        derive_network_cidrs(value)
        networks[environment] = ipaddress.ip_network(value, strict=True)
    for index, environment in enumerate(ENVIRONMENTS):
        for other_environment in ENVIRONMENTS[index + 1 :]:
                if networks[environment].overlaps(networks[other_environment]):
                    raise SystemExit(
                        "workload VNet CIDRs must not overlap: "
                        f"{environment}={networks[environment]} and "
                        f"{other_environment}={networks[other_environment]}"
                    )


def _render_project_in_place(
    project_dir: Path,
    workload_name: str,
    namespace: str,
    environment_names: dict[str, str],
    environment_vnet_cidrs: dict[str, str],
    runner_hub_vnet_resource_ids: dict[str, str],
    shared_private_dns_zone_resource_ids: dict[str, dict[str, str]],
    orchestration: str,
    ado_pipeline: Path,
) -> None:
    for environment in ENVIRONMENTS:
        network_cidrs = derive_network_cidrs(environment_vnet_cidrs[environment])
        render_config(
            project_dir,
            environment,
            environment_names[environment],
            workload_name,
            namespace,
            network_cidrs,
            runner_hub_vnet_resource_ids[environment],
            shared_private_dns_zone_resource_ids[environment],
        )

    bicep_path = project_dir / "infrastructure" / "main.bicep"
    replace_exact(
        bicep_path,
        "param location string = 'eastus2'\n",
        (
            "param location string = 'eastus2'\n"
            f"param workloadDisplayName string = {bicep_string(workload_name)}\n"
        ),
    )
    replace_exact(bicep_path, "  Project: prefix\n", "  Project: workloadDisplayName\n")
    replace_exact(bicep_path, "  Name: prefix\n", "  Name: workloadDisplayName\n")

    renderer_path = project_dir / "mlops" / "scripts" / "render_bicep_parameters.py"
    replace_exact(
        renderer_path,
        '    "location": "location",\n',
        '    "location": "location",\n    "workload_name": "workloadDisplayName",\n',
    )
    replace_exact(
        renderer_path,
        (
            "    canonical_uuid = re.compile(\n"
            '        r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",\n'
            "        re.IGNORECASE,\n"
            "    )\n"
        ),
        (
            "    canonical_uuid = re.compile(\n"
            '        r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"\n'
            "    )\n"
        ),
    )
    replace_exact(
        renderer_path,
        "AZURE_PRINCIPAL_OBJECT_ID must be a canonical UUID",
        "AZURE_PRINCIPAL_OBJECT_ID must be a lowercase canonical UUID",
    )
    replace_exact(
        renderer_path,
        "DEV_JUMPBOX_LOGIN_GROUP_ID must be empty or a canonical UUID",
        "DEV_JUMPBOX_LOGIN_GROUP_ID must be empty or a lowercase canonical UUID",
    )

    validator_path = project_dir / "mlops" / "scripts" / "validate_project.py"
    replace_exact(
        validator_path,
        '    "environment",\n',
        '    "environment",\n    "environment_name",\n    "workload_name",\n',
    )
    validator_content = validator_path.read_text(encoding="utf-8")
    for suffix in ("batch.csv", "data.csv", "request.json"):
        validator_content = validator_content.replace(
            f'"taxi-{suffix}"', f'"{namespace}-{suffix}"'
        )
    validator_path.write_text(validator_content, encoding="utf-8")
    replace_exact(
        validator_path,
        (
            '            and "config-infra-${{ needs.config.outputs.environment }}.yml"\n'
            "            not in content\n"
        ),
        (
            '            and "config-infra-${{ needs.config.outputs.environment }}.yml"\n'
            "            not in content\n"
            '            and "config-infra-${{ steps.select.outputs.environment }}.yml"\n'
            "            not in content\n"
        ),
    )

    job_path = project_dir / "mlops" / "azureml" / "train" / "job.yml"
    replace_exact(
        job_path,
        "display_name: classical-training",
        f"display_name: {yaml_string(workload_name + ' Training')}",
    )
    replace_exact(
        job_path,
        "experiment_name: classical-training",
        f"experiment_name: {namespace}-training",
    )
    replace_exact(job_path, "path: ../../../data/taxi-data.csv", f"path: ../../../data/{namespace}-data.csv")
    replace_exact(job_path, "table_name: taximonitoring", f"table_name: {namespace}monitoring")

    for suffix in ("batch.csv", "data.csv", "request.json"):
        source = project_dir / "data" / f"taxi-{suffix}"
        destination = project_dir / "data" / f"{namespace}-{suffix}"
        if not source.is_file() or destination.exists():
            raise SystemExit(f"cannot rename {source} to {destination}")
        source.rename(destination)

    if orchestration == "github-actions":
        render_github_workflows(
            project_dir, workload_name, namespace, environment_names
        )
    else:
        pipeline_dir = project_dir / "mlops" / "devops-pipelines"
        pipeline_dir.mkdir(parents=True, exist_ok=True)
        (pipeline_dir / "deploy-infrastructure-pipeline.yml").write_bytes(
            ado_pipeline.read_bytes()
        )
        online_path = pipeline_dir / "deploy-online-endpoint-pipeline.yml"
        replace_exact(
            online_path,
            "REQUIRED_PRIVATE_SELF_HOSTED_POOL|Azure\\ Pipelines)",
            "REQUIRED_PRIVATE_SELF_HOSTED_POOL|Azure\\ Pipelines|Default)",
        )
        replace_exact(
            online_path,
            "--request-file data/taxi-request.json",
            f"--request-file data/{namespace}-request.json",
            count=2,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", type=Path, required=True)
    parser.add_argument("--workload-name", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--dev-environment-name", required=True)
    parser.add_argument("--test-environment-name", required=True)
    parser.add_argument("--prod-environment-name", required=True)
    parser.add_argument("--dev-vnet-cidr", required=True)
    parser.add_argument("--test-vnet-cidr", required=True)
    parser.add_argument("--prod-vnet-cidr", required=True)
    parser.add_argument("--dev-runner-hub-vnet-resource-id", default="")
    parser.add_argument("--test-runner-hub-vnet-resource-id", default="")
    parser.add_argument("--prod-runner-hub-vnet-resource-id", default="")
    parser.add_argument(
        "--dev-shared-private-dns-zone-resource-ids", default="{}"
    )
    parser.add_argument(
        "--test-shared-private-dns-zone-resource-ids", default="{}"
    )
    parser.add_argument(
        "--prod-shared-private-dns-zone-resource-ids", default="{}"
    )
    parser.add_argument(
        "--orchestration",
        choices=("github-actions", "azure-devops"),
        required=True,
    )
    parser.add_argument("--ado-infrastructure-pipeline", type=Path, required=True)
    args = parser.parse_args()

    environment_names = {
        "dev": args.dev_environment_name,
        "test": args.test_environment_name,
        "prod": args.prod_environment_name,
    }
    validate_workload_name(args.workload_name)
    validate_environment_names(environment_names)
    environment_vnet_cidrs = {
        "dev": args.dev_vnet_cidr,
        "test": args.test_vnet_cidr,
        "prod": args.prod_vnet_cidr,
    }
    runner_hub_vnet_resource_ids = {
        "dev": args.dev_runner_hub_vnet_resource_id,
        "test": args.test_runner_hub_vnet_resource_id,
        "prod": args.prod_runner_hub_vnet_resource_id,
    }
    shared_private_dns_zone_resource_ids = {}
    for environment in ENVIRONMENTS:
        try:
            mapping = parse_shared_zone_mapping(
                getattr(
                    args,
                    f"{environment}_shared_private_dns_zone_resource_ids",
                )
            )
            validate_dns_configuration(
                runner_hub_vnet_resource_ids[environment], mapping
            )
        except ValueError as exc:
            raise SystemExit(f"{environment}: {exc}") from exc
        shared_private_dns_zone_resource_ids[environment] = mapping
    render_project(
        args.project_dir.resolve(),
        args.workload_name,
        args.namespace,
        environment_names,
        environment_vnet_cidrs,
        runner_hub_vnet_resource_ids,
        shared_private_dns_zone_resource_ids,
        args.orchestration,
        args.ado_infrastructure_pipeline.resolve(),
    )


if __name__ == "__main__":
    main()
