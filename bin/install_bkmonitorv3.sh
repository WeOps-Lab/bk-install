#!/usr/bin/env bash
# 用途： 安装蓝鲸的监控后台V3
 
# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0
source /data/install/weops_version
# 全局默认变量
# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

# PYTHON目录
PYTHON_PATH=/opt/py36_e/bin/python3.6

# 默认安装所有子模块
MODULE="bkmonitorv3"
PROJECTS=(influxdb-proxy transfer grafana monitor unify-query ingester)
RPM_DEP=(gcc libmysqlclient-dev libevent-dev libxext6 libxrender1 fontconfig)
ENV_FILE=/data/install/bin/04-final/bkmonitorv3.env
BIND_ADDR=127.0.0.1

# IMAGE=docker-bkrepo.cwoa.net/ce1b09/weops-docker/bkmonitorv3:v3.6.3656
# error exit handler
err_trap_handler () {
    MYSELF="$0"
    LASTLINE="$1"
    LASTERR="$2"
    echo "${MYSELF}: line ${LASTLINE} with exit code ${LASTERR}" >&2
}
trap 'err_trap_handler ${LINENO} $?' ERR

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -b, --bind        [可选] "监听的网卡地址，默认为127.0.0.1" ]
            [ -m, --module      [必选] "安装的子模块(${PROJECTS[*]})" ]
            [ --python-path     [可选] "指定创建virtualenv时的python二进制路径，默认为/opt/py27/bin/python" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]

            [ -s, --srcdir      [必填] "从该目录拷贝$MODULE/project目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --cert-path       [可选] "企业版证书存放目录，默认为\$PREFIX/cert" ]
            [ --log-dir         [可选] "日志目录,默认为\$PREFIX/logs/$MODULE" ]

            [ -v, --version     [可选] 查看脚本版本号 ]
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
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -m | --module )
            shift
            BKMONITOR_MODULE=$1
            ;;
        --python-path )
            shift
            PYTHON_PATH=$1
            ;;
        -e | --env-file)
            shift
            ENV_FILE="$1"
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        --cert-path)
            shift
            CERT_PATH=$1
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/$MODULE}
CERT_PATH=${CERT_PATH:-$PREFIX/cert}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/$MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE 不存在"
fi
if [[ $BKMONITOR_MODULE = *monitor* ]]; then
    if ! [[ $("$PYTHON_PATH" --version 2>&1) = *Python* ]]; then
        warning "$PYTHON_PATH 不是一个合法的python二进制"
    fi
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if [[ -z "$BKMONITOR_MODULE" ]]; then
    warning "-m can't be empty"
