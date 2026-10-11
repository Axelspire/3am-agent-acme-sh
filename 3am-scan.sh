#!/usr/bin/env bash
# Copyright (c) 2026 Axelspire Inc.
# SPDX-License-Identifier: MIT
#
# 3am-scan.sh — ONE-FILE TLS scan + report companion for upstream acme.sh
#
# Design constraints (DATASINK-31):
#   * This is the ONLY file we add for datasink test/dev scanning.
#   * It does NOT patch or fork-edit acme.sh — keep an upstream clone beside it
#     and rebase/update that clone freely.
#   * Bootstrap = obtain a client cert first (via acme.sh / at3am / other),
#     then run this scanner with mTLS against scan.<id>.3am.global.
#
# Required env:
#   SCAN_SERVER   https://scan.<id>.3am.global  (no trailing slash)
#   SCAN_CERT     path to client certificate PEM (leaf; CN = host_id)
#   SCAN_KEY      path to client private key PEM
#
# Optional env:
#   SCAN_CA       path to CA bundle to verify the scan server (recommended)
#   SCAN_HOST_ID  override host_id (default: CN from SCAN_CERT)
#   SCAN_PORTS    comma-separated ports (override config ports)
#   SCAN_TIMEOUT  connect timeout seconds (default: 5)
#   SCAN_USE_SCOPE=1  force legacy GET /scope instead of OpenAPI /config
#   SCAN_EXPAND=1     expand assigned_cidrs under max_expand_hosts budget
#   SCAN_STATE_DIR    directory for last-scan timestamp (default: ~/.local/state/3am)
#
# Usage:
#   ./3am-scan.sh                  # pull config, scan, POST results
#   ./3am-scan.sh host1.example.com host2.example.com:8443
#     (still GETs config first — DATASINK-70)
#
set -euo pipefail

SCAN_SERVER="${SCAN_SERVER:-}"
SCAN_CERT="${SCAN_CERT:-}"
SCAN_KEY="${SCAN_KEY:-}"
SCAN_CA="${SCAN_CA:-}"
SCAN_HOST_ID="${SCAN_HOST_ID:-}"
SCAN_TIMEOUT="${SCAN_TIMEOUT:-5}"
SCAN_STATE_DIR="${SCAN_STATE_DIR:-${HOME:-/tmp}/.local/state/3am}"
DEFAULT_PORTS="443,993,995,8443"

_die() { echo "3am-scan: ERROR: $*" >&2; exit 1; }
_info() { echo "3am-scan: $*" >&2; }

_require() {
  command -v "$1" >/dev/null 2>&1 || _die "missing dependency: $1"
}

_require curl
_require openssl
_require python3

[[ -n "$SCAN_SERVER" ]] || _die "SCAN_SERVER is required (e.g. https://scan.demo.3am.global)"
[[ -f "$SCAN_CERT" ]] || _die "SCAN_CERT not found: ${SCAN_CERT:-<unset>}"
[[ -f "$SCAN_KEY" ]] || _die "SCAN_KEY not found: ${SCAN_KEY:-<unset>}"

SCAN_SERVER="${SCAN_SERVER%/}"

_curl_mtls() {
  # shellcheck disable=SC2086
  local ca_args=()
  if [[ -n "$SCAN_CA" ]]; then
    ca_args=(--cacert "$SCAN_CA")
  else
    ca_args=(-k)
  fi
  curl -sS "${ca_args[@]}" \
    --cert "$SCAN_CERT" \
    --key "$SCAN_KEY" \
    --connect-timeout "$SCAN_TIMEOUT" \
    "$@"
}

_cn_from_cert() {
  openssl x509 -in "$SCAN_CERT" -noout -subject -nameopt RFC2253 2>/dev/null \
    | sed -n 's/.*CN=\([^,/]*\).*/\1/p' \
    | head -n1
}

HOST_ID="${SCAN_HOST_ID:-$(_cn_from_cert)}"
[[ -n "$HOST_ID" ]] || _die "could not derive host_id from SCAN_CERT CN; set SCAN_HOST_ID"

