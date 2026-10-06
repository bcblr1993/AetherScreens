"""Controlled RFB/HTTP fixture for received iOS gesture events.

No credentials or real desktop content. Defaults to loopback; an explicit local
interface and separate ports support isolated physical-device test lanes.
Run before the opt-in gesture UI test.
"""
import argparse
import json
import math
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
CLIPBOARD_DESKTOPS = {}
CLIPBOARD_INITIAL = 'VM clipboard 中文🙂𠮷'
CLIPBOARD_CHANGED = 'VM remote copy 第二段🙂𠮷'
CLIPBOARD_OVERSIZED = '中' * (1_048_000 // 3 + 1)
NEXT_CONNECTION_ID = 0
WIDTH, HEIGHT = 640, 360


def record(event):
    with LOCK:
        EVENTS.append(dict(event, time=time.monotonic()))


def decode_clipboard_archive(archive):
    position = 0
    def word():
        nonlocal position
        if len(archive) - position < 4: raise ValueError('Truncated archive word')
        value = struct.unpack_from('>I', archive, position)[0]
        position += 4
        return value
    def field():
        nonlocal position
        size = word()
        if size > len(archive) - position: raise ValueError('Truncated archive field')
        value = archive[position:position + size]
        position += size
        return value
    if not archive: return []
    count = word()
    if count > 256: raise ValueError('Too many clipboard flavors')
    result = []
    for _ in range(count):
        type_bytes = field()
        if len(type_bytes) > 1024: raise ValueError('Oversized clipboard type')
        uti = type_bytes.decode('utf-8')
        word()  # Reserved metadata.
        alias_count = word()
        if alias_count > 64: raise ValueError('Too many clipboard aliases')
        aliases = []
        for _ in range(alias_count):
            name = field()
            if len(name) > 1024: raise ValueError('Oversized clipboard alias')
            aliases.append((name.decode('utf-8'), field()))
        result.append((uti, field(), aliases))
    if position != len(archive): raise ValueError('Trailing clipboard archive bytes')
    return result


def encode_clipboard_archive(items):
    def field(value): return struct.pack('>I', len(value)) + value
    result = bytearray(struct.pack('>I', len(items)))
    for uti, value, aliases in items:
        result += field(uti.encode('utf-8')) + struct.pack('>II', 0, len(aliases))
        for name, data in aliases:
            result += field(name.encode('utf-8')) + field(data)
        result += field(value)
    return bytes(result)


class Desktop(socketserver.BaseRequestHandler):
    reports_layout = False
    apple_clipboard = False
    native_displays = False
    encoding = 'raw'
    def send(self, data):
        with self.send_lock:
            self.request.sendall(data)

    def record(self, event):
        record(dict(event, connection=self.connection_id))

    def record_clipboard(self, kind):
        event = {'type': kind}
        if self.clipboard_text in (CLIPBOARD_INITIAL, CLIPBOARD_CHANGED):
            event['text'] = self.clipboard_text
        else:
            size = len(self.clipboard_text.encode('utf-8'))
            event.update(bytes=size, oversized=size > 1_048_000)
        if getattr(self, 'clipboard_items', None) is not None:
            event['flavors'] = [{'type': uti, 'bytes': len(data)} for uti, data, _ in self.clipboard_items]
        self.record(event)

    def send_clipboard(self):
        text = self.clipboard_text.encode('utf-8')
        items = getattr(self, 'clipboard_items', None)
        archive = encode_clipboard_archive(items if items is not None else [('public.utf8-plain-text', text, [])])
        compressor = zlib.compressobj()
        payload = compressor.compress(archive) + compressor.flush(zlib.Z_SYNC_FLUSH)
        self.send(bytes((31, 0, 0, 0)) + struct.pack('>III', 0, len(archive), len(payload)) + payload)
        self.record_clipboard('clipboard-download')

    def read(self, count):
        data = bytearray()
        while len(data) < count:
            chunk = self.request.recv(count - len(data))
            if not chunk:
                raise EOFError
            data.extend(chunk)
        return bytes(data)

    def desktop_size(self):
        width = WIDTH // 2 if self.native_displays and self.selected_native_display is not None else WIDTH
        return int(width * self.server_scale), int(HEIGHT * self.server_scale)

    def frame(self, full=False):
        with self.geometry_lock:
            self.render_frame(full)

    def render_frame(self, full=False):
        width, height = self.desktop_size() if full else (1, 1)
        if full and self.native_displays and not self.native_layout_sent:
            self.native_layout_sent = True
            self.send_native_layout()
        encoding = 16 if self.encoding == 'zrle' else 0
        if encoding == 16 and encoding not in self.offered_encodings:
            self.record({'type': 'protocol-error', 'reason': 'ZRLE not advertised'})
            raise EOFError
        header = struct.pack('>BBHHHHHi', 0, 0, 1, 0, 0, width, height, encoding)
        if full:
            base = 110 if self.native_displays and self.selected_native_display == 20 else 90
            pixels = b''.join(bytes((base + (x // 80) * 10, 80 + (y // 60) * 20, 45, 255))
                              for y in range(height) for x in range(width))
        else:
            pixels = bytes((120, 100, 45, 255))
        if encoding == 16:
            tiles = bytearray()
            if full:
                for top in range(0, height, 64):
                    for left in range(0, width, 64):
                        tiles.append(0)
                        for y in range(top, min(top + 64, height)):
                            start = (y * width + left) * 4
                            for x in range(min(64, width - left)):
                                tiles.extend(pixels[start + x * 4:start + x * 4 + 3])
            else:
                tiles.extend(bytes((1, 120, 100, 45)))
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
        self.send(header + payload)
        self.record({'type': 'frame', 'full': full, 'encoding': self.encoding,
                     'payloadBytes': len(payload), 'rawPixelBytes': len(pixels), 'width': width, 'height': height})

    def handle(self):
        global NEXT_CONNECTION_ID
        self.compressor = zlib.compressobj() if self.encoding == 'zrle' else None
        self.offered_encodings = []
        self.clipboard_text = CLIPBOARD_INITIAL
        self.clipboard_monitoring = False
        self.clipboard_status_allowed = False
        self.held_keys = set()
        self.selected_native_display = None
        self.native_layout_sent = False
        self.server_scale = 1.0
        self.geometry_lock = threading.RLock()
        self.hold_native_scaling = False
        self.pending_native_scale = None
        with LOCK:
            NEXT_CONNECTION_ID += 1
            self.connection_id = NEXT_CONNECTION_ID
            CONNECTIONS[self.connection_id] = self.request
            self.send_lock = threading.Lock()
            SEND_LOCKS[self.connection_id] = self.send_lock
            if self.reports_layout:
                DISPLAY_CONNECTIONS.add(self.connection_id)
            if self.apple_clipboard:
                CLIPBOARD_DESKTOPS[self.connection_id] = self
        try:
            self.send(b'RFB 003.889\n' if self.apple_clipboard else b'RFB 003.008\n')
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
            automatic_updates = False
            while True:
                message = self.read(1)[0]
                if message == 0:
                    self.read(19)
                elif message == 2:
                    header = self.read(3)
                    count = struct.unpack('>H', header[1:])[0]
                    encoded = self.read(count * 4)
                    self.offered_encodings = list(struct.unpack('>' + 'i' * count, encoded))
                    self.record({'type': 'encodings', 'values': self.offered_encodings})
                elif message == 3:
                    header = self.read(9)
                    if header[0] == 0:
                        self.frame(full=True)
                    else:
                        pending_update = True
                elif self.apple_clipboard and message == 9:
                    reserved, version, interval, x, y, width, height = struct.unpack('>BHIHHHH', self.read(15))
                    if reserved != 0 or version != 1 or x != 0 or y != 0 or (width, height) != self.desktop_size():
                        self.record({'type': 'protocol-error', 'reason': 'Invalid Apple automatic update region'})
                        return
                    automatic_updates = interval != 0xffffffff
                    self.record({'type': 'automatic-frame-updates', 'intervalMicroseconds': interval,
                                 'enabled': automatic_updates, 'width': width, 'height': height})
                elif self.native_displays and message == 13:
                    combine, reserved, display_id = struct.unpack('>BHI', self.read(7))
                    if reserved != 0 or combine not in (0, 1) or (combine == 0 and display_id not in (10, 20)):
                        self.record({'type': 'protocol-error', 'reason': 'Invalid native display selection'})
                        return
                    with self.geometry_lock:
                        self.selected_native_display = None if combine == 1 else display_id
                        automatic_updates = False
                        pending_update = False
                        self.send_native_layout()
                elif self.native_displays and message == 8:
                    reserved, factor = struct.unpack('>Bd', self.read(9))
                    if reserved != 0 or not math.isfinite(factor) or not 0 < factor <= 1 or int(WIDTH // 2 * factor) < 1 or int(HEIGHT * factor) < 1:
                        self.record({'type': 'protocol-error', 'reason': 'Invalid native server scaling'})
                        return
                    self.record({'type': 'native-scaling-request', 'factor': factor})
                    automatic_updates = False
                    pending_update = False
                    with self.geometry_lock:
                        if self.hold_native_scaling:
                            self.pending_native_scale = factor
                        else:
                            self.apply_native_scaling(factor)
                elif message == 4:
                    packet = self.read(7)
                    key = struct.unpack('>I', packet[3:])[0]
                    self.record({'type': 'key', 'down': packet[0], 'key': key})
                    if packet[0]:
                        self.held_keys.add(key)
                        if self.apple_clipboard and key == 118 and 0xFFEB in self.held_keys:
                            self.record_clipboard('clipboard-paste')
                    else:
                        self.held_keys.discard(key)
                    if pending_update or automatic_updates:
                        self.frame()
                        pending_update = False
                elif message == 5:
                    mask, x, y = struct.unpack('>BHH', self.read(5))
                    self.record({'type': 'pointer', 'mask': mask, 'x': x, 'y': y})
                    if pending_update or automatic_updates:
                        self.frame()
                        pending_update = False
                elif message == 6:
                    length = struct.unpack('>I', self.read(7)[3:])[0]
                    if length > 1048576:
                        return
                    self.read(length)
                elif self.apple_clipboard and message == 33:
                    header = self.read(3)
                    size = struct.unpack('>H', header[1:])[0]
                    if size != 62: return
                    body = self.read(size)
                    self.clipboard_status_allowed = bool(body[-32:][2] & 0x08)
                    self.record({'type': 'viewer-info', 'commands': list(body[-32:])})
                elif self.apple_clipboard and message == 21:
                    self.clipboard_monitoring = self.read(7)[2] == 1
                    self.record({'type': 'clipboard-monitor', 'enabled': self.clipboard_monitoring})
                elif self.apple_clipboard and message == 11:
                    self.read(7)
                    self.send_clipboard()
                elif self.apple_clipboard and message == 31:
                    header = self.read(15)
                    size = struct.unpack('>I', header[11:15])[0]
                    if size > 16_777_216: return
                    decompressor = zlib.decompressobj()
                    archive = decompressor.decompress(self.read(size), 16_777_217)
                    if decompressor.unconsumed_tail or len(archive) > 16_777_216: return
                    items = decode_clipboard_archive(archive)
                    self.clipboard_items = items
                    self.clipboard_text = next((data.decode('utf-8') for uti, data, _ in items
                                                if uti == 'public.utf8-plain-text'), '')
                    self.record_clipboard('clipboard-upload')
                else:
                    self.record({'type': 'unexpected', 'message': message})
                    return
        except (EOFError, ConnectionError, OSError, ValueError, zlib.error, struct.error):
            return
        finally:
            with LOCK:
                CONNECTIONS.pop(self.connection_id, None)
                SEND_LOCKS.pop(self.connection_id, None)
                DISPLAY_CONNECTIONS.discard(self.connection_id)
                CLIPBOARD_DESKTOPS.pop(self.connection_id, None)
            self.record({'type': 'disconnected'})


class DualDisplayDesktop(Desktop):
    reports_layout = True


class AppleClipboardDesktop(Desktop):
    apple_clipboard = True


class AppleDisplayDesktop(AppleClipboardDesktop):
    native_displays = True

    def apply_native_scaling(self, factor):
        with self.geometry_lock:
            self.server_scale = factor
            self.pending_native_scale = None
            self.send_native_layout()

    def send_native_layout(self):
        if 0x44D not in self.offered_encodings or 0x451 not in self.offered_encodings:
            self.record({'type': 'protocol-error', 'reason': 'Missing native display encodings'})
            raise EOFError
        width, height = self.desktop_size()
        pixel_format = struct.pack('>BBBBHHHBBBxxx', 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
        current = 0xffffffff if self.selected_native_display is None else self.selected_native_display
        body = struct.pack('>HHHHHIIH', 5, WIDTH, HEIGHT, width, height, current, 0, 2)
        for display_id, left, flags in [(10, -WIDTH // 2, 1), (20, 0, 0)]:
            edges = struct.pack('>hhhh', 0, left, HEIGHT, left + WIDTH // 2)
            backing = struct.pack('>hhhh', 0, int(left * self.server_scale), height,
                                  int((left + WIDTH // 2) * self.server_scale))
            body += struct.pack('>ddI', 1.0, self.server_scale, display_id) + edges + backing + struct.pack('>I', flags) + pixel_format
        self.send(struct.pack('>BBHHHHHiH', 0, 0, 1, 0, 0, 0, 0, 0x451, len(body)) + body)
        self.record({'type': 'native-layout', 'selected': self.selected_native_display, 'width': width, 'height': height,
                     'factor': self.server_scale})


class Inspection(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path not in ('/events', '/reset', '/drop', '/three-displays', '/clipboard-change', '/clipboard-too-large',
                             '/native-scaling-hold', '/native-scaling-release'):
            self.send_error(404)
            return
        if self.path in ('/native-scaling-hold', '/native-scaling-release'):
            with LOCK:
                targets = [target for target in CLIPBOARD_DESKTOPS.values() if target.native_displays]
            for target in targets:
                with target.geometry_lock:
                    target.hold_native_scaling = self.path == '/native-scaling-hold'
                    if not target.hold_native_scaling and target.pending_native_scale is not None:
                        target.apply_native_scaling(target.pending_native_scale)
        if self.path in ('/clipboard-change', '/clipboard-too-large'):
            with LOCK:
                targets = list(CLIPBOARD_DESKTOPS.values())
            for target in targets:
                target.clipboard_items = None
                target.clipboard_text = CLIPBOARD_OVERSIZED if self.path == '/clipboard-too-large' else CLIPBOARD_CHANGED
                target.record_clipboard('clipboard-change')
                if target.clipboard_monitoring and target.clipboard_status_allowed:
                    try:
                        target.send(bytes((20, 0, 0, 4, 0, 1, 0, 2)))
                        target.record_clipboard('clipboard-notification')
                    except OSError:
                        pass
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
    parser.add_argument('--clipboard-rfb-port', type=int, default=6001)
    parser.add_argument('--native-display-rfb-port', type=int, default=6002)
    parser.add_argument('--encoding', choices=('raw', 'zrle'), default='raw', help='ZRLE validates negotiated, continuous compressed rendering')
    args = parser.parse_args()
    Desktop.encoding = args.encoding
    with RFBServer((args.listen_host, args.rfb_port), Desktop) as desktop, RFBServer((args.listen_host, args.display_rfb_port), DualDisplayDesktop) as displays, RFBServer((args.listen_host, args.clipboard_rfb_port), AppleClipboardDesktop) as clipboard, RFBServer((args.listen_host, args.native_display_rfb_port), AppleDisplayDesktop) as native_displays:
        threading.Thread(target=desktop.serve_forever, daemon=True).start()
        threading.Thread(target=displays.serve_forever, daemon=True).start()
        threading.Thread(target=clipboard.serve_forever, daemon=True).start()
        threading.Thread(target=native_displays.serve_forever, daemon=True).start()
        with ThreadingHTTPServer((args.listen_host, args.http_port), Inspection) as inspection:
            print('Gesture fixture ready on ' + args.listen_host, flush=True)
            inspection.serve_forever()


if __name__ == '__main__':
    main()
