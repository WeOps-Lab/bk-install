#!/bin/bash
source /data/install/functions
source /data/install/tools.sh

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

_generate_weopsconsul_envvars() {
    echo "WEOPS_CONSUL_KEYSTR_32BYTES=$(consul keygen)"
}

rndpw () {
    </dev/urandom tr -dc _A-Za-z0-9"$2" | head -c"${1:-12}"
}

_generate_prometheus_envvars() {
    echo "WEOPS_PROMETHEUS_USER=admin"
    echo "WEOPS_KAFKA_ADAPTER_USER=admin"
    PROMETHEUS_PASSWORD=$(rndpw 12)
    echo "WEOPS_PROMETHEUS_PASSWORD=${PROMETHEUS_PASSWORD}"
    echo "WEOPS_KAFKA_ADAPTER_PASSWORD=${PROMETHEUS_PASSWORD}"
    python <<EOF
import bcrypt
import base64
salt = bcrypt.gensalt()
password = "${PROMETHEUS_PASSWORD}"
hashed_password = bcrypt.hashpw(password.encode('utf-8'), salt)
base64_hashed_password = base64.b64encode(hashed_password).decode('utf-8')
print("WEOPS_PROMETHEUS_SECRET_BASE64=" + base64_hashed_password)
print("WEOPS_KAFKA_ADAPTER_SECRET=" + base64_hashed_password)
EOF
}

_generate_minio_envvars() {
    MINIO_ACCESS_KEY=weops
    MINIO_SECRET_KEY=$(rndpw 12)
    echo "WEOPS_MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}"
    echo "WEOPS_MINIO_SECRET_KEY=${MINIO_SECRET_KEY}"
}

_generate_onlyoffice_envvars() {
    WEOPS_ONLYOFFICE_JWT_SECRET=$(rndpw 32)
    echo "WEOPS_ONLYOFFICE_JWT_SECRET=${WEOPS_ONLYOFFICE_JWT_SECRET}"
    echo "WEOPS_ONLYOFFICE_DOC_PORT=8084"
    echo "WEOPS_ONLYOFFICE_WEB_PORT=9002"
}

_generate_age_envvars() {
    WEOPS_AGE_DB_PORT=5432
    WEOPS_AGE_DB_NAME=weops
    WEOPS_AGE_DB_USER=weops
    WEOPS_AGE_DB_PASSWORD=$(rndpw 16)
    echo "WEOPS_AGE_DB_PASSWORD=${WEOPS_AGE_DB_PASSWORD}"
    echo "WEOPS_AGE_DB_PORT=${WEOPS_AGE_DB_PORT}"
    echo "WEOPS_AGE_DB_NAME=${WEOPS_AGE_DB_NAME}"
    echo "WEOPS_AGE_DB_USER=${WEOPS_AGE_DB_USER}"
}

if [[ -f ${HOME}/.tag/weops.env ]]; then
    echo "tag weops.env exists, skipping"
    exit 0
else 
    echo "Generating weopsconsul envvars"
    _generate_weopsconsul_envvars | tee -a /data/install/bin/04-final/weops.env
    echo "Generating prometheus envvars"
    _generate_prometheus_envvars | tee -a /data/install/bin/04-final/weops.env
    echo "Generating minio envvars"
    _generate_minio_envvars | tee -a /data/install/bin/04-final/weops.env
    echo "Generating onlyoffice envvars"
    _generate_onlyoffice_envvars | tee -a /data/install/bin/04-final/weops.env
    echo "Generating age envvars"
    _generate_age_envvars | tee -a /data/install/bin/04-final/weops.env
    echo "weops.env generated"
    make_tag weops.env
    echo "weops.env tagged"
fi
