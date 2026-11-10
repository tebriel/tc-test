import socket
import statistics
import sys
import time

mode = sys.argv[1]
expected = {"baseline": 0, "delayed": 50, "ingress-only": 25, "egress-only": 25}[mode]

for address in ("10.200.1.1", "fd00:200::1"):
    for port in (6033, 3306, 6032):
        samples = []
        for _ in range(10):
            # Retry startup only; errors during an established exchange must fail.
            deadline = time.monotonic() + 10
            while True:
                try:
                    conn = socket.create_connection((address, port), timeout=5)
                    break
                except ConnectionRefusedError:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.05)
            with conn:
                start = time.perf_counter()
                conn.sendall(b"x")
                if conn.recv(1) != b"x":
                    raise RuntimeError("Echo response mismatch")
                samples.append((time.perf_counter() - start) * 1000)
        median = statistics.median(samples)
        target = expected if port == 6033 else 0
        print(f"{mode:12} {address:14} :{port} median {median:.2f}ms (target {target}ms)", flush=True)
        if not max(0, target - 5) <= median <= target + 15:
            raise RuntimeError(f"{address}:{port}: unexpected RTT {median:.2f}ms")
