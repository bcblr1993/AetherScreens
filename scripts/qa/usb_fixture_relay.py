"""Read controlled fixture events on the Mac, exchanging QA files over USB.

The UI test runner makes no LAN requests. Its app under test still connects
normally, so this does not change the product's network or permission behavior.
"""
import base64
import json
from pathlib import Path
import subprocess
import threading
import urllib.request
from uuid import UUID, uuid4


class USBFixtureRelay:
    def __init__(self, device_id, fixture_host, http_port, output):
        self.device_id = device_id
        self.base = f'http://{fixture_host}:{http_port}/'
        self.directory = 'AetherScreensQARelay-' + uuid4().hex
        self.output = Path(output) / 'usb-relay'
        self.output.mkdir()
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.counts = {}

    def start(self):
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        self.thread.join(timeout=15)

    def _copy(self, direction, source, destination):
        return subprocess.run([
            'xcrun', 'devicectl', 'device', 'copy', direction,
            '--device', self.device_id,
            '--domain-type', 'appDataContainer',
            '--domain-identifier', 'com.aethernative.aetherscreens.ios.uitests.xctrunner',
            '--source', str(source), '--destination', str(destination),
            '--timeout', '5', '--quiet',
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

    def _serve(self):
        processed = set()
        remote = 'Documents/' + self.directory + '/'
        while not self.stop_event.is_set():
            # devicectl skips unchanged transfers. A fresh local destination
            # and a unique response filename prevent stale UUIDs being reused.
            request_file = self.output / ('receive-' + uuid4().hex + '.json')
            try:
                if not self._copy('from', remote + 'request.json', request_file):
                    continue
                request = json.loads(request_file.read_text())
                identifier = request['id']
                UUID(identifier)
                if identifier in processed:
                    continue
                # Only our synthetic fixture's four inspection operations are
                # allowed; no arbitrary URL, device file or credential access.
                if request['path'] not in ('events', 'reset', 'drop', 'three-displays'):
                    continue
                try:
                    with urllib.request.urlopen(self.base + request['path'], timeout=3) as response:
                        payload = response.read()
                    reply = {'id': identifier, 'payload': base64.b64encode(payload).decode()}
                except (OSError, ValueError):
                    reply = {'id': identifier, 'error': 'Controlled fixture request failed'}
                response_file = self.output / ('response-' + identifier + '.json')
                response_file.write_text(json.dumps(reply))
                if self._copy('to', response_file, remote + response_file.name):
                    processed.add(identifier)
                    path = request['path']
                    self.counts[path] = self.counts.get(path, 0) + 1
                    (self.output / 'counts.json').write_text(json.dumps(self.counts))
            except (OSError, ValueError, KeyError):
                pass
            finally:
                # This file was created by this polling iteration alone.
                request_file.unlink(missing_ok=True)
                self.stop_event.wait(0.05)
