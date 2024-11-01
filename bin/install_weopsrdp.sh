#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0

source ../weops_version
# GUACD_IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/guacd:latest"
# WEOPSRDP_IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/weopsrdp:latest"

VERSION="1.0.0"

BIND_IP="127.0.0.1"

PORT=8089

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -s --site-url             [必填] "记录远程日志的url" ]
            [ -I --inner-host           [必填] "回调蓝鲸的内部域名" ]
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
        --site-url | -s)
            shift
            SITE_URL=$1
            ;;
        --inner-host | -I)
            shift
            INNER_HOST=$1
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
[ -z "$SITE_URL" ] && error "必须提供记录远程日志的url"
[ -z "$INNER_HOST" ] && error "必须提供回调蓝鲸的内部域名"

if [[ -d /data/bkce/logs/weopsrdp ]]; then
    log "weopsrdp"
else
    install -d /data/bkce/logs/weopsrdp
fi

if [[ $(docker ps -a|grep guacd) ]]; then
    warning "guacd容器已存在, 删除"
    docker rm -f guacd
fi

log "启动guacd容器"
docker run -d --name guacd --network=host --restart=always $GUACD_IMAGE

if [[ $(docker ps -a|grep weopsrdp) ]]; then
    warning "weopsrdp容器已存在, 删除"
    docker rm -f weopsrdp
fi
log "启动weopsrdp容器"
docker run -d --name weopsrdp --network=host --restart=always \
    -e BK_PAAS_INNER_HOST=$SITE_URL \
    -e BKAPP_SITE_URL=$INNER_HOST \
    $WEOPSRDP_IMAGE