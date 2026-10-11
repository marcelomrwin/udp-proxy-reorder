import socket
import struct
import sys
import time

TARGET = sys.argv[1] if len(sys.argv) > 1 else "10.10.2.3"
PORT = 5000
IDLE_TIMEOUT = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
WINDOW = 32

sock_in = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock_in.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4194304)
sock_in.bind(("0.0.0.0", PORT))
sock_in.settimeout(0.1)

sock_out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

buf = {}
next_seq = 0
received = 0
forwarded = 0
arrival = []
last_recv = time.time()

def flush_consecutive():
    global next_seq, forwarded
    while next_seq in buf:
        sock_out.sendto(buf.pop(next_seq), (TARGET, PORT))
        next_seq += 1
        forwarded += 1

while True:
    try:
        data, _ = sock_in.recvfrom(65535)
        seq = struct.unpack("!I", data[:4])[0]
        received += 1
        last_recv = time.time()
        if len(arrival) < 30:
            arrival.append(seq)
        buf[seq] = data
        flush_consecutive()
        if len(buf) >= WINDOW:
            next_seq = min(buf)
            flush_consecutive()
    except socket.timeout:
        if time.time() - last_recv > IDLE_TIMEOUT:
            for seq in sorted(buf):
                sock_out.sendto(buf[seq], (TARGET, PORT))
                forwarded += 1
            break

sock_in.close()
sock_out.close()

print(f"Proxy: received {received}, forwarded {forwarded} (streaming, window={WINDOW})")
print(f"  arrival order (first {len(arrival)}): {' '.join(str(s) for s in arrival)}")
