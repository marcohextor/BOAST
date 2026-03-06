#!/usr/bin/env bash
# This Let's Encrypt post-validation hook is to be used for the DNS-01 challenge with
# BOAST's main domain. It's made to work with the Dockerfile in this directory and may
# need some changes for customised use cases.
#
# This hook will only be run if the certificate is due for renewal, so certbot can be
# run frequently (e.g. as a cron job) without unnecessarily stopping BOAST.
#
# Doc on how to use this with the provided Dockerfile and more:
# https://github.com/marcohextor/boast/blob/master/docs/deploying.md
#
set -euo pipefail

if [ -z "${RENEWED_LINEAGE:-}" ]; then
	echo "error: renewed lineage is empty"
	exit 1
fi

# Clean up accumulated TXT values from pre-validation hook.
rm -f /tmp/boast-acme-txt-values

if [ -n "${CONTAINER_ENGINE:-}" ]; then
	_engine="$CONTAINER_ENGINE"
elif command -v podman &>/dev/null; then
	_engine="podman"
else
	_engine="docker"
fi
_boast_img="boast"
_boast_container="boast"
_boast_dns_container="boast-dns"
_tls_certificate="${RENEWED_LINEAGE}/fullchain.pem"
_tls_privkey="${RENEWED_LINEAGE}/privkey.pem"
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_boast_tls="$(dirname "$_script_dir")/tls"

# Ignoring errors with `|| true` in case containers are not running or do not exist.

# Make sure everything is stopped.
${_engine} stop ${_boast_container} || true
${_engine} stop ${_boast_dns_container} || true

# Make sure the BOAST container does not exist.
${_engine} container rm ${_boast_container} || true

# Copy TLS files to BOAST's TLS directory.
mkdir -p ${_boast_tls}
cp ${_tls_certificate} ${_tls_privkey} ${_boast_tls}

# Run the BOAST's main container.
${_engine} run -d --name ${_boast_container} --restart=unless-stopped -p 53:53/udp -p 80:80 -p 443:443 -p 2096:2096 -p 8080:8080 -p 8443:8443 -v ${_boast_tls}:/app/tls ${_boast_img}
