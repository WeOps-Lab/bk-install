#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0

source /data/install/weops_version
# IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/casbinmesh:latest"

VERSION="1.0.0"


usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -b --bind-ip           [必填] "casbin-mesh的公共ip" ]
            [ -i --init              [可选] "是否init节点" ]
            [ -j --join              [可选] "加入的master节点" ]
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
        --bind-ip | -b)
            shift
            BIND_IP=$1
            ;;
        --init | -i)
            INIT=true
            ;;
        --join | -j)
            shift
            JOIN_IP=$1
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
[[ -z $BIND_IP ]] && error "缺少必填参数: -b --bind-ip"


if [[ $(docker ps -a|grep casbin_mesh) ]]; then
    warning "已存在casbin_mesh容器,将删除"
    docker rm -f casbin_mesh
fi

if [[ -d /data/weops/casbin-mesh ]]; then
    log "/data/weops/casbin-mesh 数据目录已存在,重建集群,清除此目录,重建成功后需手动初始化weops权限策略"
    rm -rf /data/weops/casbin-mesh/*
fi

if [[ $INIT ]]; then
    docker run -d --restart=always \
            -v /data/weops/casbin-mesh:/casmesh/data \
            --net=host \
            --name=casbin_mesh \
            ${CASBIN_IMAGE} -node-id ${BIND_IP} -raft-advertise-address ${BIND_IP}:4002 -raft-address 0.0.0.0:4002
else
    docker run -d --restart=always \
            -v /data/weops/casbin-mesh:/casmesh/data \
            --net=host \
            --name=casbin_mesh \
            ${CASBIN_IMAGE} -node-id ${BIND_IP} -raft-advertise-address ${BIND_IP}:4002 -raft-address 0.0.0.0:4002 -join http://${JOIN_IP}:4002
fi