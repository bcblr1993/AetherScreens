#!/usr/bin/env python3
"""Inspect Apple RFB version/auth negotiation without submitting credentials."""
import argparse
import json
import re
import socket
import struct
import time


def probe(host, port, timeout, client_version):
    deadline = time.monotonic() + timeout
    with socket.create_connection((host, port), timeout=timeout) as connection:
        def receive(size):
            result = bytearray()
            while len(result) < size:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('Negotiation deadline exceeded')
                connection.settimeout(remaining)
                chunk = connection.recv(size - len(result))
                if not chunk:
                    raise EOFError('Server closed during negotiation')
                result.extend(chunk)
            return bytes(result)

        server_version = receive(12)
        if not re.fullmatch(rb'RFB [0-9]{3}\.[0-9]{3}\n', server_version):
            raise ValueError('Invalid server version banner')
        connection.sendall(client_version)
        count = receive(1)[0]
        if count == 0:
            # Do not retain the server failure string: it can contain private context.
            raise ValueError('Server rejected the selected protocol version')
        types = list(receive(count))
        result = {
            'client_version': client_version.decode('ascii').strip(),
            'server_version': server_version.decode('ascii').strip(),
            'security_types': types,
            'authentication_submitted': False,
        }
        if 30 in types:
            connection.sendall(bytes([30]))
            generator, key_length = struct.unpack('>HH', receive(4))
            if not 16 <= key_length <= 4096 or generator < 2:
                raise ValueError('Invalid or unbounded Apple DH challenge')
            # Public modulus and server key are consumed, never retained in the report.
            receive(key_length * 2)
            result['ard_dh'] = {'generator': generator, 'key_length_bytes': key_length}
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, default=5900)
    parser.add_argument('--timeout', type=float, default=5)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or not 0 < args.timeout <= 30:
        parser.error('Port must be 1..65535; timeout must be positive and at most 30 seconds')
    reports = []
    for version in (b'RFB 003.008\n', b'RFB 003.889\n'):
        try:
            reports.append(probe(args.host, args.port, args.timeout, version))
        except (OSError, ValueError, EOFError) as error:
            reports.append({'client_version': version.decode('ascii').strip(),
                            'error_type': type(error).__name__,
                            'authentication_submitted': False})
    print(json.dumps({'negotiations': reports}, indent=2))
    return 0 if all('ard_dh' in report for report in reports) else 1


if __name__ == '__main__':
    raise SystemExit(main())
