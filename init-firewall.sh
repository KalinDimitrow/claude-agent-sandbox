#!/bin/bash
# Default-deny egress firewall for the shared network namespace.
# Allows only: loopback, the configured DNS resolver(s), GitHub, and the
# domains listed below. IPv6 is fully blocked.
set -euo pipefail
IFS=$'\n\t'

# Must resolve, or the script aborts.
REQUIRED_DOMAINS=(
  api.anthropic.com        # Claude API
  claude.ai                # claude.ai account login
  platform.claude.com      # Console account login
  registry.npmjs.org       # npm
)

# Nice to have: a failed lookup only prints a warning.
OPTIONAL_DOMAINS=(
  downloads.claude.ai      # plugins / updates
)

# --- Fail closed: if anything below fails, leave the namespace fully blocked.
lockdown() {
  iptables -P INPUT DROP || true
  iptables -P FORWARD DROP || true
  iptables -P OUTPUT DROP || true
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -P INPUT DROP || true
    ip6tables -P FORWARD DROP || true
    ip6tables -P OUTPUT DROP || true
  fi
}
on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "Firewall setup FAILED (exit $rc); leaving all traffic blocked." >&2
    lockdown
  fi
}
trap on_exit EXIT

verify() {
  echo "Firewall configured. Verifying..."

  if curl -s -o /dev/null --connect-timeout 5 https://example.com; then
    echo "ERROR: verification failed - example.com is reachable"; exit 1
  fi
  echo "OK: example.com blocked"

  if timeout 5 bash -c 'echo > /dev/tcp/1.1.1.1/22' 2>/dev/null; then
    echo "ERROR: verification failed - arbitrary SSH is reachable"; exit 1
  fi
  echo "OK: arbitrary SSH blocked"

  curl -fsS -o /dev/null --connect-timeout 5 https://api.github.com/zen \
    || { echo "ERROR: cannot reach api.github.com"; exit 1; }
  echo "OK: GitHub reachable"

  # Any HTTP status counts; we only care that the connection succeeds.
  curl -s -o /dev/null --connect-timeout 5 https://api.anthropic.com \
    || { echo "ERROR: cannot reach api.anthropic.com"; exit 1; }
  echo "OK: api.anthropic.com reachable"
}

# --- podman-compose may start this container twice. If the firewall from the
# first run is fully in place, only re-verify it (no reset, no open window).
if iptables -S OUTPUT 2>/dev/null | grep -q -- '-P OUTPUT DROP' \
   && iptables -S OUTPUT 2>/dev/null | grep -q -- '--match-set allowed-domains dst' \
   && iptables -S OUTPUT 2>/dev/null | grep -q -- '-j REJECT'; then
  echo "Firewall already active in this namespace; verifying only."
  verify
  exit 0
fi

# --- Re-run safety: a previous run leaves the default policy at DROP, which
# would block the lookups below. Open the policies first; the trap above
# re-locks everything if any later step fails.
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# --- Reset filter/mangle tables (nat is left alone so Docker DNS keeps working)
iptables -F
iptables -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains hash:net

# --- GitHub ranges (IPv4 only)
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -fsS --max-time 15 https://api.github.com/meta) \
  || { echo "ERROR: failed to fetch GitHub IP ranges"; exit 1; }
jq -e '.web and .api and .git' >/dev/null <<<"$gh_ranges" \
  || { echo "ERROR: GitHub meta response missing fields"; exit 1; }

while read -r cidr; do
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] \
    || { echo "ERROR: invalid CIDR from GitHub meta: $cidr"; exit 1; }
  ipset add -exist allowed-domains "$cidr"
done < <(jq -r '(.web + .api + .git)[] | select(contains(":") | not)' <<<"$gh_ranges")

# --- Other allowed domains (resolved once, at startup)
add_domain() {
  local domain="$1" ips ip
  # Ask several times and merge: CDN-fronted hosts return different IPs per query.
  ips=$(for _ in 1 2 3 4 5 6; do dig +short A "$domain"; sleep 0.3; done \
        | { grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || true; } | sort -u)
  [ -n "$ips" ] || return 1
  while read -r ip; do
    ipset add -exist allowed-domains "$ip"
  done <<<"$ips"
}

for domain in "${REQUIRED_DOMAINS[@]}"; do
  echo "Resolving $domain..."
  add_domain "$domain" || { echo "ERROR: could not resolve required domain $domain"; exit 1; }
done
for domain in "${OPTIONAL_DOMAINS[@]}"; do
  echo "Resolving $domain (optional)..."
  add_domain "$domain" || echo "WARNING: could not resolve optional domain $domain; skipping"
done

# --- Rules
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# DNS only to the resolver(s) this namespace is configured with (not to any host)
while read -r ns; do
  iptables -A OUTPUT -p udp -d "$ns" --dport 53 -j ACCEPT
  iptables -A OUTPUT -p tcp -d "$ns" --dport 53 -j ACCEPT
done < <(awk '/^nameserver/ && $2 ~ /^[0-9.]+$/ {print $2}' /etc/resolv.conf)

iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# --- IPv6: block everything except loopback
if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -F || echo "WARNING: ip6tables flush failed"
  ip6tables -A INPUT  -i lo -j ACCEPT || true
  ip6tables -A OUTPUT -o lo -j ACCEPT || true
  ip6tables -P INPUT   DROP || echo "WARNING: could not set IPv6 INPUT policy"
  ip6tables -P OUTPUT  DROP || echo "WARNING: could not set IPv6 OUTPUT policy"
  ip6tables -P FORWARD DROP || echo "WARNING: could not set IPv6 FORWARD policy"
  # Reject (not silently drop) outbound IPv6 so clients fall back to IPv4 at once.
  ip6tables -A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited \
    || echo "WARNING: could not add IPv6 REJECT rule (IPv6 may be slow, still blocked)"
else
  echo "WARNING: ip6tables not found; IPv6 is not filtered"
fi

echo "Firewall configured. Verifying..."

if curl -s -o /dev/null --connect-timeout 5 https://example.com; then
  echo "ERROR: verification failed - example.com is reachable"; exit 1
fi
echo "OK: example.com blocked"

if timeout 5 bash -c 'echo > /dev/tcp/1.1.1.1/22' 2>/dev/null; then
  echo "ERROR: verification failed - arbitrary SSH is reachable"; exit 1
fi
echo "OK: arbitrary SSH blocked"

curl -fsS -o /dev/null --connect-timeout 5 https://api.github.com/zen \
  || { echo "ERROR: cannot reach api.github.com"; exit 1; }
echo "OK: GitHub reachable"

# Any HTTP status counts; we only care that the connection succeeds.
curl -s -o /dev/null --connect-timeout 5 https://api.anthropic.com \
  || { echo "ERROR: cannot reach api.anthropic.com"; exit 1; }
echo "OK: api.anthropic.com reachable"
