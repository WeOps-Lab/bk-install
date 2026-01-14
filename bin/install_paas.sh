#!/usr/bin/env bash
# 蓝鲸PaaS平台容器化安装脚本（最终修正版）
source /data/install/weops_version

set -euo pipefail

PROGRAM=$(basename "$0")
VERSION=5.3

declare -A PORTS=(
    ["paas"]=8001
    ["appengine"]=8000
    ["esb"]=8002
    ["login"]=8003
    ["console"]=8004
    ["apigw"]=8005
)
declare -a MODULES=(${!PORTS[@]})

SELF_DIR=$(dirname "$(readlink -f "$0")")

# --- 变量定义 ---
PREFIX="/data/bkce"
MODULE_SRC_DIR="/data/src"
ENV_FILE=""
BIND_ADDR="0.0.0.0"
LOG_DIR="${PREFIX}/logs/open_paas"
ETC_DIR="${PREFIX}/etc"
PUBLIC_DIR="${PREFIX}/public/open_paas"
OPENPAAS_DIR="${PREFIX}/open_paas"
SELECTED_MODULE=""
RUN_USER_UID=10000
DOCKER_NETWORK_MODE="host"
# ----------------

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [可选] "安装的子模块(${MODULES[*]}), 默认全部安装" ]
            [ -s, --srcdir      [必填] "源代码目录，如 /data/src/open_paas" ]
            [ -p, --prefix      [必填] "安装目标路径，如 /data/bkce" ]
            [ -e, --env-file    [必填] "环境变量文件，内容格式为 KEY=VALUE" ]
            [ -b, --bind        [可选] "监听地址，默认0.0.0.0" ]
            [ -v, --version     [可选] 查看脚本版本号 ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

version () {
    echo "$PROGRAM version $VERSION"
}

# 参数解析
while (( $# > 0 )); do 
    case "$1" in
        -m | --module ) shift; SELECTED_MODULE=$1 ;;
        -s | --srcdir ) shift; MODULE_SRC_DIR=$1 ;;
        -p | --prefix ) shift; PREFIX=$1 ;;
        -e | --env-file ) shift; ENV_FILE=$1 ;;
        -b | --bind ) shift; BIND_ADDR=$1 ;;
        --help | -h | '-?' ) usage_and_exit 0 ;;
        --version | -v | -V ) version; exit 0 ;;
        -* ) echo "不可识别的参数: $1" 1>&2; usage_and_exit 1 ;;
        *) break ;;
    esac
    shift 
done 

# 重新根据 PREFIX 计算依赖路径
LOG_DIR="${PREFIX}/logs/open_paas"
ETC_DIR="${PREFIX}/etc"
PUBLIC_DIR="${PREFIX}/public/open_paas"
OPENPAAS_DIR="${PREFIX}/open_paas"

if [[ -z "$MODULE_SRC_DIR" ]]; then
    echo "必须指定源代码目录 -s <srcdir>" 1>&2
    usage_and_exit 1
fi
if [[ -z "$PREFIX" ]]; then
    echo "必须指定安装目标路径 -p <prefix>" 1>&2
    usage_and_exit 1
fi
if [[ -z "$ENV_FILE" ]]; then
    echo "必须指定环境变量文件 -e <env-file>" 1>&2
    usage_and_exit 1
fi

if [[ -n "$SELECTED_MODULE" ]]; then
    MODULES=("$SELECTED_MODULE")
fi



# 创建必要目录
# 优化：仅当未指定模块（全量安装）或指定模块为 'paas'（通常是批量安装的第一个）时才进行全量备份
# 避免在 bkcli 连续调用时产生多次备份
if [[ -z "$SELECTED_MODULE" || "$SELECTED_MODULE" == "paas" ]]; then
    if [[ -d "$OPENPAAS_DIR" ]]; then
        BACKUP_PATH="${OPENPAAS_DIR}_$(date +%Y%m%d%H%M%S)"
        echo "检测到 $OPENPAAS_DIR 存在，正在全量备份到 $BACKUP_PATH ..."
        cp -rp "$OPENPAAS_DIR" "$BACKUP_PATH"
    fi
fi

install -o 10000 -g 10000 -d -m 755 "$LOG_DIR"
install -o 10000 -g 10000 -d -m 755 "$OPENPAAS_DIR"
install -o 10000 -g 10000 -d -m 755 "$PUBLIC_DIR"
install -d -m 755 "$ETC_DIR"

