#!/usr/bin/env python3
"""Host bootstrap consent and installer conflict tests; no real sudo/downloads."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOST = (Path('/proc/sys/kernel/osrelease').exists()
        and 'wsl2' in Path('/proc/sys/kernel/osrelease').read_text().lower()
        and not Path('/.dockerenv').exists() and os.geteuid() != 0)


@unittest.skipUnless(HOST, 'normal WSL2 user required')
class Bootstrap(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='dotfiles-bootstrap-')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home/'bin'; self.bin.mkdir()
        self.log = self.home/'sudo-calls'
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin)+':/usr/bin:/bin')
        self.stub('sudo', f'printf "%s\\n" "$*" >> "{self.log}"')
        self.stub('dpkg-query', 'exit 1')
        self.stub('docker', 'exit 0')
        self.stub('devcontainer', 'case "$*" in --version) echo 0.89.0 ;; "up --help") echo --no-lockfile ;; *) exit 99 ;; esac')

    def stub(self, name, text):
        path=self.bin/name
        path.write_text('#!/bin/sh\n'+text+'\n'); path.chmod(0o755)

    def run_script(self, script, *args):
        return subprocess.run(['/bin/bash', str(ROOT/script), *args], env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)

    def test_plan_and_refused_consent_do_not_install(self):
        self.assertEqual(self.run_script('bootstrap-wsl.sh', '--plan').returncode, 0)
        self.assertEqual(self.run_script('bootstrap-wsl.sh').returncode, 1)
        self.assertFalse(self.log.exists())

    def test_yes_installs_only_listed_missing_packages(self):
        result=self.run_script('bootstrap-wsl.sh', '--yes')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        calls=self.log.read_text().splitlines()
        self.assertEqual(calls[0], 'apt-get update')
        self.assertEqual(calls[1], 'apt-get install -y --no-install-recommends git curl ca-certificates zsh python3 coreutils nano tar xz-utils diffutils findutils grep')

    def test_complete_packages_do_not_run_apt(self):
        self.stub('dpkg-query', "printf 'install ok installed'")
        result=self.run_script('bootstrap-wsl.sh', '--yes')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertFalse(self.log.exists())

    def test_shell_only_does_not_require_cli(self):
        self.stub('devcontainer', 'exit 99')
        result=self.run_script('bootstrap-wsl.sh', '--yes', '--shell-only')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)

    def test_existing_cli_is_not_replaced(self):
        before=(self.bin/'devcontainer').read_bytes()
        self.assertEqual(self.run_script('install-cli.sh').returncode, 0)
        self.assertEqual(before, (self.bin/'devcontainer').read_bytes())
        self.assertFalse((self.home/'.local/bin/devcontainer').exists())

    def test_incompatible_cli_is_preserved_and_rejected(self):
        self.stub('devcontainer', 'echo old')
        self.assertEqual(self.run_script('install-cli.sh').returncode, 1)
        self.assertFalse((self.home/'.local/bin/devcontainer').exists())

    def test_checksum_failure_does_not_activate_cli(self):
        (self.bin/'devcontainer').unlink()
        self.stub('curl', 'while [ "$1" != -o ]; do shift; done; shift; printf invalid > "$1"')
        result=self.run_script('install-cli.sh')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Prüfsumme', result.stderr)
        self.assertFalse((self.home/'.local/bin/devcontainer').exists())
        root=self.home/'.local/share/dotfiles-devcontainer-cli'
        self.assertEqual(list(root.iterdir()), [])


if __name__ == '__main__': unittest.main()
