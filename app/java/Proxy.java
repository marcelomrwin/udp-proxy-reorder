import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.TreeMap;

public class Proxy {
    static final int PORT = 5000;
    static final int WINDOW = 32;

    public static void main(String[] args) throws Exception {
        String target = args.length > 0 ? args[0] : "10.10.2.3";
        int idleTimeoutMs = args.length > 1 ? (int) (Double.parseDouble(args[1]) * 1000) : 3000;

        DatagramSocket sockIn = new DatagramSocket(PORT);
        sockIn.setReceiveBufferSize(4194304);
        sockIn.setSoTimeout(100);

        DatagramSocket sockOut = new DatagramSocket();
        InetAddress targetAddr = InetAddress.getByName(target);

        TreeMap<Integer, byte[]> buf = new TreeMap<>();
        List<Integer> arrival = new ArrayList<>();
        int nextSeq = 0;
        int received = 0;
        int forwarded = 0;
        long lastRecv = System.currentTimeMillis();

        while (true) {
            try {
                byte[] buffer = new byte[65535];
                DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                sockIn.receive(packet);
                int seq = ByteBuffer.wrap(packet.getData()).getInt();
                byte[] data = new byte[packet.getLength()];
                System.arraycopy(packet.getData(), 0, data, 0, packet.getLength());

                received++;
                lastRecv = System.currentTimeMillis();
                if (arrival.size() < 30) arrival.add(seq);
                buf.put(seq, data);

                while (buf.containsKey(nextSeq)) {
                    byte[] d = buf.remove(nextSeq);
                    sockOut.send(new DatagramPacket(d, d.length, targetAddr, PORT));
                    nextSeq++;
                    forwarded++;
                }

                if (buf.size() >= WINDOW && !buf.isEmpty()) {
                    nextSeq = buf.firstKey();
                    while (buf.containsKey(nextSeq)) {
                        byte[] d = buf.remove(nextSeq);
                        sockOut.send(new DatagramPacket(d, d.length, targetAddr, PORT));
                        nextSeq++;
                        forwarded++;
                    }
                }
            } catch (SocketTimeoutException e) {
                if (System.currentTimeMillis() - lastRecv > idleTimeoutMs) {
                    for (byte[] d : buf.values()) {
                        sockOut.send(new DatagramPacket(d, d.length, targetAddr, PORT));
                        forwarded++;
                    }
                    break;
                }
            }
        }

        sockIn.close();
        sockOut.close();

        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < arrival.size(); i++) {
            if (i > 0) sb.append(' ');
            sb.append(arrival.get(i));
        }

        System.out.printf("Proxy: received %d, forwarded %d (streaming, window=%d)%n",
                received, forwarded, WINDOW);
        System.out.printf("  arrival order (first %d): %s%n", arrival.size(), sb);
    }
}
