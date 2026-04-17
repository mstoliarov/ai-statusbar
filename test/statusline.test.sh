#!/usr/bin/env bash
set -e
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../statusline.sh"
FIXTURE="$SCRIPT_DIR/fixtures/status-openrouter.json"

# Convert to Windows path for Python on Windows (Git Bash has cygpath)
FIXTURE_WIN="$FIXTURE"
if command -v cygpath >/dev/null 2>&1; then
    FIXTURE_WIN=$(cygpath -w "$FIXTURE")
fi

pass() { echo "✔ $1"; }
fail() { echo "✖ $1"; echo "  $2"; exit 1; }

# Write a temp Python server script
TMPPY=$(mktemp /tmp/mock_server_XXXXXX.py)
cat > "$TMPPY" <<PYEOF
import http.server, sys, threading, time
FIXTURE = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            with open(FIXTURE, 'rb') as f: body = f.read()
            self.send_response(200); self.send_header('content-type','application/json'); self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
httpd = http.server.HTTPServer(('127.0.0.1', 11499), H)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
time.sleep(3600)
PYEOF

# Start a tiny mock /status server on port 11499
python3 "$TMPPY" "$FIXTURE_WIN" &
MOCK_PID=$!
trap "kill \$MOCK_PID 2>/dev/null; rm -f \$TMPPY" EXIT

# Wait for server to be ready (up to 3 seconds)
for i in $(seq 1 30); do
    if curl -s --max-time 0.2 http://127.0.0.1:11499/status >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

# Verify server is up
curl -s --max-time 1 http://127.0.0.1:11499/status >/dev/null 2>&1 || { echo "FATAL: mock server not responding"; exit 1; }

# Test: statusline picks up provider from /status
INPUT='{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Nemotron"},"context_window":{"used_percentage":5,"context_window_size":200000}}'
output=$(CLAUDE_STATUS_URL=http://127.0.0.1:11499/status bash "$STATUSLINE" <<< "$INPUT" 2>&1)

# Check for provider icon — use a unique prefix that only appears when icon is rendered
# (grep for the blue ANSI code followed by the display label, proving icon was prepended)
echo "$output" | grep -qE $'\033\[34m.+or ' || fail "provider icon missing (no blue+icon+display)" "$output"
pass "provider icon rendered"

echo "$output" | grep -q "128k" || fail "context window from /status not used" "$output"
pass "context_window from /status"

echo "$output" | grep -qP '\033\[34m|\x1b\[34m' || fail "blue color for OpenRouter not applied" "$output"
pass "provider color applied"

echo "$output" | grep -q "or " || fail "provider display label 'or' missing" "$output"
pass "provider display label"

echo "$output" | grep -q "usage/d" || fail "usage/d block missing" "$output"
pass "usage/d block present"

echo "$output" | grep -q "50%" || fail "usage/d percentage missing" "$output"
pass "usage/d percentage rendered"

# usage/h should be absent since short is null
if echo "$output" | grep -q "usage/h"; then
    fail "usage/h present when short=null" "$output"
fi
pass "usage/h hidden when short=null"

echo "All tests passed"
