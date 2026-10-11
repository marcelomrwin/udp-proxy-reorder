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
	target := "10.10.2.3"
	if len(os.Args) > 1 {
		target = os.Args[1]
	}
	count := 200
	if len(os.Args) > 2 {
		count, _ = strconv.Atoi(os.Args[2])
	}

	addr, err := net.ResolveUDPAddr("udp", target+":5000")
	check(err)
	conn, err := net.DialUDP("udp", nil, addr)
	check(err)
	defer conn.Close()

	conn.SetWriteBuffer(1048576)

	payload := make([]byte, 20000)
	for i := 4; i < len(payload); i++ {
		payload[i] = 0x42
	}

	for seq := 0; seq < count; seq++ {
		binary.BigEndian.PutUint32(payload[:4], uint32(seq))
		_, err := conn.Write(payload)
		check(err)
		time.Sleep(time.Millisecond)
	}

	fmt.Printf("Sent %d datagrams (20000 bytes) to %s:5000\n", count, target)
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
