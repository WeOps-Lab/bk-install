#!/usr/bin/env bash
# 通用脚本框架变量
set -euo pipefail
PROGRAM=$(basename "$0")
EXITCODE=0
source ../weops_version
#IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/monstache:latest"

VERSION="1.0.0"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -p --mongodb-password     [必填] "mongodb的密码" ]
            [ -e --elasticsearch-paasword [必填] "elasticsearch的密码" ]
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
        --mongodb-password | -p)
            shift
            MONGODB_PASSWORD=$1
            ;;
        --elasticsearch-password | -e)
            shift
            ELASTICSEARCH_PASSWORD=$1
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
[[ -z $MONGODB_PASSWORD ]] && error "缺少必填参数: --mongodb-password"
[[ -z $ELASTICSEARCH_PASSWORD ]] && error "缺少必填参数: --elasticsearch-password"


if [[ $(docker ps -a|grep monstache) ]]; then
    warning "已存在monstache容器,将删除"
    docker rm -f monstache
fi

docker run --net=host -itd \
    --name=monstache \
    -e BK_CMDB_MONGODB_PASSWORD=$MONGODB_PASSWORD \
    -e BK_CMDB_ES7_PASSWORD=$ELASTICSEARCH_PASSWORD \
    ${MONSTACHE_IMAGE}