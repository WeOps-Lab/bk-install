#!/usr/bin/env bash
# 用途：在已经运行的单实例的 rabbitmq-server 上，配置为rabbitmq 集群
# 参考文档：
#       1. https://www.rabbitmq.com/clustering.html
#       2. https://www.rabbitmq.com/cluster-formation.html#peer-discovery-consul

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
ERLANG_COOKIE=
ERLANG_COOKIE_SERVER_PATH=/var/lib/rabbitmq/.erlang.cookie
ERLANG_COOKIE_CLIENT_PATH=$HOME/.erlang.cookie 
CLUSTER_FORMATION_CONSUL_SVC=rabbitmq
source /data/install/weops_version
usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -e, --erlang-cookie   [必填] "指定内部erlang通信的cookie，长度为<255的base64字符集的字符串" ]
            [ -n, --service-name    [可选] "指定注册到consul的服务名，默认为rabbitmq" ]
            [ -v, --version         [可选] "查看脚本版本号" ]
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

fail () {
    echo "$@" 1>&2
    exit 1
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
        -e | --erlang-cookie )
            shift
            ERLANG_COOKIE=$1
            ;;
        -n | --service-name )
            shift
            CLUSTER_FORMATION_CONSUL_SVC=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --version | -v | -V )
            version 
            exit 0
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
check_port_alive () {
    local port=$1

    lsof -i:$port -sTCP:LISTEN 1>/dev/null 2>&1

    return $?
}
wait_port_alive () {
    local port=$1
    local timeout=${2:-10}

    for i in $(seq $timeout); do
        check_port_alive $port && return 0
        sleep 1
    done
    return 1
}
# 参数合法性有效性校验
if [[ ${#ERLANG_COOKIE} -eq 0 || ${#ERLANG_COOKIE} -gt 255 ]]; then
    warning "(-e, --erlang-cookie) 指定的字符串长度等于0或者大于255"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# make sure previous rabbitmq-server stopped
docker stop rabbitmq

log "生成 $ERLANG_COOKIE_SERVER_PATH $ERLANG_COOKIE_CLIENT_PATH 并设置权限为400"
echo -n "$ERLANG_COOKIE" > "$ERLANG_COOKIE_SERVER_PATH"
chown 999:999 "$ERLANG_COOKIE_SERVER_PATH"
chmod 400 "$ERLANG_COOKIE_SERVER_PATH"
echo -n "$ERLANG_COOKIE" > "$ERLANG_COOKIE_CLIENT_PATH"

log "enbale consul backend service discovery plugin"
docker run --rm \
    --name=rabbitmq-conf \
    --net=host \
    --ulimit nofile=102400:102400 \
    -v /etc/rabbitmq:/etc/rabbitmq \
    -v /data/bkce/public/rabbitmq:/data/bkce/public/rabbitmq \
    -v /data/bkce/logs/rabbitmq:/data/bkce/logs/rabbitmq \
    -v /var/lib/rabbitmq/:/var/lib/rabbitmq/ \
    $RABBITMQ_MANAGE_IMAGE rabbitmq-plugins enable --offline rabbitmq_peer_discovery_consul

log "modify rabbitmq config to using consul backend peer discovery"
[[ -r /etc/rabbitmq/rabbitmq.conf ]] && sed -i '/cluster_formation/d' /etc/rabbitmq/rabbitmq.conf
cat <<EOF > /etc/rabbitmq/rabbitmq.conf

cluster_formation.peer_discovery_backend = rabbit_peer_discovery_consul

cluster_formation.consul.host = localhost
# 8500 is used by default
cluster_formation.consul.port = 8500
# http is used by default
cluster_formation.consul.scheme = http
cluster_formation.consul.svc = $CLUSTER_FORMATION_CONSUL_SVC
# health check interval (node TTL) in seconds
cluster_formation.consul.svc_ttl = 40
# how soon should nodes that fail their health checks be unregistered by Consul?
# this value is in seconds and must not be lower than 60 (a Consul requirement)
cluster_formation.consul.deregister_after = 90
# do compute service address
cluster_formation.consul.svc_addr_auto = true
# compute service address using node name
cluster_formation.consul.svc_addr_use_nodename = true
EOF

if grep -q \\. /etc/rabbitmq/rabbitmq-env.conf 2>/dev/null; then
    echo 'cluster_formation.consul.use_longname = true' >> /etc/rabbitmq/rabbitmq.conf
fi

# start rabbitmq and reset all data (become blank one)
docker start rabbitmq
log "wait for rabbitmq port 5672 alive"
wait_port_alive 5672 10

log "stop rabbitmq and reset all data"
docker exec rabbitmq rabbitmqctl stop_app && \
docker exec rabbitmq rabbitmqctl force_reset && \
docker exec rabbitmq rabbitmqctl start_app