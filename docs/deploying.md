# Deploying

## Quick start (Cloudflare)

This path assumes you have a domain dedicated to BOAST, managed through Cloudflare.

### 1. DNS configuration

At your **domain registrar** (not Cloudflare), set the domain's nameservers to point to your BOAST server by creating glue records:

```
ns1.example.com  ->  YOUR_SERVER_IP
ns2.example.com  ->  YOUR_SERVER_IP
```

And NS records:

```
example.com.      IN      NS      ns1.example.com.
example.com.      IN      NS      ns2.example.com.
```

This delegates all DNS for the domain to BOAST. Cloudflare is not in the DNS or HTTP path for this domain.

### 2. TLS certificate

Generate a Cloudflare Origin Certificate (SSL/TLS > Origin Server > Create Certificate) for `*.example.com` and `example.com`. Save the files:

```
mkdir -p tls
# Save certificate as tls/fullchain.pem
# Save private key as tls/privkey.pem
```

Note: Cloudflare Origin Certificates are signed by Cloudflare's CA, which is not publicly trusted. This is fine for BOAST's use case -- interaction clients don't validate certificates, and you can use `curl -k` for the API.

### 3. Configure

```
cp .env.example .env
```

Edit `.env` and set `DOMAIN` and `PUBLIC_IP`. Review the other values -- `HMAC_KEY` and `STATUS_URL_PATH` are auto-generated if unset, but you should persist them in `.env` after the first deploy.

### 4. Deploy

```
./deploy.sh
```

This validates your config and TLS files, builds the container image, generates `boast.toml`, and starts BOAST with automatic restart on reboot.

### 5. Verify

```
curl -k https://example.com:2096/
dig @example.com example.com A
curl http://example.com/
```

## Non-Cloudflare deployment (Let's Encrypt)

This path uses certbot's DNS-01 challenge. BOAST's DNS receiver handles the ACME challenge.

### 1. DNS and initial setup

Follow step 1 above (DNS configuration), then configure `.env` (step 3 above).

Build the image and generate the config (without starting the server):

```
./deploy.sh build
```

### 2. Initial certificate issuance

Run BOAST in DNS-only mode to handle the ACME challenge:

```
podman run -d --name boast-dns -p 53:53/udp boast ./boast -dns_only
```

Run certbot with the pre-validation hook:

```
certbot certonly --agree-tos --manual --preferred-challenges=dns \
    -d '*.example.com' -d example.com \
    --manual-auth-hook ./build/certbot-dns-01-pre-validation-hook.sh
```

Stop the DNS-only container and copy the issued certificates:

```
podman stop boast-dns && podman rm boast-dns
mkdir -p tls
cp /etc/letsencrypt/live/example.com/fullchain.pem tls/
cp /etc/letsencrypt/live/example.com/privkey.pem tls/
```

Now deploy the full server:

```
./deploy.sh
```

### 3. Certificate renewal

Automate renewal with a cron job using both hook scripts:

```
certbot certonly -n --agree-tos --manual-public-ip-logging-ok --manual \
    --preferred-challenges=dns -d '*.example.com' \
    --manual-auth-hook /path/to/build/certbot-dns-01-pre-validation-hook.sh \
    --renew-hook /path/to/build/certbot-dns-01-renew-hook.sh
```

The hooks handle stopping, certificate copying, and restarting BOAST automatically. They only run when renewal is actually due.

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

## Notes

- **`--restart=unless-stopped`**: Production containers restart on reboot and on crash, but stay stopped after `./deploy.sh stop`. This is deliberate.
- **`HMAC_KEY` persistence**: If not set in `.env`, `deploy.sh` auto-generates one. Add the printed value to `.env` or existing test IDs will be invalidated on redeployment.
- **`STATUS_URL_PATH` persistence**: Same as `HMAC_KEY` -- auto-generated if unset, but persist it or you lose access to the status page.
- **Container engine**: Defaults to `podman`, falls back to `docker`. Override with `CONTAINER_ENGINE` in `.env` or environment.
- **`REAL_IP_HEADER`**: Only set this if BOAST is behind a reverse proxy (e.g. `CF-Connecting-IP` for Cloudflare, `X-Real-IP` for nginx). If unset, BOAST records the direct connection IP.

## Configuration reference

See [boast-configuration.md](boast-configuration.md) for the full configuration file reference and command-line flags.
