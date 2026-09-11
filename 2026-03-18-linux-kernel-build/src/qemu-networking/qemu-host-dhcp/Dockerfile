FROM alpine

RUN apk --no-cache add dnsmasq

COPY dnsmasq.conf /etc/dnsmasq.conf

EXPOSE 67/udp

CMD ["dnsmasq", "-p0", "-d"]
