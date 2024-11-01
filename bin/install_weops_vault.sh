#!/bin/bash
set -euo pipefail
PROGRAM=$(basename "$0")
EXITCODE=0

source ../weops_version
# IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/vault:latest"

VERSION="1.0.0"
INIT=false
usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -s --server             [必填] "mysql的地址, 一般为consul服务" ]
            [ -p --password         [必填] "mysql的密码" ]
            [ -u --user             [必填] "mysql的用户名" ]
            [ -P --port             [必填] "mysql的端口" ]
            [ -i --init             [必填] "是否init节点" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

error () {
    echo "$@" 1>&2
    usage_and_exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        --init | -i)
            INIT=true
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --server | -s)
            shift
            MYSQL_HOST=$1
            ;;
        --password | -p)
            shift
            MYSQL_PASSWORD=$1
            ;;
        --port | -P)
            shift
            MYSQL_PORT=$1
            ;;
        --user | -u)
            shift
            MYSQL_USER=$1
            ;;
        -*)
            error "不可识别的参数: $1"
            ;;
        *) 
            break
            ;;
    esac
    shift 
done 

mkdir -p /data/vault/config

if [[ -f /data/vault/config/vault.hcl ]]; then
    warning "vault.hcl already exists, overwrite it."
fi

cat << EOF > /data/vault/config/vault.hcl
backend "mysql" {
    address = "${MYSQL_HOST}:${MYSQL_PORT}"
    username = "${MYSQL_USER}"
    password = "${MYSQL_PASSWORD}"
}

listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = 1
}
ui = false
disable_mlock = true
EOF

if [[ $(docker ps -a | grep vault) ]]; then
    warning "vault container already exists, delete it."
    docker rm -f vault
fi

docker run -d --restart=always --net=host \
-v /data/vault/config/vault.hcl:/etc/vault.hcl \
--name=vault \
docker-bkrepo.cwoa.net/ce1b09/weops-docker/vault server -config=/etc/vault.hcl

if [[ "$INIT" == true ]]; then
    # wait for vault online
    sleep 30
    log "init vault"
    docker exec vault sh -c "export VAULT_ADDR=http://127.0.0.1:8200 vault operator init"
    docker exec vault sh -c "export VAULT_ADDR=http://127.0.0.1:8200 && vault operator init -key-shares=1 -key-threshold=1" > /data/vault.secret
fi