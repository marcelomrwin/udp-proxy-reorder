SHELL := /bin/bash

APP ?= python
export APP

ifndef COMPOSE
  ifneq ($(shell command -v docker 2>/dev/null),)
    COMPOSE := docker compose
  else ifneq ($(shell command -v podman 2>/dev/null),)
    COMPOSE := podman compose
  else
    $(error No container runtime found — install docker or podman)
  endif
endif

EXEC := $(COMPOSE) exec -T

ifeq ($(APP),java)
  SEND := java -cp /app Sender
  RECV := java -cp /app Receiver
  PRXY := java -cp /app Proxy
else ifeq ($(APP),go)
  SEND := /app/sender
  RECV := /app/receiver
  PRXY := /app/proxy
else
  SEND := python3 /app/sender.py
  RECV := python3 /app/receiver.py
  PRXY := python3 /app/proxy.py
endif

.PHONY: all setup capture step1 step2 step3 perf clean help

all: setup capture step1 step2 step3 clean

setup:
	@$(COMPOSE) down 2>/dev/null || true ; \
	$(COMPOSE) up -d --build && \
	sleep 2 && \
	$(EXEC) sender   ip route add 10.10.2.0/24 via 10.10.1.3 && \
	$(EXEC) receiver ip route add 10.10.1.0/24 via 10.10.2.2 && \
	$(EXEC) proxy    ip route add 10.10.1.0/24 via 10.10.2.2 && \
	$(EXEC) vswitch  iptables -P FORWARD ACCEPT && \
	echo "" && \
	echo "Lab ready. (runtime: $(COMPOSE) | app: $(APP))"

capture:
	@echo "" ; \
	echo "=== Fragment capture: 1 datagram = 14 IP fragments ===" ; \
	echo "" ; \
	BACK_IF=$$($(EXEC) vswitch ip -o addr show | grep "10\.10\.2\." | awk '{print $$2}' | tr -d '\r') ; \
	$(EXEC) vswitch tc qdisc del dev "$$BACK_IF" root 2>/dev/null || true ; \
	$(EXEC) vswitch tcpdump -n -c 14 -i "$$BACK_IF" ip and dst host 10.10.2.3 > /tmp/lab-capture.txt 2>/dev/null & PID=$$! ; \
	sleep 1 ; \
	$(EXEC) sender $(SEND) 10.10.2.3 1 ; \
	sleep 2 ; \
	kill $$PID 2>/dev/null || true ; \
	wait $$PID 2>/dev/null || true ; \
	cat /tmp/lab-capture.txt

step1:
	@echo "" ; \
	echo "=== Step 1: Baseline (no reorder) ===" ; \
	echo "" ; \
	BACK_IF=$$($(EXEC) vswitch ip -o addr show | grep "10\.10\.2\." | awk '{print $$2}' | tr -d '\r') ; \
	$(EXEC) vswitch tc qdisc del dev "$$BACK_IF" root 2>/dev/null || true ; \
	$(EXEC) vswitch iptables -t nat -F PREROUTING 2>/dev/null || true ; \
	$(EXEC) receiver $(RECV) > /tmp/lab-recv.txt 2>&1 & PID=$$! ; \
	sleep 1 ; \
	$(EXEC) sender $(SEND) 10.10.2.3 ; \
	wait $$PID ; \
	cat /tmp/lab-recv.txt

step2:
	@echo "" ; \
	echo "=== Step 2: vswitch reorders fragments ===" ; \
	echo "" ; \
	BACK_IF=$$($(EXEC) vswitch ip -o addr show | grep "10\.10\.2\." | awk '{print $$2}' | tr -d '\r') ; \
	$(EXEC) vswitch tc qdisc del dev "$$BACK_IF" root 2>/dev/null || true ; \
	$(EXEC) vswitch tc qdisc add dev "$$BACK_IF" root netem delay 6ms 5ms limit 10000 ; \
	echo "  netem: delay 6ms ±5ms on $$BACK_IF" ; \
	echo "" ; \
	$(EXEC) vswitch iptables -t nat -F PREROUTING 2>/dev/null || true ; \
	$(EXEC) receiver $(RECV) > /tmp/lab-recv.txt 2>&1 & PID=$$! ; \
	sleep 1 ; \
	$(EXEC) sender $(SEND) 10.10.2.3 ; \
	wait $$PID ; \
	cat /tmp/lab-recv.txt

step3:
	@echo "" ; \
	echo "=== Step 3: Streaming reorder proxy ===" ; \
	echo "" ; \
	BACK_IF=$$($(EXEC) vswitch ip -o addr show | grep "10\.10\.2\." | awk '{print $$2}' | tr -d '\r') ; \
	$(EXEC) vswitch tc qdisc del dev "$$BACK_IF" root 2>/dev/null || true ; \
	$(EXEC) vswitch tc qdisc add dev "$$BACK_IF" root netem delay 6ms 5ms limit 10000 ; \
	$(EXEC) vswitch iptables -t nat -F PREROUTING 2>/dev/null || true ; \
	$(EXEC) proxy $(PRXY) 10.10.2.3 3 > /tmp/lab-proxy.txt 2>&1 & PID_P=$$! ; \
	$(EXEC) receiver $(RECV) 8 > /tmp/lab-recv.txt 2>&1 & PID_R=$$! ; \
	sleep 2 ; \
	$(EXEC) sender $(SEND) 10.10.2.4 ; \
	wait $$PID_P ; \
	wait $$PID_R ; \
	cat /tmp/lab-proxy.txt ; \
	cat /tmp/lab-recv.txt

perf:
	@echo "" ; \
	echo "=== Performance: iperf3 UDP 20kB datagrams through vswitch ===" ; \
	echo "" ; \
	BACK_IF=$$($(EXEC) vswitch ip -o addr show | grep "10\.10\.2\." | awk '{print $$2}' | tr -d '\r') ; \
	$(EXEC) vswitch tc qdisc del dev "$$BACK_IF" root 2>/dev/null || true ; \
	$(EXEC) vswitch tc qdisc add dev "$$BACK_IF" root netem delay 6ms 5ms limit 10000 ; \
	echo "  netem: delay 6ms ±5ms on $$BACK_IF" ; \
	echo "" ; \
	$(EXEC) receiver iperf3 -s -1 > /tmp/lab-iperf-server.txt 2>&1 & PID=$$! ; \
	sleep 1 ; \
	$(EXEC) sender iperf3 -c 10.10.2.3 -u -l 20000 -b 50M -t 10 --forceflush ; \
	wait $$PID ; \
	echo "" ; \
	echo "--- Server report ---" ; \
	cat /tmp/lab-iperf-server.txt

clean:
	@$(COMPOSE) down -v ; \
	echo "Lab cleaned up."

help:
	@echo "Usage: make [target] [APP=python|java|go]" ; \
	echo "" ; \
	echo "  all      (default) full run: setup → capture → step1 → step2 → step3 → clean" ; \
	echo "  setup    build images, start containers, configure routing" ; \
	echo "  capture  send 1 datagram, show the 14 IP fragments on the wire" ; \
	echo "  step1    baseline — no reorder" ; \
	echo "  step2    introduce fragment reorder via netem on vswitch" ; \
	echo "  step3    streaming reorder proxy" ; \
	echo "  perf     iperf3 UDP load test (20kB datagrams, 10s)" ; \
	echo "  clean    stop and remove containers"
