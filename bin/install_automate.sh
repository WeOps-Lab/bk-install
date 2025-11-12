#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0

source /data/install/weops_version
# IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/auto-mate:v1.0.21-fix6"

VERSION="1.0.0"

BIND_IP="127.0.0.1"

PORT=8089

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -r --redis-server         [必填] "redis服务器ip" ]
            [ -P --redis-port           [必填] "redis服务器端口" ]
            [ -a --auth                 [必填] "redis密码" ]
            [ -v --vault-url            [必填] "vault地址"]
            [ -t --vault-token          [必填] "vault token" ]
            [ -w --remote-write         [必填] "prometheus remote write地址" ]
            [ -u --remote-user          [必填] "prometheus remote write用户名" ]
            [ -s --remote-password      [必填] "prometheus remote write密码" ]
            [ -b --bind-ip              [必填] "automate的接入点ip"]
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
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --redis-server | -r)
            shift
            REDIS_SERVER=$1
            ;;
        --redis-port | -P)
            shift
            REDIS_PORT=$1
            ;;
        --auth | -a)
            shift
            REDIS_AUTH=$1
            ;;
        --vault-url | -v)
            shift
            VAULT_URL=$1
            ;;
        --vault-token | -t)
            shift
            VAULT_TOKEN=$1
            ;;
        --remote-write | -w)
            shift
            REMOTE_WRITE=$1
            ;;
        --remote-user | -u)
            shift
            REMOTE_USER=$1
            ;;
        --remote-password | -s)
            shift
            REMOTE_PASSWORD=$1
            ;;
        --bind-ip | -b)
            shift
            BIND_IP=$1
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

if [ -z "$REDIS_SERVER" ]; then
    error "缺少参数: --redis-server"
fi

if [ -z "$REDIS_PORT" ]; then
    error "缺少参数: --redis-port"
fi

if [ -z "$REDIS_AUTH" ]; then
    error "缺少参数: --auth"
fi

if [ -z "$VAULT_URL" ]; then
    error "缺少参数: --vault-url"
fi

if [ -z "$VAULT_TOKEN" ]; then
    error "缺少参数: --vault-token"
fi

if [ -z "$REMOTE_WRITE" ]; then
    error "缺少参数: --remote-write"
fi

if [ -z "$REMOTE_USER" ]; then
    error "缺少参数: --remote-user"
fi

if [ -z "$REMOTE_PASSWORD" ]; then
    error "缺少参数: --remote-password"
fi

if [ -z "$BIND_IP" ]; then
    error "缺少参数: --bind-ip"
fi

if [[ -d /data/bkce/logs/automate/automate ]]; then
    warning "automate日志目录已存在"
else
    install -d -o 1001 -g 1001 /data/bkce/logs/automate/automate
fi

if [[ $(docker ps -a|grep auto-mate) ]]; then
    warning "automate容器已经存在, 将删除旧容器"
    docker rm -f auto-mate
fi

docker run -d --restart=always --net=host \
-e APP_PORT=$PORT \
-e CELERY_BROKER=redis://:${REDIS_AUTH}@${REDIS_SERVER}:${REDIS_PORT}/11 \
-e CELERY_BACKEND=redis://:${REDIS_AUTH}@${REDIS_SERVER}:${REDIS_PORT}/14 \
-e VAULT_URL=${VAULT_URL} \
-e VAULT_TOKEN=${VAULT_TOKEN} \
-e REDIS_URL=redis://:${REDIS_AUTH}@${REDIS_SERVER}:${REDIS_PORT}/14 \
-e WEOPS_PATH=http://paas.service.consul/o/weops_saas \
-e PROMETHEUS_RW_URL=${REMOTE_WRITE} \
-e PROMETHEUS_USER=${REMOTE_USER} \
-e PROMETHEUS_PWD=${REMOTE_PASSWORD} \
-e ACCESS_POINT_URL=${BIND_IP}:$PORT \
-e ENABLE_OTEL=false \
-v /data/bkce/logs/automate:/app/logs \
--name=auto-mate ${AUTOMATE_IMAGE}