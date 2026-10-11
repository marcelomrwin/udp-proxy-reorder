FROM alpine:3.21
RUN apk add --no-cache openjdk17-jdk iproute2 tcpdump iptables iperf3
COPY app/java/*.java /app/
WORKDIR /app
RUN javac *.java
CMD ["sleep", "infinity"]
