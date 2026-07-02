#!/usr/bin/env python3
"""Dumb TCP forwarder for QA: listen on :8099 → forward to :8081.

The offline-drain test points the core at 8099; killing/starting this
process simulates the network dropping/returning while the backend
itself stays up.
"""
import socket
import sys
import threading

LISTEN = ("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8099)
TARGET = ("127.0.0.1", int(sys.argv[2]) if len(sys.argv) > 2 else 8081)


def pump(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(client: socket.socket) -> None:
    try:
        upstream = socket.create_connection(TARGET, timeout=10)
    except OSError:
        client.close()
        return
    threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pump, args=(upstream, client), daemon=True).start()


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(LISTEN)
srv.listen(64)
print(f"proxy {LISTEN} -> {TARGET}", flush=True)
while True:
    conn, _ = srv.accept()
    handle(conn)
