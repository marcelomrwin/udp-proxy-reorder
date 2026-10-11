package main

import (
	"encoding/binary"
	"fmt"
	"net"
	"os"
	"sort"
	"strconv"
	"time"
)

const window = 32

func main() {
	target := "10.10.2.3"
	if len(os.Args) > 1 {
		target = os.Args[1]
	}
	idleTimeout := 3 * time.Second
	if len(os.Args) > 2 {
		secs, _ := strconv.ParseFloat(os.Args[2], 64)
		idleTimeout = time.Duration(secs * float64(time.Second))
	}

	listenAddr, err := net.ResolveUDPAddr("udp", ":5000")
	check(err)
	sockIn, err := net.ListenUDP("udp", listenAddr)
	check(err)
	defer sockIn.Close()
	sockIn.SetReadBuffer(4194304)

	targetAddr, err := net.ResolveUDPAddr("udp", target+":5000")
	check(err)
	sockOut, err := net.DialUDP("udp", nil, targetAddr)
	check(err)
	defer sockOut.Close()

	buf := make(map[uint32][]byte)
	var arrival []uint32
	var nextSeq uint32
	received := 0
	forwarded := 0
	lastRecv := time.Now()
	readBuf := make([]byte, 65535)

	flushConsecutive := func() {
		for {
			data, ok := buf[nextSeq]
			if !ok {
				break
			}
			sockOut.Write(data)
			delete(buf, nextSeq)
			nextSeq++
			forwarded++
		}
	}

	for {
		sockIn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
		n, _, err := sockIn.ReadFromUDP(readBuf)
		if err != nil {
			if time.Since(lastRecv) > idleTimeout {
				keys := make([]uint32, 0, len(buf))
				for k := range buf {
					keys = append(keys, k)
				}
				sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })
				for _, k := range keys {
					sockOut.Write(buf[k])
					forwarded++
				}
				break
			}
			continue
		}
		if n < 4 {
			continue
		}

		seq := binary.BigEndian.Uint32(readBuf[:4])
		data := make([]byte, n)
		copy(data, readBuf[:n])

		received++
		lastRecv = time.Now()
		if len(arrival) < 30 {
			arrival = append(arrival, seq)
		}
		buf[seq] = data
		flushConsecutive()

		if len(buf) >= window {
			var minSeq uint32 = ^uint32(0)
			for k := range buf {
				if k < minSeq {
					minSeq = k
				}
			}
			nextSeq = minSeq
			flushConsecutive()
		}
	}

	fmt.Printf("Proxy: received %d, forwarded %d (streaming, window=%d)\n", received, forwarded, window)
	fmt.Printf("  arrival order (first %d):", len(arrival))
	for _, s := range arrival {
		fmt.Printf(" %d", s)
	}
	fmt.Println()
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