# 1. 拷贝代码 (防止 rsync --delete 删除渲染后的配置文件，必须先拷贝)
for m in "${MODULES[@]}"; do
    SRC_MOD_PATH="$MODULE_SRC_DIR/open_paas/$m"
    DEST_MOD_PATH="$OPENPAAS_DIR/$m"
    # 校验源代码目录
    if ! [[ -d "$SRC_MOD_PATH" ]]; then
        echo "源模块代码目录不存在: $SRC_MOD_PATH" 1>&2
        continue
    fi

    # 拷贝代码到目标目录
    echo "拷贝 $SRC_MOD_PATH 到 $DEST_MOD_PATH ..."
    rsync -a --delete --exclude=media "$SRC_MOD_PATH/" "$DEST_MOD_PATH/"
done

# 统一修改权限 (确保容器用户有权访问)
echo "修改 $OPENPAAS_DIR 权限为 $RUN_USER_UID:$RUN_USER_UID ..."
chown -R "$RUN_USER_UID:$RUN_USER_UID" "$OPENPAAS_DIR"

# 渲染配置到 $ETC_DIR (在代码拷贝之后执行)
echo "渲染配置到 $ETC_DIR ..."
"$SELF_DIR"/render_tpl -p "$PREFIX" -m open_paas \
    -E LAN_IP="$BIND_ADDR" -e "$ENV_FILE" \
    $MODULE_SRC_DIR/open_paas/support-files/templates/*

# 生成适配 Docker 的环境变量文件 (去除 export)
DOCKER_ENV_FILE="${ETC_DIR}/.env.docker"
sed 's/^export //g' "$ENV_FILE" > "$DOCKER_ENV_FILE"

# 3. 启动容器和迁移
for m in "${MODULES[@]}"; do
    DEST_MOD_PATH="$OPENPAAS_DIR/$m"
    ini="${ETC_DIR}/uwsgi-open_paas-${m}.ini"
    
    if ! [[ -d "$DEST_MOD_PATH" ]]; then
        continue
    fi

    # 数据库迁移
    if [[ -f "$DEST_MOD_PATH/on_migrate" ]]; then
        echo "正在执行数据库迁移 ($m) ..."
        MIGRATE_CMD=$(awk '/workon/ { enter=1 } !/workon/ && enter == 1 ' "$DEST_MOD_PATH/on_migrate")
        if [[ -n "$MIGRATE_CMD" ]]; then
            docker run --rm \
                -v "${OPENPAAS_DIR}:${OPENPAAS_DIR}" \
                -v "${ETC_DIR}:${ETC_DIR}" \
                -v "${LOG_DIR}:${LOG_DIR}" \
                -v "${PREFIX}/cert:${PREFIX}/cert" \
                --env-file "$DOCKER_ENV_FILE" \
                -e PAAS_LOGGING_DIR="${LOG_DIR}" \
                -e BK_ENV=production \
                --net="${DOCKER_NETWORK_MODE}" \
                -u "${RUN_USER_UID}" \
                -w "${OPENPAAS_DIR}/$m" \
                "${PAAS_IMAGE}" \
                bash -c "function fail() { echo \"\$@\" >&2; exit 1; }; $MIGRATE_CMD"
        fi
    fi

    # 删除已有容器
    cname="bk-paas-$m"
    if docker ps -a --format '{{.Names}}' | grep -q "^${cname}$"; then
        echo "已有容器 ${cname}，正在删除..."
        docker rm -f "${cname}"
    fi
    # 挂载代码、配置、日志、环境变量文件
    echo "启动容器 ${cname}..."
    docker run -itd \
        -v "${OPENPAAS_DIR}:${OPENPAAS_DIR}" \
        -v "${ETC_DIR}:${ETC_DIR}" \
        -v "${LOG_DIR}:${LOG_DIR}" \
        -v "${PREFIX}/cert:${PREFIX}/cert" \
        --env-file "$DOCKER_ENV_FILE" \
        -e PAAS_LOGGING_DIR="${LOG_DIR}" \
        -e BK_ENV=production \
        --name="${cname}" \
        --net="${DOCKER_NETWORK_MODE}" \
        -u "${RUN_USER_UID}" \
        "${PAAS_IMAGE}" \
        uwsgi --ini "${ini}"
done

echo "所有指定模块容器已启动完成。"

# 检查容器状态
echo "正在检测容器运行状态："
for m in "${MODULES[@]}"; do
    cname="bk-paas-$m"
    status=$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null || echo "not found")
    if [[ "$status" == "running" ]]; then
        echo "容器 $cname 状态正常 (running)"
    else
        echo "容器 $cname 状态异常 ($status)"
    fi
done

