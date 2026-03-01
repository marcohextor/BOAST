#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source .env early so CONTAINER_ENGINE is available to all subcommands.
# Failures are ignored -- load_env() validates required vars for prod/build.
# shellcheck source=/dev/null
[ -f .env ] && source .env || true

# Detect container engine. Respects CONTAINER_ENGINE env var (including from .env).
detect_engine() {
    if [ -n "${CONTAINER_ENGINE:-}" ]; then
        echo "$CONTAINER_ENGINE"
    elif command -v podman &>/dev/null; then
        echo "podman"
    elif command -v docker &>/dev/null; then
        echo "docker"
    else
        echo "error: no container engine found (podman or docker)" >&2
        exit 1
    fi
}

cmd_stop() {
    local engine
    engine="$(detect_engine)"
    echo "Stopping boast container..."
    $engine stop boast 2>/dev/null || true
    $engine rm boast 2>/dev/null || true
    echo "Done."
}

# Load .env and set derived values. Used by both build and prod.
load_env() {
    if [ ! -f .env ]; then
        echo "error: .env file not found. Copy .env.example to .env and configure it." >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source .env

    if [ -z "${DOMAIN:-}" ]; then
        echo "error: DOMAIN is not set in .env" >&2
        exit 1
    fi
    if [ -z "${PUBLIC_IP:-}" ]; then
        echo "error: PUBLIC_IP is not set in .env" >&2
        exit 1
    fi

    if [ -z "${HMAC_KEY:-}" ]; then
        HMAC_KEY="$(openssl rand -base64 32)"
        echo "WARNING: HMAC_KEY was not set. Auto-generated: $HMAC_KEY"
        echo "Add this to your .env to persist it across deployments."
    fi

    if [ -z "${STATUS_URL_PATH:-}" ]; then
        STATUS_URL_PATH="$(openssl rand -hex 13)"
        echo "STATUS_URL_PATH auto-generated: $STATUS_URL_PATH"
        echo "Add this to your .env to persist it across deployments."
    fi
}

generate_toml_prod() {
    local real_ip_line=""
    if [ -n "${REAL_IP_HEADER:-}" ]; then
        real_ip_line=$'\n  real_ip_header = "'"${REAL_IP_HEADER}"'"'
    fi

    cat > boast.toml <<TOML
[storage]
  max_events = 1_000_000
  max_events_by_test = 100
  max_dump_size = "80KB"
  hmac_key = "${HMAC_KEY}"

  [storage.expire]
    ttl = "24h"
    check_interval = "1h"
    max_restarts = 100

[api]
  host = "0.0.0.0"
  tls_port = 2096
  tls_cert = "./tls/fullchain.pem"
  tls_key = "./tls/privkey.pem"

  [api.status]
    url_path = "${STATUS_URL_PATH}"

[http_receiver]
  host = "0.0.0.0"
  ports = [80, 8080]${real_ip_line}

  [http_receiver.tls]
    ports = [443, 8443]
    cert = "./tls/fullchain.pem"
    key = "./tls/privkey.pem"

[dns_receiver]
  host = "0.0.0.0"
  ports = [53]
  domain = "${DOMAIN}"
  public_ip = "${PUBLIC_IP}"
TOML
    echo "Generated boast.toml"
}

generate_toml_dev() {
    cat > boast.toml <<'TOML'
[storage]
  max_events = 1_000_000
  max_events_by_test = 100
  max_dump_size = "80KB"
  hmac_key = "testing"

  [storage.expire]
    ttl = "24h"
    check_interval = "1h"
    max_restarts = 100

[api]
  host = "0.0.0.0"
  tls_port = 2096
  tls_cert = "./tls/cert.pem"
  tls_key = "./tls/key.pem"

[http_receiver]
  host = "0.0.0.0"
  ports = [8080]

  [http_receiver.tls]
    ports = [8443]
    cert = "./tls/cert.pem"
    key = "./tls/key.pem"

[dns_receiver]
  host = "0.0.0.0"
  ports = [8053]
  domain = "localhost"
  public_ip = "127.0.0.1"
TOML
    echo "Generated dev boast.toml"
}

do_build() {
    local engine="$1" skip_test="$2"
    echo "Building image with $engine..."
    if [ "$skip_test" = "1" ]; then
        $engine build --build-arg SKIP_TEST=1 -t boast -f build/Dockerfile .
    else
        $engine build -t boast -f build/Dockerfile .
    fi
}

cmd_build() {
    local skip_test="${1:-0}"
    load_env
    local engine; engine="$(detect_engine)"
    generate_toml_prod
    do_build "$engine" "$skip_test"
    echo ""
    echo "Image built. Config generated. Ready for ./deploy.sh when TLS certs are in place."
}

cmd_dev() {
    local skip_test="${1:-0}"
    local engine; engine="$(detect_engine)"
    generate_toml_dev
    do_build "$engine" "$skip_test"

    $engine stop boast 2>/dev/null || true
    $engine rm boast 2>/dev/null || true

    echo "Starting dev container..."
    $engine run -d --name boast \
        -p 8053:8053/udp \
        -p 8080:8080 \
        -p 8443:8443 \
        -p 2096:2096 \
        -v "$PWD/testdata:/app/tls:ro" \
        boast

    echo ""
    echo "Dev container running. Verify with:"
    echo "  curl -k https://localhost:2096/"
    echo "  curl http://localhost:8080/"
    echo "  dig @localhost -p 8053 localhost A"
}

cmd_prod() {
    local skip_test="${1:-0}"
    load_env
    local engine; engine="$(detect_engine)"

    if [ ! -d tls ] || [ ! -f tls/fullchain.pem ] || [ ! -f tls/privkey.pem ]; then
        echo "error: TLS certificates not found. Expected tls/fullchain.pem and tls/privkey.pem" >&2
        echo "See docs/deploying.md for certificate setup." >&2
        echo "If you need to build the image first (e.g. for Let's Encrypt DNS-01), use: ./deploy.sh build" >&2
        exit 1
    fi

    generate_toml_prod
    do_build "$engine" "$skip_test"

    $engine stop boast 2>/dev/null || true
    $engine rm boast 2>/dev/null || true

    echo "Starting production container..."
    $engine run -d --name boast \
        --restart=unless-stopped \
        -p 53:53/udp \
        -p 80:80 \
        -p 443:443 \
        -p 2096:2096 \
        -p 8080:8080 \
        -p 8443:8443 \
        -v "$PWD/tls:/app/tls:ro" \
        boast

    echo ""
    echo "BOAST is running."
    echo "  --restart=unless-stopped: container survives reboots (stop with ./deploy.sh stop)"
    echo "  Domain: $DOMAIN"
    echo "  Public IP: $PUBLIC_IP"
    echo "  Status page: https://$DOMAIN:2096/$STATUS_URL_PATH"
}

# Parse arguments
SKIP_TEST=0
MODE=""

for arg in "$@"; do
    case "$arg" in
        dev)    MODE="dev" ;;
        stop)   MODE="stop" ;;
        build)  MODE="build" ;;
        --no-test) SKIP_TEST=1 ;;
        *)
            echo "Usage: $0 [dev|stop|build] [--no-test]" >&2
            exit 1
            ;;
    esac
done

case "${MODE:-prod}" in
    dev)   cmd_dev "$SKIP_TEST" ;;
    stop)  cmd_stop ;;
    build) cmd_build "$SKIP_TEST" ;;
    prod)  cmd_prod "$SKIP_TEST" ;;
esac
