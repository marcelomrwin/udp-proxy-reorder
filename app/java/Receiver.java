import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

public class Receiver {
    static final int PORT = 5000;

    public static void main(String[] args) throws Exception {
        int timeoutMs = args.length > 0 ? (int) (Double.parseDouble(args[0]) * 1000) : 3000;

        DatagramSocket socket = new DatagramSocket(PORT);
        socket.setReceiveBufferSize(4194304);
        socket.setSoTimeout(timeoutMs);

        List<Integer> received = new ArrayList<>();
        byte[] buffer = new byte[65535];

        try {
            while (true) {
                DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                socket.receive(packet);
                received.add(ByteBuffer.wrap(packet.getData()).getInt());
            }
        } catch (SocketTimeoutException ignored) {
        }

        socket.close();

        int inversions = 0;
        for (int i = 1; i < received.size(); i++) {
            if (received.get(i) < received.get(i - 1)) inversions++;
        }

        System.out.printf("Received: %d | Out-of-order: %d | %s%n",
                received.size(), inversions, inversions == 0 ? "PASS" : "FAIL");

        if (inversions > 0) {
            int n = Math.min(30, received.size());
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < n; i++) {
                if (i > 0) sb.append(' ');
                sb.append(received.get(i));
            }
            System.out.printf("  arrival order (first %d): %s%n", n, sb);
        }
    }
}
