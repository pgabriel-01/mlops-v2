from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "render_generated_project.py"
sys.path.insert(0, str(MODULE_PATH.parent))

SPEC = importlib.util.spec_from_file_location("render_generated_project", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class EnvironmentNameValidationTests(unittest.TestCase):
    def test_rejects_case_insensitive_collision(self) -> None:
        with self.assertRaisesRegex(SystemExit, "unique after Unicode and case"):
            MODULE.validate_environment_names(
                {"dev": "Dev", "test": "dev", "prod": "Prod"}
            )

    def test_rejects_non_ascii_environment_name(self) -> None:
        with self.assertRaisesRegex(SystemExit, "only letters"):
            MODULE.validate_environment_names(
                {"dev": "Ｄｅｖ", "test": "Dev", "prod": "Prod"}
            )

    def test_rejects_name_over_github_limit(self) -> None:
        with self.assertRaisesRegex(SystemExit, "255-character"):
            MODULE.validate_environment_names(
                {"dev": "D" * 256, "test": "Test", "prod": "Prod"}
            )

    def test_rejects_apostrophe(self) -> None:
        with self.assertRaisesRegex(SystemExit, "only letters"):
            MODULE.validate_environment_names(
                {"dev": "Dev's", "test": "Test", "prod": "Prod"}
            )

    def test_rejects_control_character(self) -> None:
        with self.assertRaisesRegex(SystemExit, "control characters"):
            MODULE.validate_environment_names(
                {"dev": "Dev\t", "test": "Test", "prod": "Prod"}
            )

    def test_accepts_distinct_environment_names(self) -> None:
        MODULE.validate_environment_names(
            {"dev": "Dev", "test": "Test", "prod": "Prod"}
        )


class WorkloadNameValidationTests(unittest.TestCase):
    def test_rejects_whitespace_only_name(self) -> None:
        with self.assertRaisesRegex(SystemExit, "non-whitespace"):
            MODULE.validate_workload_name("   ")

    def test_rejects_control_character(self) -> None:
        with self.assertRaisesRegex(SystemExit, "control characters"):
            MODULE.validate_workload_name("Taxi\tFare")

    def test_rejects_name_over_tag_limit(self) -> None:
        with self.assertRaisesRegex(SystemExit, "256"):
            MODULE.validate_workload_name("T" * 257)


class NetworkDerivationTests(unittest.TestCase):
    def test_derives_expected_subnets(self) -> None:
        self.assertEqual(
            MODULE.derive_network_cidrs("10.242.0.0/16"),
            {
                "vnet": "10.242.0.0/16",
                "default": "10.242.0.0/24",
                "compute": "10.242.1.0/24",
                "private_endpoint": "10.242.2.0/24",
                "bastion": "10.242.3.0/26",
                "administration": "10.242.4.0/27",
            },
        )

    def test_rejects_insufficient_parent(self) -> None:
        with self.assertRaisesRegex(SystemExit, "/21 or larger"):
            MODULE.derive_network_cidrs("10.242.0.0/24")

    def test_rejects_loopback_space(self) -> None:
        with self.assertRaisesRegex(SystemExit, "RFC1918"):
            MODULE.derive_network_cidrs("127.0.0.0/16")

    def test_rejects_link_local_space(self) -> None:
        with self.assertRaisesRegex(SystemExit, "RFC1918"):
            MODULE.derive_network_cidrs("169.254.0.0/16")

    def test_render_rejects_overlapping_environment_vnets(self) -> None:
        with self.assertRaisesRegex(SystemExit, "must not overlap"):
            MODULE.render_project(
                Path("/unused"),
                "Taxi Fare Prediction",
                "taxifare",
                {"dev": "Dev", "test": "Test", "prod": "Prod"},
                {
                    "dev": "10.242.0.0/16",
                    "test": "10.242.0.0/17",
                    "prod": "10.244.0.0/16",
                },
                {"dev": "", "test": "", "prod": ""},
                {"dev": {}, "test": {}, "prod": {}},
                "github-actions",
                Path("/unused/pipeline.yml"),
            )


class PrivateDnsValidationTests(unittest.TestCase):
    def test_accepts_authoritative_zone_mapping(self) -> None:
        runner_hub = (
            "/subscriptions/00000000-0000-0000-0000-000000000000/"
            "resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        )
        zone_id = (
            "/subscriptions/00000000-0000-0000-0000-000000000000/"
            "resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/"
            "privatelink.blob.core.windows.net"
        )
        mapping = MODULE.parse_shared_zone_mapping(
            '{"privatelink.blob.core.windows.net":"' + zone_id + '"}'
        )
        MODULE.validate_dns_configuration(runner_hub, mapping)

    def test_rejects_zone_without_runner_hub(self) -> None:
        zone_id = (
            "/subscriptions/00000000-0000-0000-0000-000000000000/"
            "resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/"
            "privatelink.blob.core.windows.net"
        )
        mapping = MODULE.parse_shared_zone_mapping(
            '{"privatelink.blob.core.windows.net":"' + zone_id + '"}'
        )
        with self.assertRaisesRegex(ValueError, "require runner_hub"):
            MODULE.validate_dns_configuration("", mapping)

    def test_rejects_zone_key_resource_id_mismatch(self) -> None:
        zone_id = (
            "/subscriptions/00000000-0000-0000-0000-000000000000/"
            "resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/"
            "privatelink.file.core.windows.net"
        )
        with self.assertRaisesRegex(ValueError, "invalid shared private DNS"):
            MODULE.parse_shared_zone_mapping(
                '{"privatelink.blob.core.windows.net":"' + zone_id + '"}'
            )

class AtomicRenderingTests(unittest.TestCase):
    def test_late_anchor_failure_does_not_mutate_project(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            project_dir = Path(temporary_directory) / "generated"
            project_dir.mkdir()
            original = {}
            for environment in ("dev", "test", "prod"):
                path = project_dir / f"config-infra-{environment}.yml"
                path.write_text(
                    (
                        f"environment: {environment}\n"
                        "namespace: mlops\n"
                        "runner_hub_vnet_resource_id: ''\n"
                        "shared_private_dns_zone_resource_ids: '{}'\n"
                        "vnet_address_prefix: 10.0.0.0/16\n"
                        "default_subnet_prefix: 10.0.0.0/24\n"
                        "compute_subnet_prefix: 10.0.1.0/24\n"
                        "private_endpoint_subnet_prefix: 10.0.2.0/24\n"
                        "bastion_subnet_prefix: 10.0.3.0/26\n"
                        "administration_subnet_prefix: 10.0.4.0/27\n"
                    ),
                    encoding="utf-8",
                )
                original[path.name] = path.read_bytes()

            with self.assertRaises(FileNotFoundError):
                MODULE.render_project(
                    project_dir,
                    "Taxi Fare Prediction",
                    "taxifare",
                    {"dev": "Dev", "test": "Test", "prod": "Prod"},
                    {
                        "dev": "10.242.0.0/16",
                        "test": "10.243.0.0/16",
                        "prod": "10.244.0.0/16",
                    },
                    {"dev": "", "test": "", "prod": ""},
                    {"dev": {}, "test": {}, "prod": {}},
                    "github-actions",
                    Path("/unused/pipeline.yml"),
                )

            for name, content in original.items():
                self.assertEqual((project_dir / name).read_bytes(), content)

    def test_forced_commit_failure_rolls_back_all_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            project_dir = root / "project"
            staged_dir = root / "staged"
            project_dir.mkdir()
            staged_dir.mkdir()
            (project_dir / "a.txt").write_text("original-a\n", encoding="utf-8")
            (project_dir / "b.txt").write_text("original-b\n", encoding="utf-8")
            (staged_dir / "a.txt").write_text("changed-a\n", encoding="utf-8")
            (staged_dir / "b.txt").write_text("changed-b\n", encoding="utf-8")
            (staged_dir / "new.txt").write_text("new\n", encoding="utf-8")
            before = {
                path.relative_to(project_dir): path.read_bytes()
                for path in project_dir.rglob("*")
                if path.is_file()
            }
            writes = 0

            def fail_second_write(source: Path, destination: Path) -> None:
                nonlocal writes
                writes += 1
                if writes == 2:
                    raise OSError("forced commit failure")
                MODULE._atomic_copy(source, destination)

            with self.assertRaisesRegex(OSError, "forced commit failure"):
                MODULE.synchronize_project(
                    staged_dir, project_dir, write_file=fail_second_write
                )

            after = {
                path.relative_to(project_dir): path.read_bytes()
                for path in project_dir.rglob("*")
                if path.is_file()
            }
            self.assertEqual(after, before)


class AzureDevOpsTemplateSecurityTests(unittest.TestCase):
    def test_free_form_parameters_are_not_interpolated_in_shell_blocks(self) -> None:
        template = (
            Path(__file__).parents[1]
            / "templates"
            / "azure-devops"
            / "deploy-infrastructure-pipeline.yml"
        )
        lines = template.read_text(encoding="utf-8").splitlines()
        script_lines = []
        for index, line in enumerate(lines):
            stripped = line.lstrip()
            if stripped not in {"- bash: |", "inlineScript: |"}:
                continue
            body_indentation = None
            for body_line in lines[index + 1 :]:
                if not body_line.strip():
                    continue
                indentation = len(body_line) - len(body_line.lstrip())
                if body_indentation is None:
                    body_indentation = indentation
                if indentation < body_indentation:
                    break
                script_lines.append(body_line)
        scripts = "\n".join(script_lines)
        self.assertNotIn("${{ parameters.privateAgentPool }}", scripts)
        self.assertNotIn("${{ parameters.devJumpboxLoginGroupId }}", scripts)
        self.assertNotIn("${{ parameters.azurePrincipalObjectId }}", scripts)


if __name__ == "__main__":
    unittest.main()
