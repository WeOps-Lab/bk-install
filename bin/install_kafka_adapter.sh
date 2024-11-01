#!/usr/bin/env bash
# 通用脚本框架变量
set -euo pipefail
PROGRAM=$(basename "$0")
EXITCODE=0

source ../weops_version
VERSION="1.0.0"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -u --username             [必填] "用户名" ]
            [ -p --password             [必填] "密码" ]
            [ -a --app-auth-token       [必填] "app-auth-token" ]
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
        --username | -u)
            shift
            USERNAME=$1
            ;;
        --password | -p)
            shift
            PASSWORD=$1
            ;;
        --app-auth-token | -a)
            shift
            APP_AUTH_TOKEN=$1
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
if [[ -z ${USERNAME} ]]; then
    error "用户名不能为空"
fi

if [[ -z ${PASSWORD} ]]; then
    error "密码不能为空"
fi

if [[ -z ${APP_AUTH_TOKEN} ]]; then
    error "app-auth-token不能为空"
fi


if [[ $(docker ps -a|grep kafka-adapter) ]]; then
    warning "已存在kafka-adapter容器,将删除"
    docker rm -f kafka-adapter
fi

docker run -d --restart=always --net=host \
-e KAFKA_BROKER_LIST=kafka.service.consul:9092 \
-e BASIC_AUTH_USERNAME=${USERNAME} \
-e BASIC_AUTH_PASSWORD=${PASSWORD} \
-e PORT=8080 \
-e BKAPP_PAAS_HOST=http://paas.service.consul \
-e BKAPP_WEOPS_APP_ID=weops_saas \
-e BKAPP_WEOPS_APP_SECRET=${APP_AUTH_TOKEN} \
-e LOG_SKIP_RECEIVE="True" \
--name=kafka-adapter \
$KAFKA_ADAPTER_IMAGE