elif ! [[ -d $MODULE_SRC_DIR/$MODULE/$BKMONITOR_MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE/$BKMONITOR_MODULE 不存在"
fi
if [[ -n "$ENV_FILE" && ! -r "$ENV_FILE" ]]; then
    warning "指定的$ENV_FILE不存在"
fi
# if (( EXITCODE > 0 )); then
#     usage_and_exit "$EXITCODE"
# fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; } 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d "$PREFIX/public/$MODULE"
install -o blueking -g blueking -m 755 -d /var/run/bkmonitorv3

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/bkmonitorv3.conf <<EOF
D /var/run/bkmonitorv3 0755 blueking blueking
EOF
# 拷贝模块目录到$PREFIX
rsync -a --delete "${MODULE_SRC_DIR}/$MODULE/" "$PREFIX/$MODULE/"

# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -E LAN_IP="$BIND_ADDR" -e "$ENV_FILE" \
    "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*

case $BKMONITOR_MODULE in 
    monitor) 
        # 安装rpm依赖包，如果不存在
        if ! dpkg -l "${RPM_DEP[@]}" >/dev/null; then
            apt -y install "${RPM_DEP[@]}"
        fi
        # 拷贝证书目录到$PREFIX, monitor依赖证书
        rsync -a "$CERT_PATH/" "$PREFIX/cert/"
        # 加载influxdb存储相关的配置
        source "${SELF_DIR}"/../load_env.sh 
        # 转换一下环境变量兼容监控后台的逻辑 //TODO
        set +u
        export INFLUXDB_BKMONITORV3_IP0=$BK_INFLUXDB_BKMONITORV3_IP0
        # 兼容单台influxdb场景
        if [[ -n $BK_INFLUXDB_BKMONITORV3_IP1 ]]; then
            export INFLUXDB_BKMONITORV3_IP1=$BK_INFLUXDB_BKMONITORV3_IP1
        fi
        export INFLUXDB_BKMONITORV3_IP=$BK_INFLUXDB_BKMONITORV3_IP
        export INFLUXDB_BKMONITORV3_PORT=$BK_MONITOR_INFLUXDB_PORT
        export INFLUXDB_BKMONITORV3_USER=$BK_MONITOR_INFLUXDB_USER
        export INFLUXDB_BKMONITORV3_PASS=$BK_MONITOR_INFLUXDB_PASSWORD
        export BKMONITORV3_INFLUXDB_PROXY_HOST=$BK_INFLUXDB_PROXY_HOST
        export BKMONITORV3_INFLUXDB_PROXY_PORT=$BK_INFLUXDB_PROXY_PORT
        export ES7_HOST=$BK_MONITOR_ES7_HOST
        export ES7_REST_PORT=$BK_MONITOR_ES7_REST_PORT
        export ES7_USER=$BK_MONITOR_ES7_USER
        export ES7_PASSWORD=$BK_MONITOR_ES7_PASSWORD
        export KAFKA_HOST=$BK_MONITOR_KAFKA_HOST
        export KAFKA_PORT=$BK_MONITOR_KAFKA_PORT
        set -u

        if [[ -z "$INFLUXDB_BKMONITORV3_IP0" ]]; then
            echo "influxdb (bkmonitorv3) or \$INFLUXDB_BKMONITORV3_IP0 is not configured."
            exit 1
        fi
        source "${SELF_DIR}"/../functions
        wait_ns_alive  influxdb-proxy.bkmonitorv3.service.consul || fail "influxdb-proxy.bkmonitorv3.service.consul 无法解析"
        if [ "$(docker ps -aq -f name=bkmonitorv3-monitor)" ]; then
            echo "Container bkmonitorv3-monitor is running. Stopping and removing it now."
            docker stop bkmonitorv3-monitor
            docker rm -f bkmonitorv3-monitor 
            rm -vf /var/run/bkmonitorv3/celerybeat.pid /var/run/bkmonitorv3/monitor-supervisord.pid /var/run/bkmonitorv3/monitor-supervisord.sock
        fi
        # 生成docker用的supervisor配置文件
        sed "s@/data/bkce/.envs/bkmonitorv3-monitor@/cache/.bk/env@" /data/bkce/etc/supervisor-bkmonitorv3-monitor.conf > /data/bkce/etc/supervisor-bkmonitorv3-monitor.docker.conf
        sed -i 's@/cache/.bk/env/bin/python@/cache/.bk/env/bin/python3.6_e@g' /data/bkce/etc/supervisor-bkmonitorv3-monitor.docker.conf
        # 生成docker用的on_migrate文件
        sed "2,9s/^/#/" /data/bkce/bkmonitorv3/monitor/on_migrate > /data/bkce/bkmonitorv3/monitor/on_migrate.docker
        chmod 0755 /data/bkce/bkmonitorv3/monitor/on_migrate.docker
        # 启动容器
        docker run -itd \
        -v /data/bkce/bkmonitorv3/monitor:/data/bkce/bkmonitorv3/monitor \
        -v /data/bkce/logs/bkmonitorv3:/data/bkce/logs/bkmonitorv3 \
        -v /data/bkce/etc/supervisor-bkmonitorv3-monitor.docker.conf:/data/bkce/etc/supervisor-bkmonitorv3-monitor.conf:ro \
        -v /data/bkce/bkmonitorv3/support-files/pkgs:/pkgs \
        -v /data/bkce/bkmonitorv3/cert/saas_priv.txt:/data/bkce/bkmonitorv3/cert/saas_priv.txt:ro \
        -e BK_FILE_PATH=/data/bkce/bkmonitorv3/cert/saas_priv.txt \
        -e PYTHON_BIN=/cache/.bk/env/bin/python3.6_e \
        --net=host --name=bkmonitorv3-monitor -v /var/run/bkmonitorv3:/var/run/bkmonitorv3/ ${BKMONITORV3_IMAGE} bash -c "cd /data/bkce/bkmonitorv3/monitor && supervisord -n -c /data/bkce/etc/supervisor-bkmonitorv3-monitor.conf"
        # 初始化数据同步zk和写入influxdb信息（可重复执行）
        (
            set +u +e
            # 设置加密解释器用得变量
            docker exec bkmonitorv3-monitor bash -c "export INFLUXDB_BKMONITORV3_IP0=$INFLUXDB_BKMONITORV3_IP0;export INFLUXDB_BKMONITORV3_IP1=$INFLUXDB_BKMONITORV3_IP1;export INFLUXDB_BKMONITORV3_PORT=$INFLUXDB_BKMONITORV3_PORT;export INFLUXDB_BKMONITORV3_USER=$INFLUXDB_BKMONITORV3_USER;export INFLUXDB_BKMONITORV3_PASS=$INFLUXDB_BKMONITORV3_PASS;export BKMONITORV3_INFLUXDB_PROXY_HOST=$BKMONITORV3_INFLUXDB_PROXY_HOST;export BKMONITORV3_INFLUXDB_PROXY_PORT=$BKMONITORV3_INFLUXDB_PROXY_PORT;export ES7_HOST=$ES7_HOST;export ES7_REST_PORT=$ES7_REST_PORT;export ES7_USER=$ES7_USER;export ES7_PASSWORD=$ES7_PASSWORD;export KAFKA_HOST=$KAFKA_HOST;export KAFKA_PORT=$KAFKA_PORT;bash -x on_migrate.docker 1>&2 2>/dev/null;"
        )
        ;;
    transfer) 
        # 生成service定义配置
        cat > /usr/lib/systemd/system/bk-transfer.service <<EOF