_fetch_config() {
  # Prefer OpenAPI v0.6 /config (cidrs + fqdns + port objects). Fall back to
  # legacy /scope so older sinks still work (DATASINK-39 / B9).
  local cfg_url="${SCAN_SERVER}/v1/at3am/config/${HOST_ID}"
  local scope_url="${SCAN_SERVER}/v1/at3am/scope/${HOST_ID}"
  if [[ "${SCAN_USE_SCOPE:-}" == "1" ]]; then
    _info "GET scope ${scope_url}"
    _curl_mtls -f -X GET "$scope_url"
    return
  fi
  _info "GET config ${cfg_url}"
  if out="$(_curl_mtls -f -X GET "$cfg_url" 2>/dev/null)"; then
    printf '%s' "$out"
    return
  fi
  _info "config unavailable; falling back to legacy scope ${scope_url}"
  _curl_mtls -f -X GET "$scope_url"
}

_scan_endpoint() {
  # Args: host port → prints one JSON object (certificate + tls facts) or empty
  local host="$1" port="$2"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  if ! echo | openssl s_client -connect "${host}:${port}" -servername "$host" \
      -brief 2>/dev/null | head -n 40 >"$tmp"; then
    # Retry capturing PEM even on non-zero (common for verify errors)
    echo | openssl s_client -connect "${host}:${port}" -servername "$host" \
      2>/dev/null >"$tmp" || true
  fi

  if ! grep -q "BEGIN CERTIFICATE" "$tmp"; then
    return 1
  fi

  python3 - "$host" "$port" "$tmp" <<'PY'
import json, sys, subprocess, datetime
host, port, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
pem = open(path, "r", encoding="utf-8", errors="replace").read()
# Extract first cert block
start = pem.find("-----BEGIN CERTIFICATE-----")
end = pem.find("-----END CERTIFICATE-----")
if start < 0 or end < 0:
    sys.exit(1)
leaf = pem[start:end + len("-----END CERTIFICATE-----")] + "\n"
proc = subprocess.run(
    ["openssl", "x509", "-noout", "-subject", "-issuer", "-serial",
     "-dates", "-ext", "subjectAltName"],
    input=leaf, text=True, capture_output=True,
)
text = (proc.stdout or "") + (proc.stderr or "")
def grab(prefix):
    for line in text.splitlines():
        if line.startswith(prefix):
            return line.split("=", 1)[-1].strip() if "=" in line else line[len(prefix):].strip()
    return ""
subject = grab("subject=") or grab("Subject:")
issuer = grab("issuer=") or grab("Issuer:")
serial = grab("serial=")
not_before = grab("notBefore=")
not_after = grab("notAfter=")
sans = []
for line in text.splitlines():
    if "DNS:" in line or "IP Address:" in line:
        for part in line.replace(" ", "").split(","):
            if part.startswith("DNS:"):
                sans.append(part[4:])
            elif part.startswith("IPAddress:"):
                sans.append(part[len("IPAddress:"):])
out = {
    "host": host,
    "port": port,
    "certificate": {
        "subject": subject,
        "issuer": issuer,
        "serial": serial,
        "not_before": not_before,
        "not_after": not_after,
        "sans": sans,
    },
    "tls": {},
    "scanner": "3am-scan/openssl",
    "timeout_flagged": False,
}
print(json.dumps(out))
PY
}

