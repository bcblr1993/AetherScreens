#!/usr/bin/env python3
"""Loopback-only ARD security offer for account-prompt/cancellation UI QA.

No authentication is accepted. The fixture advertises only type 30 and records
protocol milestones without recording any received payload or credential.
"""
import argparse
import ipaddress
import json
from pathlib import Path
import socket
import socketserver
import threading
from uuid import uuid4


class AccountOfferServer(socketserver.ThreadingTCPServer):
    daemon_threads = True

    def __init__(self, address, log):
        self.log = log
        self.log_lock = threading.Lock()
        super().__init__(address, AccountOfferHandler)

    def event(self, connection, milestone):
        with self.log_lock:
            self.log.write(json.dumps({'connection': connection, 'type': milestone}) + '\n')
            self.log.flush()


class AccountOfferHandler(socketserver.BaseRequestHandler):
    def handle(self):
        identifier = uuid4().hex
        self.request.settimeout(300)
        try:
            self.request.sendall(b'RFB 003.889\n')
            version = b''
            while len(version) < 12:
                data = self.request.recv(12 - len(version))
                if not data:
                    self.server.event(identifier, 'closed-before-version')
                    return
                version += data
            if version not in (b'RFB 003.008\n', b'RFB 003.889\n'):
                self.server.event(identifier, 'unexpected-version')
                return
            self.request.sendall(bytes([1, 30]))
            self.server.event(identifier, 'account-offer')
            if self.request.recv(1):
                self.server.event(identifier, 'unexpected-authentication-selection')
            else:
                self.server.event(identifier, 'closed-without-authentication')
        except socket.timeout:
            self.server.event(identifier, 'fixture-timeout')
        except OSError:
            self.server.event(identifier, 'transport-closed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--listen-host', type=ipaddress.IPv4Address, default=ipaddress.IPv4Address('127.0.0.1'))
    parser.add_argument('--port', type=int, default=6090)
    parser.add_argument('--log', type=Path, required=True, help='New milestone log')
    args = parser.parse_args()
    if not args.listen_host.is_loopback or not 1024 <= args.port <= 65535:
        parser.error('Use a loopback address and an unprivileged TCP port')
    with args.log.open('x') as log:
        with AccountOfferServer((str(args.listen_host), args.port), log) as server:
            print('Owned account-prompt fixture listening on loopback port ' + str(args.port), flush=True)
            server.serve_forever()


if __name__ == '__main__':
    main()
