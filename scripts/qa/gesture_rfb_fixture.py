"""Controlled RFB/HTTP fixture for received iOS gesture events.

No credentials or real desktop content. Defaults to loopback; an explicit local
interface and separate ports support isolated physical-device test lanes.
Run before the opt-in gesture UI test.
"""
import argparse
import json
import socket
import socketserver
import struct
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EVENTS = []
LOCK = threading.Lock()
CONNECTIONS = {}
SEND_LOCKS = {}
DISPLAY_CONNECTIONS = set()
NEXT_CONNECTION_ID = 0
STALL_NEXT_CONNECTION = False
WIDTH, HEIGHT = 640, 360


def record(event):
    with LOCK:
        EVENTS.append(dict(event, time=time.monotonic()))


class Desktop(socketserver.BaseRequestHandler):
    reports_layout = False
    encoding = 'raw'
    cursor_shape = False
    def send(self, data):
        with self.send_lock:
            self.request.sendall(data)

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
        encoding = 16 if self.encoding == 'zrle' else 0
        if encoding == 16 and encoding not in self.offered_encodings:
            self.record({'type': 'protocol-error', 'reason': 'ZRLE not advertised'})
            raise EOFError
        header = struct.pack('>BBHHHHHi', 0, 0, 1, 0, 0, width, height, encoding)
        if full:
            pixels = b''.join(bytes((90 + (x // 80) * 10, 80 + (y // 60) * 20, 45, 255))
                              for y in range(height) for x in range(width))
        else:
            pixels = bytes((120, 100, 45, 255))
        if self.bits_per_pixel == 16:
            pixels = b''.join(struct.pack('<H', ((pixels[i + 2] >> 3) << 11) |
                                           ((pixels[i + 1] >> 2) << 5) | (pixels[i] >> 3))
                              for i in range(0, len(pixels), 4))
        stride = self.bits_per_pixel // 8
        compact_stride = 2 if stride == 2 else 3
        if encoding == 16:
            tiles = bytearray()
            if full:
                for top in range(0, height, 64):
                    for left in range(0, width, 64):
                        tiles.append(0)
                        for y in range(top, min(top + 64, height)):
                            start = (y * width + left) * stride
                            for x in range(min(64, width - left)):
                                tiles.extend(pixels[start + x * stride:start + x * stride + compact_stride])
            else:
                tiles.extend(bytes((1,)) + pixels[:compact_stride])
            compressed = self.compressor.compress(tiles) + self.compressor.flush(zlib.Z_SYNC_FLUSH)
            payload = struct.pack('>I', len(compressed)) + compressed
        else:
            payload = pixels
        if full and self.reports_layout:
            layout_header = struct.pack('>BBHHHHHi', 0, 0, 1, 0, 0, WIDTH, HEIGHT, -308)
            screens = struct.pack('>IHHHHI', 10, 0, 0, WIDTH // 2, HEIGHT, 0)
            screens += struct.pack('>IHHHHI', 20, WIDTH // 2, 0, WIDTH // 2, HEIGHT, 0)
            self.send(layout_header + bytes((2, 0, 0, 0)) + screens)
            self.record({'type': 'layout', 'screens': 2})
        if full and self.cursor_shape:
            if -239 not in self.offered_encodings:
                raise RuntimeError('RichCursor not advertised')
            cursor_pixels = bytearray()
            mask = bytearray()
            for y in range(24):
                bits = 0
                for x in range(24):
                    visible = x in range(10, 14) or y in range(10, 14)
                    bits = (bits << 1) | visible
                    cursor_pixels.extend(struct.pack('<H', 0x07e0) if self.bits_per_pixel == 16 else bytes((0, 255, 0, 0)))
                mask.extend(bits.to_bytes(3, 'big'))
            self.send(struct.pack('>BBHHHHHi', 0, 0, 1, 12, 12, 24, 24, -239) + cursor_pixels + mask)
            self.record({'type': 'cursor', 'hotspot': [12, 12], 'size': [24, 24]})
        self.send(header + payload)
        self.record({'type': 'frame', 'full': full, 'encoding': self.encoding,
                     'payloadBytes': len(payload), 'rawPixelBytes': len(pixels),
                     'bitsPerPixel': self.bits_per_pixel})

    def handle(self):
        global NEXT_CONNECTION_ID, STALL_NEXT_CONNECTION
        self.compressor = zlib.compressobj() if self.encoding == 'zrle' else None
        self.offered_encodings = []
        self.bits_per_pixel = 32
        with LOCK:
            self.stall_pixels = STALL_NEXT_CONNECTION
            STALL_NEXT_CONNECTION = False
            NEXT_CONNECTION_ID += 1
            self.connection_id = NEXT_CONNECTION_ID
            CONNECTIONS[self.connection_id] = self.request
            self.send_lock = threading.Lock()
            SEND_LOCKS[self.connection_id] = self.send_lock
            if self.reports_layout:
                DISPLAY_CONNECTIONS.add(self.connection_id)
        try:
            self.send(b'RFB 003.008\n')
            if self.read(12) != b'RFB 003.008\n':
                return
            self.send(bytes((1, 1)))
            if self.read(1) != bytes((1,)):
                return
            self.send(bytes(4))
            self.read(1)
            pixel_format = struct.pack('>BBBBHHHBBBxxx', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
            name = b'Gesture QA'
            self.send(struct.pack('>HH', WIDTH, HEIGHT) + pixel_format + struct.pack('>I', len(name)) + name)
            self.record({'type': 'ready'})
            pending_update = False
            while True:
                message = self.read(1)[0]
                if message == 0:
                    packet = self.read(19)
                    format_bytes = packet[3:]
                    values = struct.unpack('>BBBBHHHBBBxxx', format_bytes)
                    if values not in ((32, 24, 0, 1, 255, 255, 255, 16, 8, 0),
                                      (16, 16, 0, 1, 31, 63, 31, 11, 5, 0)):
                        self.record({'type': 'protocol-error', 'reason': 'Unsupported pixel format'})
                        return
                    self.bits_per_pixel = values[0]
                    self.record({'type': 'pixel-format', 'bitsPerPixel': self.bits_per_pixel})
                elif message == 2:
                    header = self.read(3)
                    count = struct.unpack('>H', header[1:])[0]
                    encoded = self.read(count * 4)
                    self.offered_encodings = list(struct.unpack('>' + 'i' * count, encoded))
                    self.record({'type': 'encodings', 'values': self.offered_encodings})
                elif message == 3:
                    header = self.read(9)
                    if self.stall_pixels:
                        self.record({'type': 'frame-withheld'})
                    elif header[0] == 0:
                        self.frame(full=True)
                    else:
                        pending_update = True
                elif message == 4:
                    packet = self.read(7)
                    self.record({'type': 'key', 'down': packet[0], 'key': struct.unpack('>I', packet[3:])[0]})
                elif message == 5:
                    mask, x, y = struct.unpack('>BHH', self.read(5))
                    self.record({'type': 'pointer', 'mask': mask, 'x': x, 'y': y})
                    if pending_update and not self.stall_pixels:
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
                SEND_LOCKS.pop(self.connection_id, None)
                DISPLAY_CONNECTIONS.discard(self.connection_id)
            self.record({'type': 'disconnected'})


class DualDisplayDesktop(Desktop):
    reports_layout = True


class Inspection(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        global STALL_NEXT_CONNECTION
        if self.path == '/stall-next':
            with LOCK:
                STALL_NEXT_CONNECTION = True
        if self.path not in ('/events', '/reset', '/drop', '/three-displays', '/stall-next'):
            self.send_error(404)
            return
        if self.path == '/three-displays':
            header = struct.pack('>BBHHHHHi', 0, 0, 1, 0, 0, WIDTH, HEIGHT, -308)
            screens = b''.join(struct.pack('>IHHHHI', *screen, 0) for screen in
                               [(10, 0, 0, 213, HEIGHT), (20, 213, 0, 214, HEIGHT), (30, 427, 0, 213, HEIGHT)])
            with LOCK:
                targets = [(connection_id, CONNECTIONS[connection_id], SEND_LOCKS[connection_id])
                           for connection_id in DISPLAY_CONNECTIONS]
            for connection_id, target, send_lock in targets:
                try:
                    with send_lock:
                        target.sendall(header + bytes((3, 0, 0, 0)) + screens)
                    record({'type': 'layout', 'connection': connection_id, 'screens': 3})
                except OSError:
                    pass
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
                STALL_NEXT_CONNECTION = False
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
    parser.add_argument('--listen-host', default='127.0.0.1', help='Explicit local interface for physical-device QA; defaults to loopback')
    parser.add_argument('--rfb-port', type=int, default=5999)
    parser.add_argument('--http-port', type=int, default=8768)
    parser.add_argument('--display-rfb-port', type=int, default=6000)
    parser.add_argument('--encoding', choices=('raw', 'zrle'), default='raw', help='ZRLE validates negotiated, continuous compressed rendering')
    parser.add_argument('--cursor', action='store_true', help='Advertise a visible standard RichCursor fixture')
    args = parser.parse_args()
    Desktop.encoding = args.encoding
    Desktop.cursor_shape = args.cursor
    with RFBServer((args.listen_host, args.rfb_port), Desktop) as desktop, RFBServer((args.listen_host, args.display_rfb_port), DualDisplayDesktop) as displays:
        threading.Thread(target=desktop.serve_forever, daemon=True).start()
        threading.Thread(target=displays.serve_forever, daemon=True).start()
        with ThreadingHTTPServer((args.listen_host, args.http_port), Inspection) as inspection:
            print('Gesture fixture ready on ' + args.listen_host, flush=True)
            inspection.serve_forever()


if __name__ == '__main__':
    main()