# EXPAND_BEGIN — tests/unit/test_3am_scan_expand.py extracts this block
_expand_targets_from_config() {
  # Reads AgentConfig or legacy scope JSON on stdin; prints host:port lines.
  # Safety default: only singleton CIDRs (/32,/128) + explicit fqdns.
  # With SCAN_EXPAND=1 or config.expand_assigned=true: also walk assigned_cidrs
  # under max_expand_hosts (default 256). Never expand assumed/union cidrs.
  # Env SCAN_EXPAND is passed as argv so python -c can see it.
  local expand_flag="${SCAN_EXPAND:-0}"
  python3 -c '
import json, sys, ipaddress, os
doc = json.load(sys.stdin)
expand_env = (sys.argv[1] if len(sys.argv) > 1 else "0") in ("1", "true", "yes")
expand_cfg = bool(doc.get("expand_assigned"))
do_expand = expand_env or expand_cfg
max_expand = int(doc.get("max_expand_hosts") or 256)
if max_expand < 1:
    max_expand = 256

raw_ports = doc.get("ports") or [443, 993, 995, 8443]
ports = []
for p in raw_ports:
    if isinstance(p, dict):
        try:
            ports.append(int(p.get("port")))
        except (TypeError, ValueError):
            continue
    else:
        try:
            ports.append(int(p))
        except (TypeError, ValueError):
            continue
if not ports:
    ports = [443, 993, 995, 8443]

hosts = []
skipped_budget = 0

# Singletons from effective cidrs (assigned preferred by sink in cidrs)
for c in doc.get("cidrs") or []:
    try:
        net = ipaddress.ip_network(c, strict=False)
    except ValueError:
        continue
    if net.num_addresses == 1:
        hosts.append(str(net.network_address))

for fqdn in doc.get("fqdns") or []:
    if isinstance(fqdn, str) and fqdn.strip() and "*" not in fqdn:
        hosts.append(fqdn.strip().rstrip(".").lower())

if do_expand:
    assigned = list(doc.get("assigned_cidrs") or [])
    # If sink only put assignment into cidrs, use those non-singletons too
    # but ONLY when assigned_cidrs is explicitly present and non-empty.
    for c in assigned:
        try:
            net = ipaddress.ip_network(c, strict=False)
        except ValueError:
            continue
        if net.num_addresses == 1:
            hosts.append(str(net.network_address))
            continue
        addrs = list(net.hosts()) if net.version == 4 else list(net.hosts())
        # IPv4: net.hosts() already skips network/broadcast
        for addr in addrs:
            if len(hosts) >= max_expand:
                skipped_budget += 1
                continue
            hosts.append(str(addr))
        if len(addrs) > max_expand:
            # count remainder beyond what we took in this net
            pass

seen, ordered = set(), []
for h in hosts:
    if h not in seen:
        seen.add(h)
        ordered.append(h)
# Cap total unique hosts at max_expand when expanding
if do_expand and len(ordered) > max_expand:
    skipped_budget += len(ordered) - max_expand
    ordered = ordered[:max_expand]

if skipped_budget:
    print(f"3am-scan: expand budget skipped {skipped_budget} addresses (max_expand_hosts={max_expand})", file=sys.stderr)

for host in ordered:
    for p in ports:
        print(f"{host}:{p}")
' "$expand_flag"
}
# EXPAND_END

