#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0
source ../weops_version
#IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/consul:latest"

VERSION="1.0.0"

BIND_IP="127.0.0.1"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -i, --init               [可选] "部署种子节点" ]
            [ -k, --key                [必填] "consul key" ]
            [ -j, --join               [可选] "加入集群的种子节点" ]
            [ -b, --bind-ip            [必填] "consul 集群的通信ip"]
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
        --key | -k)
            shift
            CONSUL_KEY=$1
            ;;
        --join | -j)
            shift
            JOIN_IP=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
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

if [ -z "$BIND_IP" ]; then
    error "必须指定consul集群的通信ip"
fi

if [ -z "$CONSUL_KEY" ]; then
    error "必须指定consul key"
fi

if [ -z "$INIT" ] && [ -z "$JOIN_IP" ]; then
    error "必须指定是部署种子节点还是加入集群的种子节点"
fi

if [[ $(docker ps -a | grep weops-consul) ]]; then
    warning "已存在weops-consul容器,将删除"
    docker rm -f weops-consul
fi

if [ "$INIT" = "true" ]; then
    log "部署种子节点"
    docker run -d --restart=always -v /data/weops/proxy/:/consul/data \
        -e 'CONSUL_LOCAL_CONFIG={"connect": {"enabled": true}}' \
        -e CONSUL_HTTP_ADDR=http://127.0.0.1:8501 \
        --net=host \
        --name=weops-consul $CONSUL_IMAGE \
        agent -server \
        -client=127.0.0.1 \
        -bootstrap-expect=1 \
        -server-port=8603 \
        -serf-wan-port=8602 \
        -serf-lan-port=8601 \
        -http-port=8501 \
        -bind ${BIND_IP} \
        -encrypt="${CONSUL_KEY}"
    sleep 5
    log "添加默认区域采集节点"
    curl -o /dev/null -s -X PUT http://127.0.0.1:8501/v1/kv/weops/access_points/default -d "
{
    \"ip\":\"automate.service.consul\",
    \"name\":\"默认区域采集节点\",
    \"zone\":\"default\",
    \"port\": 8089,
    \"logip\": \"datainsight.service.consul\",
    \"logport\": 9000
}
"
    access_point=$(curl -sSL http://127.0.0.1:8501/v1/kv/weops/access_points/default | jq -r '.[].Value'|base64 -d)
    log "默认区域采集节点信息: $access_point"
else
    log "加入集群的种子节点"
    docker run -d --restart=always -v /data/weops/proxy/:/consul/data \
        -e 'CONSUL_LOCAL_CONFIG={"connect": {"enabled": true}}' \
        -e CONSUL_HTTP_ADDR=http://127.0.0.1:8501 \
        --net=host \
        --name=weops-consul $CONSUL_IMAGE \
        agent -server \
        -client=127.0.0.1 \
        -retry-join=${JOIN_IP} \
        -server-port=8603 \
        -serf-wan-port=8602 \
        -serf-lan-port=8601 \
        -http-port=8501 \
        -bind ${BIND_IP} \
        -encrypt="${CONSUL_KEY}"
fi