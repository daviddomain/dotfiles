#!/usr/bin/env python3
"""Run on WSL. All Docker/CLI operations are replaced by recording stubs."""
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
WSL = (Path('/proc/sys/kernel/osrelease').exists()
       and 'microsoft' in Path('/proc/sys/kernel/osrelease').read_text().lower()
       and not Path('/.dockerenv').exists())


@unittest.skipUnless(WSL, 'WSL host required')
class Helpers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='dotfiles-helpers-')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.workspace = self.home / 'workspace with spaces'
        self.workspace.mkdir()
        self.log = self.home / 'calls.jsonl'
        for tool in ['docker', 'devcontainer']:
            file = self.bin / tool
            file.write_text('''#!/usr/bin/python3
import json, os, sys
with open(os.environ['CALL_LOG'], 'a') as f:
    f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + '\\n')
if os.path.basename(sys.argv[0]) == 'docker':
    sys.exit(int(os.environ.get('DOCKER_FAILURE', '0')))
if sys.argv[1:] == ['up', '--help']:
    print('old CLI' if os.environ.get('OLD_CLI') else '--no-lockfile')
elif sys.argv[1] == 'up':
    sys.exit(int(os.environ.get('UP_FAILURE', '0')))
''')
            file.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=str(self.bin)+':/usr/bin:/bin', CALL_LOG=str(self.log))

    def command(self, expression):
        return ['zsh', '-fc', 'source "$1"; '+expression, '--',
                str(ROOT/'zsh/wsl.zsh'), str(self.workspace)]

    def run_helper(self, expression, **env):
        return subprocess.run(self.command(expression), env=dict(self.env, **env),
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20)

    def calls(self):
        return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_source_and_help_are_read_only(self):
        result = self.run_helper('dcupexec --help; dcuvoice --help')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_start_preserves_path_and_explicit_flags(self):
        result = self.run_helper('dcupexec "$2" bash')
        self.assertEqual(result.returncode, 0, result.stderr)
        up = next(c for c in self.calls() if c[:3] == ['devcontainer','up','--workspace-folder'])
        self.assertIn(str(self.workspace), up)
        self.assertIn('--no-lockfile', up)
        self.assertIn('--dotfiles-repository', up)
        self.assertIn('~/dotfiles', up)
        self.assertNotIn('--remove-existing-container', up)

    def test_failed_up_does_not_execute_in_container(self):
        result = self.run_helper('dcupexec "$2"', UP_FAILURE='7')
        self.assertEqual(result.returncode, 7)
        self.assertFalse(any(c[:2] == ['devcontainer','exec'] for c in self.calls()))

    def test_missing_lockfile_support_stops_before_up(self):
        self.assertNotEqual(self.run_helper('dcupexec "$2"', OLD_CLI='1').returncode, 0)
        self.assertFalse(any('--workspace-folder' in c for c in self.calls()))

    def test_docker_failure_stops_before_up(self):
        self.assertNotEqual(self.run_helper('dcupexec "$2"', DOCKER_FAILURE='1').returncode, 0)
        self.assertFalse(any(c[0] == 'devcontainer' for c in self.calls()))

    def test_existing_function_is_preserved(self):
        result = self.run_helper('dcupexec() { print local-override; }; source "$1"; dcupexec')
        self.assertEqual(result.stdout.strip(), 'local-override')
        self.assertEqual(self.calls(), [])

    def test_existing_alias_is_preserved(self):
        result = subprocess.run(['zsh', '-fc',
            'alias dcupexec="echo private-alias"; source "$1"; alias dcupexec',
            '--', str(ROOT/'zsh/wsl.zsh')], env=self.env,
            capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('private-alias', result.stdout)
        self.assertEqual(self.calls(), [])

    def test_voice_rejects_noninteractive_input(self):
        self.assertNotEqual(self.run_helper('dcuvoice "$2"').returncode, 0)
        self.assertFalse(any('--remove-existing-container' in c for c in self.calls()))

    @unittest.skipUnless(Path('/mnt/wslg/PulseServer').is_socket(), 'WSLg socket required')
    def test_voice_decline_and_accept_with_fake_cli(self):
        for answer, expect_up in [('nein', False), ('ja', True)]:
            if self.log.exists(): self.log.unlink()
            master, slave = pty.openpty()
            proc = subprocess.Popen(self.command('dcuvoice "$2" bash'), env=self.env,
                                    stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            output = b''
            deadline = time.monotonic()+20
            sent = False
            try:
                while proc.poll() is None and time.monotonic() < deadline:
                    if select.select([master], [], [], .1)[0]:
                        try: output += os.read(master, 8192)
                        except OSError: break
                    if b'[ja/NEIN]' in output and not sent:
                        os.write(master, (answer+'\n').encode()); sent = True
                self.assertTrue(sent, output)
                self.assertEqual(proc.wait(timeout=2), 0, output)
            finally:
                if proc.poll() is None: proc.kill(); proc.wait()
                os.close(master)
            self.assertEqual(any('--remove-existing-container' in c for c in self.calls()), expect_up)
            for call in self.calls():
                if '-lc' in call:
                    script = call[call.index('-lc')+1]
                    parsed = subprocess.run(['sh', '-n'], input=script,
                                            capture_output=True, text=True)
                    self.assertEqual(parsed.returncode, 0, parsed.stderr)


if __name__ == '__main__': unittest.main()
