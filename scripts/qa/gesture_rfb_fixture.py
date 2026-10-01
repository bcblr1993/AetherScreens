"""Loopback-only RFB/HTTP fixture for received iOS gesture events.

No credentials or real desktop content. Run before the opt-in gesture UI test.
"""
import argparse
import json
import socket
import socketserver
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EVENTS = []
LOCK = threading.Lock()
CONNECTIONS = {}
NEXT_CONNECTION_ID = 0
WIDTH, HEIGHT = 640, 360


def record(event):
    with LOCK:
        EVENTS.append(dict(event, time=time.monotonic()))


class Desktop(socketserver.BaseRequestHandler):
    def record(self, event):
        record(dict(event, connection=self.connection_id))

    def read(self, count):
        data = bytearray()
        while len(data) < count:
            chunk = self.request.recv(count - len(data))
            if not chunk:
                raise EOFError
            data.extend(chunk)
        return bytes(data)

    def frame(self, full=False):
        width, height = (WIDTH, HEIGHT) if full else (1, 1)
        header = struct.pack('>BBHHHHHi', 0, 0, 1, 0, 0, width, height, 0)
        if full:
            pixels = b''.join(bytes((90 + (x // 80) * 10, 80 + (y // 60) * 20, 45, 255))
                              for y in range(height) for x in range(width))
        else:
            pixels = bytes((120, 100, 45, 255))
        self.request.sendall(header + pixels)
        self.record({'type': 'frame', 'full': full})

    def handle(self):
        global NEXT_CONNECTION_ID
        with LOCK:
            NEXT_CONNECTION_ID += 1
            self.connection_id = NEXT_CONNECTION_ID
            CONNECTIONS[self.connection_id] = self.request
        try:
            self.request.sendall(b'RFB 003.008\n')
            if self.read(12) != b'RFB 003.008\n':
                return
            self.request.sendall(bytes((1, 1)))
            if self.read(1) != bytes((1,)):
                return
            self.request.sendall(bytes(4))
            self.read(1)
            pixel_format = struct.pack('>BBBBHHHBBBxxx', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
            name = b'Gesture QA'
            self.request.sendall(struct.pack('>HH', WIDTH, HEIGHT) + pixel_format + struct.pack('>I', len(name)) + name)
            self.record({'type': 'ready'})
            pending_update = False
            while True:
                message = self.read(1)[0]
                if message == 0:
                    self.read(19)
                elif message == 2:
                    header = self.read(3)
                    self.read(struct.unpack('>H', header[1:])[0] * 4)
                elif message == 3:
                    header = self.read(9)
                    if header[0] == 0:
                        self.frame(full=True)
                    else:
                        pending_update = True
                elif message == 4:
                    packet = self.read(7)
                    self.record({'type': 'key', 'down': packet[0], 'key': struct.unpack('>I', packet[3:])[0]})
                elif message == 5:
                    mask, x, y = struct.unpack('>BHH', self.read(5))
                    self.record({'type': 'pointer', 'mask': mask, 'x': x, 'y': y})
                    if pending_update:
                        self.frame()
                        pending_update = False
                elif message == 6:
                    length = struct.unpack('>I', self.read(7)[3:])[0]
                    if length > 1048576:
                        return
                    self.read(length)
                else:
                    self.record({'type': 'unexpected', 'message': message})
                    return
        except (EOFError, ConnectionError, OSError):
            return
        finally:
            with LOCK:
                CONNECTIONS.pop(self.connection_id, None)
            self.record({'type': 'disconnected'})


class Inspection(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path not in ('/events', '/reset', '/drop'):
            self.send_error(404)
            return
        if self.path == '/drop':
            with LOCK:
                targets = list(CONNECTIONS.values())
            for target in targets:
                try:
                    target.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        with LOCK:
            if self.path == '/reset':
                EVENTS.clear()
            payload = json.dumps(EVENTS).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class RFBServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rfb-port', type=int, default=5999)
    parser.add_argument('--http-port', type=int, default=8768)
    args = parser.parse_args()
    with RFBServer(('127.0.0.1', args.rfb_port), Desktop) as desktop:
        threading.Thread(target=desktop.serve_forever, daemon=True).start()
        with ThreadingHTTPServer(('127.0.0.1', args.http_port), Inspection) as inspection:
            print('Loopback gesture fixture ready', flush=True)
            inspection.serve_forever()


if __name__ == '__main__':
    main()
