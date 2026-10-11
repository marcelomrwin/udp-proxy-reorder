import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.util.Arrays;

public class Sender {
    static final int PORT = 5000;
    static final int SIZE = 20000;
    static final long INTERVAL_MS = 1;

    public static void main(String[] args) throws Exception {
        String target = args.length > 0 ? args[0] : "10.10.2.3";
        int count = args.length > 1 ? Integer.parseInt(args[1]) : 200;

        DatagramSocket socket = new DatagramSocket();
        socket.setSendBufferSize(1048576);
        InetAddress address = InetAddress.getByName(target);

        for (int seq = 0; seq < count; seq++) {
            byte[] payload = new byte[SIZE];
            ByteBuffer.wrap(payload).putInt(seq);
            Arrays.fill(payload, 4, SIZE, (byte) 0x42);

            socket.send(new DatagramPacket(payload, SIZE, address, PORT));
            Thread.sleep(INTERVAL_MS);
        }

        socket.close();
        System.out.printf("Sent %d datagrams (%d bytes) to %s:%d%n", count, SIZE, target, PORT);
    }
}
