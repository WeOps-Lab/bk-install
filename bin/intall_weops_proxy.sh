#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0
source ../weops_version
#IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/weopsproxy:1.0.4"

VERSION="1.0.0"

BIND_IP="127.0.0.1"

PORT=8089

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -r --remote-url           [必填] "prometheus remote url" ]
            [ -c --consul-addr          [必填] "consul地址" ]
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

(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --remote-url | -r)
            shift
            REMOTE_URL=$1
            ;;
        --consul-addr | -c)
            shift
            CONSUL_ADDR=$1
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

# 检查必填参数
[[ -z $REMOTE_URL ]] && error "缺少必填参数: --remote-url"
[[ -z $CONSUL_ADDR ]] && error "缺少必填参数: --consul-addr"

if [[ -d /data/bkce/logs/weopsproxy ]]; then
    log "weopsproxy日志目录已存在"
else
    install -d -g 1001 -o 1001 /data/bkce/logs/weopsproxy
fi

if [[ $(docker ps -a|grep weops-proxy) ]]; then
    warning "已存在weops-proxy容器,将删除"
    docker rm -f weops-proxy
fi

docker run -d -e CONSUL_ADDR=$CONSUL_ADDR \
    -e REMOTE_URL=$REMOTE_URL \
    --net=host --restart=always --name=weops-proxy \
    -v /data/bkce/logs/weopsproxy:/app/log \
    $PROXY_IMAGE