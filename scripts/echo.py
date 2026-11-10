import selectors
import socket

selector = selectors.DefaultSelector()
for family, address in ((socket.AF_INET, "10.200.1.1"), (socket.AF_INET6, "fd00:200::1")):
    for port in (6033, 3306, 6032):
        listener = socket.socket(family)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((address, port))
        listener.listen()
        selector.register(listener, selectors.EVENT_READ)

print("Echo listeners ready", flush=True)
while True:
    for key, _ in selector.select():
        conn, _ = key.fileobj.accept()
        with conn:
            conn.settimeout(5)
            data = conn.recv(1024)
            if data:
                conn.sendall(data)