[Unit]
Description="Blueking Bkmonitor Transfer Server"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
EnvironmentFile=-/etc/sysconfig/bk-transfer
ExecStart=$PREFIX/$MODULE/transfer/transfer \
    run -c $PREFIX/$MODULE/transfer/transfer.yaml --pid /var/run/bkmonitorv3/transfer.pid --max-cpus 0.9 --max-files 0.6
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF
        ;;
    influxdb-proxy)
        # 生成service定义配置
        cat > /usr/lib/systemd/system/bk-influxdb-proxy.service <<EOF
[Unit]
Description="Blueking influxdb Proxy"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/$MODULE/influxdb-proxy/influxdb-proxy \
        --config $PREFIX/$MODULE/influxdb-proxy/etc/influxdb-proxy.yml 
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF
        ;;
    grafana)
        # 生成service定义配置
        cat > /usr/lib/systemd/system/bk-grafana.service <<EOF
[Unit]
Description="Blueking grafana"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
WorkingDirectory=$PREFIX/$MODULE/grafana
ExecStart=$PREFIX/$MODULE/grafana/bin/grafana-server \
        --homepath ./ --config ./conf/grafana.ini cfg:default.paths.logs=$PREFIX/logs/bkmonitorv3/ \
        cfg:default.paths.data=./data cfg:default.paths.plugins=./plugins
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF
        ;;
    unify-query)
        # 生成service定义配置
        cat > /usr/lib/systemd/system/bk-unify-query.service <<EOF
[Unit]
Description="Blueking bkmonitorv3 unify query"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/$MODULE/unify-query/unify-query \
        --config $PREFIX/$MODULE/unify-query/unify-query.yaml 
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF
        
        # generate logrotate
        cat > /etc/logrotate.d/bk-unify-query <<EOF
$LOG_DIR/unify-query.log {
    hourly
    missingok
    rotate 48
    compress
    copytruncate
    notifempty
    create 644 blueking blueking
    sharedscripts
    postrotate
        /usr/bin/pkill -HUP unify-query 2> /dev/null || true
    endscript
}
EOF
        ;;
    ingester)
        # 生成service定义配置
        cat > /usr/lib/systemd/system/bk-ingester.service <<EOF
[Unit]
Description="Blueking bkmonitorv3 ingester"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/$MODULE/ingester/ingester \
      run --config $PREFIX/$MODULE/ingester/ingester.yaml \
      --pid /var/run/$MODULE/ingester.pid
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF
        ;;

esac

chown -R blueking.blueking "$PREFIX/$MODULE" "$LOG_DIR"
if [ "${BKMONITOR_MODULE}" != "monitor" ]; then
    systemctl daemon-reload
    systemctl start "bk-${BKMONITOR_MODULE}"
    
    if ! systemctl is-enabled "bk-${BKMONITOR_MODULE}" &>/dev/null; then
        systemctl enable "bk-${BKMONITOR_MODULE}"
    fi
fi