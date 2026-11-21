# Firewall container: has bash and every tool init-firewall.sh needs.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash iptables ipset curl jq dnsutils iproute2 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
