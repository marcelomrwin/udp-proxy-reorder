package main

import (
	"encoding/binary"
	"fmt"
	"net"
	"os"
	"strconv"
	"time"
)

func main() {
	timeout := 3 * time.Second
	if len(os.Args) > 1 {
		secs, _ := strconv.ParseFloat(os.Args[1], 64)
		timeout = time.Duration(secs * float64(time.Second))
	}

	addr, err := net.ResolveUDPAddr("udp", ":5000")
	check(err)
	conn, err := net.ListenUDP("udp", addr)
	check(err)
	defer conn.Close()

	conn.SetReadBuffer(4194304)

	buf := make([]byte, 65535)
	var received []uint32

	for {
		conn.SetReadDeadline(time.Now().Add(timeout))
		n, _, err := conn.ReadFromUDP(buf)
		if err != nil {
			break
		}
		if n >= 4 {
			received = append(received, binary.BigEndian.Uint32(buf[:4]))
		}
	}

	inversions := 0
	for i := 1; i < len(received); i++ {
		if received[i] < received[i-1] {
			inversions++
		}
	}

	result := "PASS"
	if inversions > 0 {
		result = "FAIL"
	}
	fmt.Printf("Received: %d | Out-of-order: %d | %s\n", len(received), inversions, result)

	if inversions > 0 {
		n := len(received)
		if n > 30 {
			n = 30
		}
		fmt.Printf("  arrival order (first %d):", n)
		for i := 0; i < n; i++ {
			fmt.Printf(" %d", received[i])
		}
		fmt.Println()
	}
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
