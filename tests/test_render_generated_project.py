from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "render_generated_project.py"
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
                "github-actions",
                Path("/unused/pipeline.yml"),
            )


if __name__ == "__main__":
    unittest.main()
