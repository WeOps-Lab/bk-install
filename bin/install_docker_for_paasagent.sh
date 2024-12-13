#!/usr/bin/env bash
# install_docker_for_paasagent.sh ：安装，配置docker
set -e

SELF_DIR="$(dirname "$(readlink -f "$0")")"

source ${SELF_DIR}/../load_env.sh
source ${SELF_DIR}/../functions

export DEBIAN_FRONTEND=noninteractive

#加载版本
set -a
source /data/install/weops_version
set +a
# 卸载旧版本
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
apt autoremove -y

if ! dpkg -l  docker-ce=$DOCKER_VERSION; then
    apt-get install docker-ce=$DOCKER_VERSION -y
fi

# TODO: 需要自定义下daemon.json(参考dockerctl的start_docker()函数)
[[ -d /etc/docker ]] || mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
    "data-root": "$BK_HOME/public/paas_agent/docker",
    "insecure-registries": ["repo.service.consul:8181"],
    "exec-opts": ["native.cgroupdriver=cgroupfs"],
    "bridge": "none", 
    "iptables": false, 
    "ip-forward": true,
    "live-restore": true, 
    "log-level": "info",
    "log-driver": "json-file", 
    "log-opts": {
        "max-size": "500m",
        "max-file":"5"
    },
  "default-ulimits": {
    "core": {
      "Name": "core",
      "Hard": 0,
      "Soft": 0
    }
  },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF

mkdir -p $BK_HOME/public/paas_agent/docker
systemctl enable --now docker
# 为了让blueking身份运行的paasagent也能运行docker cli命令。
usermod -G docker blueking

if [[ -d  ${BK_PKG_SRC_PATH}/image ]];then
    echo "load docker images"
    docker load < ${BK_PKG_SRC_PATH}/image/python27e_1.0.tar
    docker load < ${BK_PKG_SRC_PATH}/image/python36e_1.0.tar 
    # 同步工具
    rsync -avz ${BK_PKG_SRC_PATH}/image/runtool /usr/bin/
    chmod +x  /usr/bin/runtool
else
    warn "docker images not found"
fi