_honour_scan_frequency() {
  # Args: config JSON. Exit 0 if ok to scan; exit 2 if too soon.
  local config_json="$1"
  mkdir -p "$SCAN_STATE_DIR"
  local stamp_file="${SCAN_STATE_DIR}/last-scan-${HOST_ID//\//_}"
  python3 - "$config_json" "$stamp_file" <<'PY'
import json, sys, time, os
doc = json.loads(sys.argv[1])
stamp = sys.argv[2]
freq = int(doc.get("max_scan_frequency_seconds") or 0)
if freq <= 0:
    sys.exit(0)
try:
    last = float(open(stamp, "r", encoding="utf-8").read().strip())
except Exception:
    sys.exit(0)
elapsed = time.time() - last
if elapsed < freq:
    remain = int(freq - elapsed)
    print(f"3am-scan: honouring max_scan_frequency_seconds={freq}; retry in ~{remain}s", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PY
}

_touch_scan_stamp() {
  mkdir -p "$SCAN_STATE_DIR"
  local stamp_file="${SCAN_STATE_DIR}/last-scan-${HOST_ID//\//_}"
  date +%s >"$stamp_file"
}

_run_network_probes() {
  # Args: config JSON → prints JSON array of probe results (may be empty).
  # Collect/forward only — do not parse account ids (DATASINK-73).
  local config_json="$1"
  python3 - "$config_json" "$SCAN_TIMEOUT" <<'PY'
import json, sys, base64, urllib.request, urllib.error, ssl, time

doc = json.loads(sys.argv[1])
default_timeout = float(sys.argv[2] or 5)
probes = doc.get("network_probes") or []
out = []

def do_http(url, method="GET", headers=None, body=None, timeout=2.0):
    hdrs = {}
    for h in headers or []:
        if isinstance(h, dict) and h.get("name"):
            hdrs[str(h["name"])] = str(h.get("value") or "")
    data = None
    if body is not None:
        data = body.encode("utf-8") if isinstance(body, str) else body
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    # link-local metadata — no TLS verify concerns for http://
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            raw = resp.read(16384)
            status = getattr(resp, "status", 200)
            resp_headers = {k: v for k, v in resp.headers.items()}
            return status, resp_headers, raw
    except urllib.error.HTTPError as e:
        raw = e.read(16384) if hasattr(e, "read") else b""
        return int(e.code), {}, raw
    except Exception as e:
        return 0, {}, str(e).encode("utf-8", errors="replace")

for probe in probes:
    if not isinstance(probe, dict):
        continue
    pid = probe.get("id") or "unknown"
    url = probe.get("url")
    if not url:
        continue
    method = (probe.get("method") or "GET").upper()
    headers = list(probe.get("headers") or [])
    timeout = float(probe.get("timeout_seconds") or default_timeout)
    token_flow = probe.get("token_flow")
    if isinstance(token_flow, dict) and token_flow.get("url"):
        t_status, _, t_body = do_http(
            token_flow["url"],
            method=(token_flow.get("method") or "PUT").upper(),
            headers=token_flow.get("headers") or [],
            timeout=timeout,
        )
        inject = token_flow.get("inject_header") or "X-aws-ec2-metadata-token"
        if t_status and int(t_status) < 400 and t_body:
            token = t_body.decode("utf-8", errors="replace").strip()
            headers = list(headers) + [{"name": inject, "value": token}]
    status, resp_headers, raw = do_http(
        url, method=method, headers=headers,
        body=probe.get("body"), timeout=timeout,
    )
    # Truncate
    if len(raw) > 16384:
        raw = raw[:16384]
    try:
        body_text = raw.decode("utf-8")
        use_b64 = False
        for ch in body_text:
            if ord(ch) < 9:
                use_b64 = True
                break
    except Exception:
        body_text = ""
        use_b64 = True
    item = {
        "id": pid,
        "parser_id": probe.get("parser_id"),
        "status": int(status) if status else 0,
        "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    if use_b64:
        item["body_b64"] = base64.b64encode(raw).decode("ascii")
    else:
        item["body"] = body_text
    if resp_headers:
        # keep a small echo
        item["headers_echo"] = {k: resp_headers[k] for k in list(resp_headers)[:20]}
    out.append(item)

print(json.dumps(out))
PY
}

_cli_targets_to_hostports() {
  # CLI hosts → host:port using ports from config (or SCAN_PORTS / defaults).
  local config_json="$1"
  shift
  python3 - "$config_json" "${SCAN_PORTS:-}" "$@" <<'PY'
import json, sys
doc = json.loads(sys.argv[1])
ports_env = sys.argv[2]
cli = sys.argv[3:]
if ports_env.strip():
    ports = [int(x) for x in ports_env.split(",") if x.strip()]
else:
    raw_ports = doc.get("ports") or [443, 993, 995, 8443]
    ports = []
    for p in raw_ports:
        if isinstance(p, dict):
            try:
                ports.append(int(p.get("port")))
            except (TypeError, ValueError):
                continue
        else:
            try:
                ports.append(int(p))
            except (TypeError, ValueError):
                continue
if not ports:
    ports = [443, 993, 995, 8443]
for t in cli:
    if ":" in t and not t.startswith("["):
        # host:port (simple; IPv6 bracket form unsupported in CLI v1)
        host, _, port_s = t.rpartition(":")
        try:
            print(f"{host}:{int(port_s)}")
            continue
        except ValueError:
            pass
    for p in ports:
        print(f"{t}:{p}")
PY
}

_post_results() {
  local payload_file="$1"
  local url="${SCAN_SERVER}/v1/at3am/results"
  _info "POST results ${url}"
  _curl_mtls -f -X POST \
    -H "Content-Type: application/json" \
    --data @"$payload_file" \
    "$url"
}

main() {
  # DATASINK-70: always pull config at start of every run (incl. CLI hosts).
  local config_json
  config_json="$(_fetch_config)"
  _info "config pulled (assignment_generation=$(
    printf '%s' "$config_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("assignment_generation",0))' 2>/dev/null || echo 0
  ))"

  if ! _honour_scan_frequency "$config_json"; then
    exit 0
  fi

  local targets=()
  local cli_hosts=()
  if [[ "$#" -gt 0 ]]; then
    cli_hosts=("$@")
    mapfile -t targets < <(_cli_targets_to_hostports "$config_json" "${cli_hosts[@]}")
    # Also include config-derived targets (singletons / expand) merged in
    local cfg_targets=()
    mapfile -t cfg_targets < <(printf '%s' "$config_json" | _expand_targets_from_config)
    targets+=("${cfg_targets[@]+"${cfg_targets[@]}"}")
  else
    mapfile -t targets < <(printf '%s' "$config_json" | _expand_targets_from_config)
  fi

  # Dedupe targets
  if [[ "${#targets[@]}" -gt 0 ]]; then
    mapfile -t targets < <(printf '%s\n' "${targets[@]}" | python3 -c '
import sys
seen=set()
for line in sys.stdin:
    t=line.strip()
    if t and t not in seen:
        seen.add(t)
        print(t)
')
  fi

  local probe_results="[]"
  probe_results="$(_run_network_probes "$config_json")" || probe_results="[]"

  if [[ "${#targets[@]}" -eq 0 ]]; then
    _info "config has no singleton CIDRs/fqdns (and expand off or empty assigned); CLI hosts none"
    _info "still posting network_probe_results if any — nothing to TLS-scan"
  fi

  local scan_id
  scan_id="scan-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  local scanned_at
  scanned_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local results_json="[]"

  for t in "${targets[@]+"${targets[@]}"}"; do
    [[ -n "$t" ]] || continue
    local host="${t%%:*}"
    local port="${t##*:}"
    if [[ "$host" == "$port" ]]; then
      port="443"
    fi
    _info "scanning ${host}:${port}"
    local one
    if one="$(_scan_endpoint "$host" "$port")"; then
      one="$(printf '%s' "$one" | python3 -c "
import json,sys
o=json.load(sys.stdin)
o['host_id']='${HOST_ID}'
o['scan_id']='${scan_id}'
o['scanned_at']='${scanned_at}'
print(json.dumps(o))
")"
      results_json="$(printf '%s\n%s\n' "$results_json" "$one" | python3 -c '
import json,sys
items=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    v=json.loads(line)
    if isinstance(v, list): items.extend(v)
    else: items.append(v)
print(json.dumps(items))
')"
    else
      _info "no TLS cert at ${host}:${port}"
    fi
  done

  local tmp_payload
  tmp_payload="$(mktemp)"
  python3 - "$HOST_ID" "$results_json" "$probe_results" "$scan_id" "$scanned_at" <<'PY' >"$tmp_payload"
import json, sys, socket
host_id, results_raw, probes_raw, scan_id, scanned_at = sys.argv[1:6]
results = json.loads(results_raw)
probes = json.loads(probes_raw) if probes_raw else []
payload = {
    "agent_host": {
        "hostname": socket.gethostname(),
        "scanner": "3am-scan/openssl",
    },
    "scan_id": scan_id,
    "scanned_at": scanned_at,
    "results": results,
    "network_probe_results": probes,
}
print(json.dumps(payload))
PY

  _info "payload hosts scanned: $(printf '%s' "$results_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
  _info "network_probe_results: $(printf '%s' "$probe_results" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
  if [[ "${#targets[@]}" -gt 0 ]] || [[ "$(printf '%s' "$probe_results" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" -gt 0 ]]; then
    _post_results "$tmp_payload"
    _touch_scan_stamp
  else
    _info "nothing to post"
  fi
  rm -f "$tmp_payload"
  _info "done (host_id=${HOST_ID} scan_id=${scan_id})"
}

main "$@"
