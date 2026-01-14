#!/usr/bin/env bash
# 蓝鲸用户管理(usermgr)容器化安装脚本

set -euo pipefail

PROGRAM=$(basename "$0")
VERSION=1.0

SELF_DIR=$(dirname "$(readlink -f "$0")")
# 尝试加载版本文件，但允许被 -i 参数覆盖
if [[ -f /data/install/weops_version ]]; then
    source /data/install/weops_version
fi

# --- 变量定义 ---
PREFIX="/data/bkee"
MODULE_SRC_DIR="/data/src"
ENV_FILE=""
BIND_ADDR="127.0.0.1"
MODULE="usermgr"
LOG_DIR="${PREFIX}/logs/${MODULE}"
USERMGR_DIR="${PREFIX}/${MODULE}"
IMAGE="${USERMGR_IMAGE:-}" # 默认从 weops_version 获取
DOCKER_NETWORK_MODE="host"
# ----------------

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -s, --srcdir      [必填] "源代码目录" ]
            [ -p, --prefix      [必填] "安装目标路径" ]
            [ -i, --image       [可选] "Docker镜像" ]
            [ -e, --env-file    [可选] "环境变量文件" ]
            [ --python-path     [可选] "兼容参数，忽略" ]
            [ -v, --version     [可选] 查看脚本版本号 ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

# 参数解析
while (( $# > 0 )); do 
    case "$1" in
        -s | --srcdir ) shift; MODULE_SRC_DIR=$1 ;;
        -p | --prefix ) shift; PREFIX=$1 ;;
        -i | --image ) shift; IMAGE=$1 ;;
        -e | --env-file ) shift; ENV_FILE=$1 ;;
        --python-path ) shift ;; # 忽略
        --help | -h | '-?' ) usage_and_exit 0 ;;
        --version | -v | -V ) echo "$VERSION"; exit 0 ;;
        -* ) echo "不可识别的参数: $1" 1>&2; usage_and_exit 1 ;;
        *) break ;;
    esac
    shift 
done 

LOG_DIR="${PREFIX}/logs/${MODULE}"
USERMGR_DIR="${PREFIX}/${MODULE}"

if [[ -z "$MODULE_SRC_DIR" ]]; then echo "必须指定源代码目录 -s" 1>&2; usage_and_exit 1; fi
if [[ -z "$PREFIX" ]]; then echo "必须指定安装目标路径 -p" 1>&2; usage_and_exit 1; fi
if [[ -z "$IMAGE" ]]; then echo "必须指定镜像 -i 或在 weops_version 中定义" 1>&2; usage_and_exit 1; fi

# 1. 清理旧的部署 (Systemd)
if systemctl is-active --quiet bk-usermgr; then
    echo "Stopping bk-usermgr systemd service..."
    systemctl stop bk-usermgr
fi
if systemctl is-enabled --quiet bk-usermgr; then
    echo "Disabling bk-usermgr systemd service..."
    systemctl disable bk-usermgr
fi
if [[ -f /usr/lib/systemd/system/bk-usermgr.service ]]; then
    echo "Removing bk-usermgr.service..."
    rm -f /usr/lib/systemd/system/bk-usermgr.service
    systemctl daemon-reload
fi
# 清理 supervisord 配置 (防止冲突)
if [[ -f ${PREFIX}/etc/supervisor-usermgr-api.conf ]]; then
    # 注意：我们稍后会重新渲染它，但如果它被 supervisord 管理，我们需要先停止它
    # 如果 supervisord 正在运行且管理着 usermgr，我们需要 update
    if pgrep -x supervisord >/dev/null; then
       # 尝试停止该进程组
       /opt/py36/bin/supervisorctl stop usermgr-api:* || true
       # 移除配置? 不，我们稍后会覆盖它。
       # 但是如果 supervisord 还在运行，它可能会尝试重启。
       # 最好是从 supervisord 中移除。
       rm -f ${PREFIX}/etc/supervisor-usermgr-api.conf
       /opt/py36/bin/supervisorctl update || true
    fi
fi

# 创建目录
install -o 10000 -g 10000 -d "${LOG_DIR}"
install -o 10000 -g 10000 -m 755 -d "${USERMGR_DIR}"
install -o 10000 -g 10000 -m 755 -d "${PREFIX}/public/usermgr"
install -o 10000 -g 10000 -m 755 -d /var/run/usermgr

# 拷贝代码
rsync -a --delete "${MODULE_SRC_DIR}/usermgr/" "${USERMGR_DIR}/"
chown -R 10000:10000 "${USERMGR_DIR}"
chown -R 10000:10000 "${LOG_DIR}"

# 渲染配置
# 如果 ENV_FILE 为空，render_tpl 会尝试使用默认配置
RENDER_ARGS=(-u -m "usermgr" -p "$PREFIX")
if [[ -n "$ENV_FILE" ]]; then
    RENDER_ARGS+=(-e "$ENV_FILE")
fi

"$SELF_DIR"/render_tpl "${RENDER_ARGS[@]}" \
        "$MODULE_SRC_DIR"/usermgr/support-files/templates/*api*

# 修正 supervisor 配置中的路径，适配容器环境
# 将宿主机的虚拟环境路径替换为容器内的路径
sed -i 's|/data/bkce/.envs/usermgr-api/bin/|/cache/.bk/env/bin/|g' "${PREFIX}/etc/supervisor-usermgr-api.conf"

# 数据库迁移
echo "正在执行数据库迁移..."
docker run --rm \
    --user 10000 \
    -v "${USERMGR_DIR}:${USERMGR_DIR}" \
    -v "${PREFIX}/etc:${PREFIX}/etc" \
    -v "${LOG_DIR}:${LOG_DIR}" \
    --net="${DOCKER_NETWORK_MODE}" \
    -e BK_ENV=production \
    -e DJANGO_SETTINGS_MODULE="bkuser_core.config.overlays.prod" \
    "${IMAGE}" \
    bash -c "cd ${USERMGR_DIR}/api && python manage.py migrate"

# 启动容器
cname="usermgr"
if docker ps -a --format '{{.Names}}' | grep -q "^${cname}$"; then
    docker rm -f "${cname}"
fi

echo "启动容器 ${cname}..."
# 注意：这里假设 supervisor 配置文件路径为 $PREFIX/etc/supervisor-usermgr-api.conf
# 并且容器内可以直接使用 supervisord
docker run -itd \
    --user 10000 \
    -v "${USERMGR_DIR}:${USERMGR_DIR}" \
    -v "${PREFIX}/etc:${PREFIX}/etc" \
    -v "${LOG_DIR}:${LOG_DIR}" \
    -v /var/run/usermgr:/var/run/usermgr \
    --net="${DOCKER_NETWORK_MODE}" \
    --name="${cname}" \
    --restart always \
    -e BK_ENV=production \
    -e DJANGO_SETTINGS_MODULE="bkuser_core.config.overlays.prod" \
    "${IMAGE}" \
    supervisord -n -c "${PREFIX}/etc/supervisor-usermgr-api.conf"

# 检查状态
sleep 10
if docker ps | grep -q "${cname}"; then
    echo "容器 ${cname} 启动成功"
else
    echo "容器 ${cname} 启动失败"
    docker logs "${cname}"
    exit 1
fi

