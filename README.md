# UDP Fragmentation & Reordering Lab

When you move a UDP link from a physical cable to a virtual switch, large datagrams can start arriving out of order. This lab reproduces the problem and shows a proxy-based fix — no application changes needed.

## Why this happens

A 20kB UDP datagram doesn't fit in a single Ethernet frame (MTU 1500). The kernel splits it into 14 IP fragments. On a physical link these fragments travel in FIFO order and get reassembled correctly. But a virtual switch may spread fragments across multiple queues or threads. When fragments from different datagrams interleave in transit, the kernel on the receiving end reassembles them in the wrong order — and the application sees datagrams arriving out of sequence.

## The setup

Four containers, two subnets, one virtual switch in the middle:

```
Steps 1 & 2:
  sender (10.10.1.2) ──[front]──> vswitch ──[back]──> receiver (10.10.2.3)

Step 3 (fix):
  sender (10.10.1.2) ──[front]──> vswitch ──[back]──> proxy (10.10.2.4) ──> receiver (10.10.2.3)
```

The vswitch routes between the two subnets. We use `tc netem` on its back-facing interface to simulate the kind of jitter that causes fragment interleaving. In step 3 the sender targets the proxy instead of the receiver directly — in production you'd use `iptables DNAT` on the vswitch to make this transparent.

## Container images

Each language gets its own `Containerfile.<lang>` with everything baked in. You only need a container runtime on the host — no Python, no JDK, no Go toolchain.

| Image | Base | What's inside | Size |
|---|---|---|---|
| `Containerfile.python` | `alpine:3.21` | Python 3 + networking tools | ~61 MB |
| `Containerfile.java` | `alpine:3.21` | OpenJDK 17 + networking tools, pre-compiled | ~289 MB |
| `Containerfile.go` | multi-stage (`golang:alpine` → `alpine:3.21`) | Static binaries + networking tools | ~19 MB |
| `Containerfile.vswitch` | `alpine:3.21` | iproute2, iptables, tcpdump | ~19 MB |

Source lives under `app/python/`, `app/java/`, and `app/go/` and gets `COPY`'d into the image at build time.

## What you need

Docker Engine 20+ or Podman 4+ with Compose. That's it.

Podman needs rootful mode for `NET_ADMIN` and `tc netem`.

## Running it

```
make                    # full run with Python (default)
make APP=java           # full run with Java
make APP=go             # full run with Go
make step2 APP=python   # just one step
make perf               # iperf3 UDP load test (needs setup first)
make clean              # tear everything down
make help               # list targets
```

Docker or Podman is auto-detected. Override with:

```
make COMPOSE="podman compose"
```

## What you should see

The lab runs four phases: fragment capture, baseline, reorder, and fix.

### Fragment capture

Sends a single 20kB datagram and captures the traffic on the vswitch with `tcpdump`. You'll see 14 IP packets — the first one carries the UDP header, the other 13 are bare IP fragments (`ip-proto-17`):

```
=== Fragment capture: 1 datagram = 14 IP fragments ===

Sent 1 datagrams (20000 bytes) to 10.10.2.3:5000
18:54:00.508095 IP 10.10.1.2.51819 > 10.10.2.3.5000: UDP, length 20000
18:54:00.508096 IP 10.10.1.2 > 10.10.2.3: ip-proto-17
18:54:00.508096 IP 10.10.1.2 > 10.10.2.3: ip-proto-17
  ... (14 packets total)
```

This is the answer to "why 14 IP packets per datagram" — `ceil(20000 / 1480) = 14` fragments.

### Steps

```
=== Step 1: Baseline (no reorder) ===

Sent 200 datagrams (20000 bytes) to 10.10.2.3:5000
Received: 200 | Out-of-order: 0 | PASS

=== Step 2: vswitch reorders fragments ===

  netem: delay 6ms ±5ms on eth0

Sent 200 datagrams (20000 bytes) to 10.10.2.3:5000
Received: ~170 | Out-of-order: ~15 | FAIL
  arrival order (first 30): 0 1 3 2 4 5 6 8 9 10 11 13 ...

=== Step 3: Streaming reorder proxy ===

Sent 200 datagrams (20000 bytes) to 10.10.2.4:5000
Proxy: received ~170, forwarded ~170 (streaming, window=32)
  arrival order (first 30): 0 4 2 1 6 8 7 9 10 11 12 13 ...
Received: ~170 | Out-of-order: 0 | PASS
```

Step 2 breaks things — look at the arrival order, the sequence numbers jump around. Step 3 fixes it: the proxy gets the same disordered input but forwards in order as datagrams arrive. Receiver sees zero inversions.

The ~15% datagram loss in steps 2 and 3 comes from fragments getting delayed long enough by netem to miss the kernel's reassembly window. Same thing that happens with real virtual switches under load.

## How the proxy works

The proxy is a streaming reorder buffer that sits between the vswitch and the receiver. It works at the UDP datagram level — fragment reassembly is still handled by the kernel.

As datagrams arrive, the proxy tracks the next expected sequence number. If a datagram arrives in order, it gets forwarded immediately. If it arrives early (a gap in the sequence), it goes into a buffer. Every time the expected sequence shows up, the proxy flushes it along with any consecutive datagrams that were waiting in the buffer.

If the buffer fills up (window of 32), the proxy skips ahead to the lowest buffered sequence and flushes from there — this handles the case where fragments are lost entirely and a sequence number never arrives.

The sender and receiver don't know the proxy is there.

**A note on latency:** the reorder buffer necessarily holds datagrams while waiting for gaps to fill, which adds latency to the forwarding path. This lab does not measure or characterize that proxy-introduced latency — a proper assessment would require load testing under realistic traffic patterns and volume before deploying this approach in production.

## Performance testing

The lab includes an iperf3-based load test that sends 20kB UDP datagrams through the vswitch with netem active:

```
make setup
make perf
```

This measures jitter, packet loss, and throughput on the path — the same conditions that cause fragment reordering. Sample output:

```
=== Performance: iperf3 UDP 20kB datagrams through vswitch ===

  netem: delay 6ms ±5ms on eth0

[ ID] Interval       Transfer     Bitrate         Jitter    Lost/Total
[  5] 0.00-10.00 sec  59.6 MBytes  50.0 Mbits/sec  3.142 ms  420/3544 (11.9%)
```

Note that iperf3 measures the **network path** characteristics, not the latency added by the reorder proxy. The proxy operates at a different layer (application-level datagram reordering) and uses its own framing. Measuring proxy overhead would require instrumented sender/receiver with embedded timestamps, or tools like [nuttcp](https://www.nuttcp.net/) or [hping3](https://github.com/antirez/hping) in a custom test harness.

## Other approaches

- **Jumbo frames** — bump MTU to 20028+ so the datagram fits in one frame, no fragmentation at all
- **Queue pinning** — pin the vswitch to a single CPU/queue so it behaves like a FIFO again
