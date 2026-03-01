#!/usr/bin/env bash
# This Let's Encrypt pre-validation hook is to be used for the DNS-01 challenge with
# BOAST's main domain. It's made to work with the Dockerfile in this directory and may
# need some changes for customised use cases.
#
# This hook will only be run if the certificate is due for renewal, so certbot can be
# run frequently (e.g. as a cron job) without unnecessarily stopping BOAST.
#
# Doc on how to use this with the provided Dockerfile (and more):
# https://github.com/marcohextor/boast/blob/master/docs/deploying.md
#
if [ -z "$CERTBOT_VALIDATION"  ]
then
	echo "error: validation is empty"
	exit -1
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

# Ignoring errors with `|| true` in case containers are not running or do not exist.

# Make sure everything is stopped
${_engine} stop ${_boast_container} || true
${_engine} stop ${_boast_dns_container} || true

# Make sure the BOAST's DNS temporary container does not exist.
${_engine} container rm ${_boast_dns_container} || true

# Run the DNS receiver with the challenge's TXT record.
${_engine} run -d --name ${_boast_dns_container} -p 53:53/udp ${_boast_img} ./boast -dns_only -dns_txt ${CERTBOT_VALIDATION}
