#!/usr/bin/env bash
# This Let's Encrypt pre-validation hook is to be used for the DNS-01 challenge with
# BOAST's main domain. It's made to work with the Dockerfile in this directory and may
# need some changes for customised use cases.
#
# Certbot calls this hook once per challenge. For wildcard + apex certificates, two
# challenges share the same _acme-challenge TXT record, so this hook accumulates all
# validation values in a temp file and restarts the DNS container with all of them.
#
# This hook will only be run if the certificate is due for renewal, so certbot can be
# run frequently (e.g. as a cron job) without unnecessarily stopping BOAST.
#
# Doc on how to use this with the provided Dockerfile (and more):
# https://github.com/marcohextor/boast/blob/master/docs/deploying.md
#
set -euo pipefail

if [ -z "${CERTBOT_VALIDATION:-}" ]; then
	echo "error: validation is empty"
	exit 1
fi

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
_txt_file="/tmp/boast-acme-txt-values"

# Accumulate validation values across hook invocations.
echo "${CERTBOT_VALIDATION}" >> "${_txt_file}"

# Build -dns_txt flags for all accumulated values.
_dns_txt_flags=()
while IFS= read -r val; do
	_dns_txt_flags+=(-dns_txt "$val")
done < "${_txt_file}"

# Ignoring errors with `|| true` in case containers are not running or do not exist.

# Make sure everything is stopped.
${_engine} stop ${_boast_container} 2>/dev/null || true
${_engine} stop ${_boast_dns_container} 2>/dev/null || true

# Make sure the BOAST's DNS temporary container does not exist.
${_engine} container rm ${_boast_dns_container} 2>/dev/null || true

# Run the DNS receiver with all challenge TXT records.
${_engine} run -d --name ${_boast_dns_container} -p 53:53/udp ${_boast_img} ./boast -dns_only "${_dns_txt_flags[@]}"
