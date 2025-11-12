#!/usr/bin/env bash
# 安装，配置 mongodb cluster 
# 参考文档： 
#           1. https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/
#           2. https://docs.mongodb.com/manual/tutorial/deploy-replica-set/

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0
source /data/install/weops_version
# 全局默认变量
MONGODB_VERSION="4.2.3"
BIND_ADDR="127.0.0.1"
CLIENT_PORT=27017
DATA_DIR="/var/lib/mongodb"
LOG_DIR="/var/log/mongodb"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --port            [选填] "部署的mongodb listen port, 默认27017" ]
            [ -b, --bind            [选填] "mongodb的监听地址默认为127.0.0.1" ]
            [ -d, --data-dir        [选填] "mongodb的数据目录，默认为/var/lib/mongodb" ]
            [ -l, --log-dir         [选填] "mongodb的日志目录，默认为/var/log/mongodb" ]
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

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}

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

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -p | --port )
            shift
            CLIENT_PORT=$1
            ;;
        -d | --data-dir )
            shift
            DATA_DIR=$1
            ;;
        -l | --log-dir )
            shift
            LOG_DIR=$1
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

if ! [[ "$BIND_ADDR" =~ ^[0-9] ]]; then
    warning "$BIND_ADDR is not a valid address"
fi

# 参数合法性有效性校验
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装 mongodb
# if ! rpm -ql mongodb-org-"$MONGODB_VERSION" &>/dev/null; then
#     yum install -y mongodb-org-"$MONGODB_VERSION" mongodb-org-server-"$MONGODB_VERSION" \
#         mongodb-org-shell-"$MONGODB_VERSION" mongodb-org-mongos-"$MONGODB_VERSION" \
#         mongodb-org-tools-"$MONGODB_VERSION" || error "安装mongodb-$MONGODB_VERSION 失败"
# fi

# 判断并创建目录
if ! [[ -d $DATA_DIR ]]; then
    mkdir -p "$DATA_DIR"
fi
if ! [[ -d $LOG_DIR ]]; then
    mkdir -p "$LOG_DIR"
fi
chown 999:999 "$DATA_DIR" "$LOG_DIR" "/var/run/mongodb"

# 修改mongodb配置
log "生成mongodb主配置文件 /etc/mongod.conf"
cat <<EOF > /etc/mongod.conf
# mongod.conf
# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/
# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  logRotate: reopen
  path: /data/bkce/logs/mongodb/mongod.log
# Where and how to store data.
storage:
  dbPath: /data/bkce/public/mongodb
  journal:
    enabled: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 4
#  wiredTiger:
# how the process runs
processManagement:
  fork: false  # fork and run in background
  pidFilePath: /var/run/mongodb/mongod.pid  # location of pidfile
  timeZoneInfo: /usr/share/zoneinfo
# network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1, ${BIND_ADDR}
#security:
#operationProfiling:
#replication:
#sharding:
## Enterprise-Only Options
#auditLog:
#snmp:
replication:
  replSetName: rs0
security:
  keyFile: /etc/mongod.key
EOF

log "生成mongodb key文件 /etc/mongod.key"
touch /etc/mongod.key

# 配置系统的logrotate
cat <<EOF > /etc/logrotate.d/mongodb
$LOG_DIR/*.log {
    daily
    rotate 14
    size 100M
    compress
    dateext
    missingok
    notifempty
    sharedscripts
    postrotate
        /bin/kill -SIGUSR1 \`cat /var/run/mongodb/mongod.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

if docker ps -a | awk '{print $NF}' | grep -wq "mongo"; then
  log "检测到已存在的mongo,删除"
  docker rm -f mongo
fi

# 启动mongodb
docker run -d \
    --name mongo \
    --net=host \
    -v /etc/mongod.conf:/etc/mongod.conf \
    -v /etc/mongod.key:/etc/mongod.key \
    -v $DATA_DIR:$DATA_DIR \
    -v $LOG_DIR:$LOG_DIR \
    -v /tmp:/tmp \
    -v /var/run/mongodb:/var/run/mongodb \
    $MONGODB_IMAGE -f /etc/mongod.conf

# 等待27017端口启动
log "等待mongodb启动"
wait_port_alive CLIENT_PORT 10
log "mongodb启动成功"

# log "启动mongod，并设置开机启动mongod"
# systemctl enable --now mongod
# systemctl status mongod
