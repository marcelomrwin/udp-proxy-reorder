FROM golang:alpine AS build
COPY app/go/*.go /src/
WORKDIR /src
RUN go build -o /bin/sender sender.go && \
    go build -o /bin/receiver receiver.go && \
    go build -o /bin/proxy proxy.go

FROM alpine:3.21
RUN apk add --no-cache iproute2 tcpdump iptables iperf3
COPY --from=build /bin/sender /bin/receiver /bin/proxy /app/
WORKDIR /app
CMD ["sleep", "infinity"]
