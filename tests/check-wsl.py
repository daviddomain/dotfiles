#!/usr/bin/env python3
"""WSL-only preflight tests; fake CLIs prevent Docker or installer mutations."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check-wsl.sh"
WSL = (
    Path("/proc/sys/kernel/osrelease").is_file()
    and not Path("/.dockerenv").exists()
    and not Path("/run/.containerenv").exists()
    and "microsoft" in Path("/proc/sys/kernel/osrelease").read_text().lower()
)


@unittest.skipUnless(WSL, "run these fixtures on the WSL host")
class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-preflight-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"
        self.env = {"HOME": str(self.root), "PATH": str(self.bin), "LC_ALL": "C"}
        for name in (
            "sha256sum timeout mktemp install cp mv rm mkdir chmod ln readlink "
            "dirname basename date cut cat cmp grep find uname"
        ).split():
            (self.bin / name).symlink_to(shutil.which(name))
        for name in ("git", "curl", "zsh", "python3", "nano"):
            self.stub(name, 'test "$*" = --version')
        self.stub("docker", 'test "$*" = "info --format {{.ServerVersion}}"')
        self.stub("devcontainer", 'test "$*" = --version')

    def stub(self, name, body):
        target = self.bin / name
        target.write_text(
            f'#!/bin/sh\nprintf "%s\\n" "{name} $*" >> "{self.calls}"\n{body}\n'
        )
        target.chmod(0o755)

    def run_check(self, *args):
        return subprocess.run(
            ["/bin/bash", str(SCRIPT), *args], env=self.env,
            capture_output=True, text=True, timeout=20,
        )

    def test_ready_and_repeatable(self):
        first = self.run_check()
        second = self.run_check()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual((first.returncode, first.stdout), (second.returncode, second.stdout))
        calls = self.calls.read_text()
        self.assertIn("docker info --format {{.ServerVersion}}", calls)
        self.assertNotIn("devcontainer up", calls)

    def test_missing_required_dependency(self):
        (self.bin / "git").unlink()
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("git fehlt", result.stdout)

    def test_unreachable_docker(self):
        self.stub("docker", "exit 1")
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Docker-Daemon nicht erreichbar", result.stdout)

    def test_broken_cli_runtime(self):
        self.stub("devcontainer", "exit 127")
        self.assertEqual(self.run_check().returncode, 1)

    def test_shell_only_does_not_call_docker_or_cli(self):
        result = self.run_check("--shell-only")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("docker", self.calls.read_text())
        self.assertNotIn("devcontainer", self.calls.read_text())

    def test_existing_incompatible_tool(self):
        self.stub("herdr", "echo herdr 0.0.0")
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("weicht vom Pin", result.stdout)

    def test_missing_nano_checks_extraction_tools(self):
        (self.bin / "nano").unlink()
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.stub("apt-get", "exit 99")
        self.stub("dpkg-deb", "exit 99")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("1 Warnungen", result.stdout)
        self.assertNotIn("apt-get", self.calls.read_text())

    def test_help_and_invalid_arguments_do_not_probe(self):
        self.assertEqual(self.run_check("--help").returncode, 0)
        self.assertEqual(self.run_check("--unknown").returncode, 2)
        self.assertEqual(self.run_check("--voice", "--shell-only").returncode, 2)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
