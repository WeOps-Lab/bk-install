#!/usr/bin/env bash
# 通用脚本框架变量
set -euo pipefail
PROGRAM=$(basename "$0")
EXITCODE=0

source /data/install/weops_version
#IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/age:PG16-1.1.5"
PGDATA="/data/postgres"
VERSION="1.0.0"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -u --postgres-user        [必填] "postgres的用户名" ]
            [ -p --postgres-password    [必填] "postgres的密码" ]
            [ -d --postgres-db          [必填] "postgres的数据库" ]
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
        --postgres-user | -u)
            shift
            POSTGRES_USER=$1
            ;;
        --postgres-password | -p)
            shift
            POSTGRES_PASSWORD=$1
            ;;
        --postgres-db | -d)
            shift
            POSTGRES_DB=$1
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
[[ -z $POSTGRES_USER ]] && error "缺少参数: postgres-user"
[[ -z $POSTGRES_PASSWORD ]] && error "缺少参数: postgres-password"
[[ -z $POSTGRES_DB ]] && error "缺少参数: postgres-db"

if [[ -d /data/weops/age/data ]]; then
    warning "已存在age数据目录,跳过"
else
    mkdir -p /data/weops/age/data
fi

if [[ $(docker ps -a|grep age) ]]; then
    warning "已存在age容器,将删除"
    docker rm -f age
fi

cd /data/weops/age

docker run --net=host -itd \
    --name=age \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -e POSTGRES_DB=$POSTGRES_DB \
    -v ./data:/data/postgres \
    --restart=always \
    $AGE_IMAGE