#!/usr/bin/env python3
"""The Last Can of Beans: game server with multiplayer.

Serves the game over HTTP and relays multiplayer messages over a WebSocket at /ws.
Python 3 standard library only. Usage: python3 server.py [port]   (default 8000)
"""
import base64
import hashlib
import itertools
import json
import os
import socket
import struct
import sys
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'  # fixed by RFC 6455
MAX_MSG = 1 << 20

lock = threading.Lock()
clients = {}  # id -> Client, in join order
next_id = itertools.count(1)
host_id = None  # the player whose browser simulates the shared world


class Client:
    def __init__(self, cid, sock):
        self.id, self.sock = cid, sock
        self.name = f'Rider {cid}'
        self.playing = False
        self.send_lock = threading.Lock()

    def send_frame(self, opcode, data):
        n = len(data)
        if n < 126:
            hdr = struct.pack('!BB', 0x80 | opcode, n)
        elif n < 65536:
            hdr = struct.pack('!BBH', 0x80 | opcode, 126, n)
        else:
            hdr = struct.pack('!BBQ', 0x80 | opcode, 127, n)
        try:
            with self.send_lock:
                self.sock.sendall(hdr + data)
        except OSError:
            pass

    def send(self, text):
        self.send_frame(0x1, text.encode('utf-8'))


def broadcast_roster():
    global host_id
    with lock:
        # the host stays host while it keeps playing, so a rejoining player can't reset the night
        if host_id not in clients or not clients[host_id].playing:
            host_id = next((c.id for c in clients.values() if c.playing), None)
        msg = json.dumps({'t': 'roster', 'host': host_id,
                          'players': [{'id': c.id, 'name': c.name, 'playing': c.playing} for c in clients.values()]})
        targets = list(clients.values())
    for c in targets:
        c.send(msg)


def relay(sender, msg):
    msg['from'] = sender.id
    to = msg.get('to')
    text = json.dumps(msg, separators=(',', ':'))
    with lock:
        targets = [c for c in clients.values() if c is not sender and (to is None or c.id == to)]
    for c in targets:
        c.send(text)


def read_exact(rfile, n):
    data = rfile.read(n)
    if data is None or len(data) < n:
        raise ConnectionError('closed')
    return data


def read_message(rfile, client):
    """Returns the next text message, or None when the peer closes."""
    parts = []
    while True:
        b1, b2 = read_exact(rfile, 2)
        opcode, n = b1 & 0x0F, b2 & 0x7F
        if n == 126:
            n = struct.unpack('!H', read_exact(rfile, 2))[0]
        elif n == 127:
            n = struct.unpack('!Q', read_exact(rfile, 8))[0]
        if n > MAX_MSG:
            raise ConnectionError('message too large')
        mask = read_exact(rfile, 4) if b2 & 0x80 else None
        data = read_exact(rfile, n)
        if mask and n:
            m = (mask * (n // 4 + 1))[:n]
            data = (int.from_bytes(data, 'big') ^ int.from_bytes(m, 'big')).to_bytes(n, 'big')
        if opcode == 0x8:
            client.send_frame(0x8, b'')
            return None
        if opcode == 0x9:
            client.send_frame(0xA, data)
            continue
        if opcode == 0xA:
            continue
        parts.append(data)
        if b1 & 0x80:
            return b''.join(parts).decode('utf-8', 'replace')


class Handler(SimpleHTTPRequestHandler):
    def hidden(self):
        # never serve dotfiles such as .git to the network
        return any(part.startswith('.') for part in urlsplit(self.path).path.split('/'))

    def end_headers(self):
        self.send_header('X-Beans-Multiplayer', '1')  # lets the page know it can open /ws
        super().end_headers()

    def do_HEAD(self):
        if self.hidden():
            return self.send_error(404)
        super().do_HEAD()

    def do_GET(self):
        if urlsplit(self.path).path == '/ws' and self.headers.get('Upgrade', '').lower() == 'websocket':
            return self.handle_ws()
        if self.hidden():
            return self.send_error(404)
        super().do_GET()

    def handle_ws(self):
        key = self.headers.get('Sec-WebSocket-Key')
        if not key:
            return self.send_error(400)
        accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.send_response(101, 'Switching Protocols')
        self.send_header('Upgrade', 'websocket')
        self.send_header('Connection', 'Upgrade')
        self.send_header('Sec-WebSocket-Accept', accept)
        self.end_headers()
        self.wfile.flush()
        self.close_connection = True
        self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

        c = Client(next(next_id), self.connection)
        with lock:
            clients[c.id] = c
        c.send(json.dumps({'t': 'hello', 'id': c.id}))
        print(f'  + rider {c.id} connected from {self.client_address[0]}', flush=True)
        broadcast_roster()
        try:
            while True:
                text = read_message(self.rfile, c)
                if text is None:
                    break
                try:
                    msg = json.loads(text)
                except ValueError:
                    continue
                if not isinstance(msg, dict):
                    continue
                if msg.get('t') in ('join', 'name', 'state'):
                    if isinstance(msg.get('name'), str) and msg['name'].strip():
                        c.name = msg['name'].strip()[:16]
                    if 'playing' in msg:
                        c.playing = bool(msg['playing'])
                    broadcast_roster()
                else:
                    relay(c, msg)
        except (ConnectionError, OSError, ValueError):
            pass
        finally:
            with lock:
                clients.pop(c.id, None)
            print(f'  - rider {c.id} ({c.name}) left', flush=True)
            broadcast_roster()

    def log_message(self, fmt, *args):
        pass  # keep the console readable for the join instructions


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))  # no packet is sent; this just picks the outgoing interface
        return s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get('PORT', 8000))
    root = os.path.dirname(os.path.abspath(__file__))
    httpd = ThreadingHTTPServer(('0.0.0.0', port), partial(Handler, directory=root))
    ip = lan_ip()
    print('The Last Can of Beans is running.')
    print(f'  You:                    http://localhost:{port}/')
    if ip and not ip.startswith('127.'):
        print(f'  Friends on your network: http://{ip}:{port}/')
    print('Press Ctrl+C to stop.', flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\nBye, partner.')


if __name__ == '__main__':
    main()
