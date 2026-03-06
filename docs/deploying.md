# Deploying

## Quick start (Let's Encrypt)

This is the recommended path. BOAST acts as its own DNS server, so it can handle the ACME DNS-01 challenge directly.

### 1. DNS configuration

At your **domain registrar**, delegate the domain to your BOAST server by creating glue records and NS records:

```
ns1.example.com  ->  YOUR_SERVER_IP
ns2.example.com  ->  YOUR_SERVER_IP

example.com.      IN      NS      ns1.example.com.
example.com.      IN      NS      ns2.example.com.
```

This delegates all DNS for the domain to BOAST.

### 2. Configure

```
cp .env.example .env
```

Edit `.env` and set `DOMAIN` and `PUBLIC_IP`. Review the other values -- `HMAC_KEY` and `STATUS_URL_PATH` are auto-generated if unset, but you should persist them in `.env` after the first deploy.

### 3. Generate config and build

Generate `boast.toml` from `.env` and build the container image:

```
./deploy.sh config
./deploy.sh build
```

`boast.toml` is mounted into the container at runtime, so you can edit it directly for custom settings (e.g. adjusting `max_events`, `ttl`, receiver ports). Changes take effect on container restart -- no rebuild needed.

### 4. Obtain TLS certificate

Run certbot with BOAST's DNS-01 hooks. The `--pre-hook` clears state from any previous run, and the `--manual-auth-hook` accumulates challenge tokens so that wildcard + apex certificates (which require two simultaneous TXT records) work correctly.

Running as root (certs go to `/etc/letsencrypt/`):

```
sudo certbot certonly --agree-tos --manual --preferred-challenges=dns \
    -d '*.example.com' -d example.com \
    --pre-hook 'rm -f /tmp/boast-acme-txt-values' \
    --manual-auth-hook /path/to/build/certbot-dns-01-pre-validation-hook.sh
```

If running rootless (recommended with rootless podman), use custom directories instead:

```
certbot certonly --agree-tos --manual --preferred-challenges=dns \
    -d '*.example.com' -d example.com \
    --pre-hook 'rm -f /tmp/boast-acme-txt-values' \
    --manual-auth-hook ./build/certbot-dns-01-pre-validation-hook.sh \
    --config-dir ~/certbot --work-dir ~/certbot/work --logs-dir ~/certbot/logs
```

Stop any temporary DNS container and copy the issued certificates:

```
podman stop boast-dns 2>/dev/null; podman rm boast-dns 2>/dev/null
mkdir -p tls
# Adjust the path: ~/certbot/live/ for rootless, /etc/letsencrypt/live/ for root
CERTDIR=~/certbot/live/example.com
cp "$CERTDIR/fullchain.pem" tls/
cp "$CERTDIR/privkey.pem" tls/
```

### 5. Deploy

```
./deploy.sh
```

### 6. Verify

```
curl -k https://example.com:2096/
dig @example.com example.com A
curl http://example.com/
```

### 7. Certificate renewal

Automate renewal with a cron job using both hook scripts. Add `--config-dir`, `--work-dir`, and `--logs-dir` if running rootless (as in step 4):

```
certbot certonly -n --agree-tos --manual-public-ip-logging-ok --manual \
    --preferred-challenges=dns \
    -d '*.example.com' -d example.com \
    --pre-hook 'rm -f /tmp/boast-acme-txt-values' \
    --manual-auth-hook /path/to/build/certbot-dns-01-pre-validation-hook.sh \
    --renew-hook /path/to/build/certbot-dns-01-renew-hook.sh
```

The hooks handle stopping, certificate copying, and restarting BOAST automatically. They only run when renewal is actually due.

## Alternative: Cloudflare Origin Certificate

If you only use BOAST's HTTP/HTTPS receivers (not DNS) and your domain is managed through Cloudflare, you can skip Let's Encrypt and use a Cloudflare Origin Certificate instead.

Generate one at SSL/TLS > Origin Server > Create Certificate for `*.example.com` and `example.com`, then save the files as `tls/fullchain.pem` and `tls/privkey.pem`.

Note: Origin Certificates are not publicly trusted. Interaction clients don't validate certificates so this is fine for BOAST's use case, but API access requires `curl -k`. DNS delegation (step 1 above) is still required for the DNS receiver to work, and Cloudflare must not proxy the domain (DNS-only / grey cloud).

## Local development

```
./deploy.sh dev
```

Uses high ports (8053, 8080, 8443, 2096), test certificates from `testdata/`, and no restart policy. Verify with:

```
curl -k https://localhost:2096/
curl http://localhost:8080/
dig @localhost -p 8053 localhost A
```

## Stopping

```
./deploy.sh stop
```

## Rebuilding without tests

```
./deploy.sh --no-test
./deploy.sh dev --no-test
```

## Changing configuration

`boast.toml` is the runtime configuration file, mounted into the container as a volume. To change settings:

1. Edit `boast.toml` directly
2. Restart: `./deploy.sh stop && ./deploy.sh`

To regenerate `boast.toml` from `.env` (resets any manual edits):

```
./deploy.sh config
```

## Notes

- **`--restart=unless-stopped`**: Production containers restart on reboot and on crash, but stay stopped after `./deploy.sh stop`. This is deliberate.
- **`HMAC_KEY` persistence**: If not set in `.env`, `deploy.sh` auto-generates one. Add the printed value to `.env` or existing test IDs will be invalidated on redeployment.
- **`STATUS_URL_PATH` persistence**: Same as `HMAC_KEY` -- auto-generated if unset, but persist it or you lose access to the status page.
- **Container engine**: Defaults to `podman`, falls back to `docker`. Override with `CONTAINER_ENGINE` in `.env` or environment.
- **`REAL_IP_HEADER`**: Only set this if BOAST is behind a reverse proxy (e.g. `CF-Connecting-IP` for Cloudflare, `X-Real-IP` for nginx). If unset, BOAST records the direct connection IP.
- **Privileged ports**: If running rootless containers, you may need `sysctl net.ipv4.ip_unprivileged_port_start=53` (or add it to `/etc/sysctl.d/`).
- **Port 53 conflict**: On Ubuntu/systemd, `systemd-resolved` binds port 53. Stop it with `systemctl stop systemd-resolved && systemctl disable systemd-resolved` and set a real nameserver in `/etc/resolv.conf`.

## Configuration reference

See [boast-configuration.md](boast-configuration.md) for the full configuration file reference and command-line flags.
