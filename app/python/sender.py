import socket
import struct
import time
import sys

TARGET = sys.argv[1] if len(sys.argv) > 1 else "10.10.2.3"
PORT = 5000
COUNT = int(sys.argv[2]) if len(sys.argv) > 2 else 200
SIZE = 20000
INTERVAL = 0.001

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1048576)

for seq in range(COUNT):
    payload = struct.pack("!I", seq) + b'\x42' * (SIZE - 4)
    sock.sendto(payload, (TARGET, PORT))
    time.sleep(INTERVAL)

sock.close()
print(f"Sent {COUNT} datagrams ({SIZE} bytes) to {TARGET}:{PORT}")
