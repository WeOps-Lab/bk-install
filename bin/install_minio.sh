#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0

source ../weops_version
# IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/minio:latest"

VERSION="1.0.0"

API_PORT=9015
CONSOLE_PORT=9016

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -a --access-key           [必填] "minio的access key" ]
            [ -s --access-secret        [必填] "minio的access token" ]
            [ -l --server-list          [必填] "集群服务器列表" ]
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
        --access-key | -a)
            shift
            ACCESS_KEY=$1
            ;;
        --access-secret | -s)
            shift
            ACCESS_SECRET=$1
            ;;
        --server-list | -l)
            shift
            SERVER_LIST=$1
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
[[ -z $ACCESS_KEY ]] && error "缺少必填参数: --access-key"
[[ -z $ACCESS_SECRET ]] && error "缺少必填参数: --access-secret"
[[ -z $SERVER_LIST ]] && error "缺少必填参数: --server-list"

if [[ -d /data/oss ]]; then
    log "/data/oss 数据目录已存在"
else
    install -d /data/oss
fi

if [[ $(docker ps -a|grep minio) ]]; then
    warning "已存在minio容器,将删除"
    docker rm -f minio
fi

docker run -d \
  --name minio \
  -v /data/oss:/data \
  -e "MINIO_ROOT_USER=${ACCESS_KEY}" \
  -e "MINIO_ROOT_PASSWORD=${ACCESS_SECRET}" \
  --network=host \
  --restart=always \
  $MINIO_IMAGE server $(printf "%s " "${SERVER_LIST[@]}") --address "0.0.0.0:${API_PORT}" --console-address ":${CONSOLE_PORT}"