import socket
import struct
import sys

PORT = 5000
TIMEOUT = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4194304)
sock.bind(("0.0.0.0", PORT))
sock.settimeout(TIMEOUT)

received = []
try:
    while True:
        data, _ = sock.recvfrom(65535)
        seq = struct.unpack("!I", data[:4])[0]
        received.append(seq)
except socket.timeout:
    pass

sock.close()

inversions = sum(1 for i in range(1, len(received)) if received[i] < received[i - 1])
print(f"Received: {len(received)} | Out-of-order: {inversions} | {'PASS' if inversions == 0 else 'FAIL'}")

if inversions > 0:
    n = min(30, len(received))
    print(f"  arrival order (first {n}): {' '.join(str(s) for s in received[:n])}")
