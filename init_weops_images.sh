#!/bin/bash
source /data/install/weops_version
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 加载环境变量和函数
if [[ -r ${SELF_DIR}/tools.sh ]]; then
    source "${SELF_DIR}/tools.sh"
else
    echo "${SELF_DIR}/tools.sh 不存在" >&2
    exit 1
fi

# 配置 hosts 解析
contrl_ip=`cat /data/install/.controller_ip`
/data/install/pcmd.sh -m all "
if ! grep -q 'repo.service.consul' /etc/hosts; then
  echo '$contrl_ip repo.service.consul' >> /etc/hosts
fi
"

# 配置 Docker insecure-registries
/data/install/pcmd.sh -m all "
if [ ! -f /etc/docker/daemon.json ] || ! grep -q 'insecure-registries' /etc/docker/daemon.json; then
  cat > /etc/docker/daemon.json <<DOCKEREOF
{
  \"insecure-registries\": [\"repo.service.consul:8181\", \"$contrl_ip:8181\"]
}
DOCKEREOF
  systemctl daemon-reload
  systemctl restart docker
fi
"

# docker load < /data/ubuntu/images/registry.tgz
if [[ ! -f /opt/registry.conf ]];then
    cat <<REGEOF > /opt/registry.conf
version: 0.1
log:
  fields:
    service: registry
http:
  addr: :8181
storage:
  filesystem:
    rootdirectory: /data/registry
REGEOF
fi

if [[ ! $(docker ps -a|grep registry) ]];then
    docker run -d --net=host --restart=always --name registry -v /opt/registry.conf:/etc/docker/registry/config.yml:ro -v /data/registry:/data/registry ${REGISTRY_IMAGE}
fi

echo "开始导入镜像..."
gunzip -c ${BK_PKG_SRC_PATH}/weops-images.tar | docker load

images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^docker-bkrepo.cwoa.net/ce1b09/weops-docker/")

contrl_ip=`cat /data/install/.controller_ip`
if cat /etc/hosts | grep ''$contrl_ip' repo.service.consul';then
    echo "hosts文件已存在repo.service.consul记录"
else
    echo "添加hosts文件记录repo.service.consul"
    /data/install/pcmd.sh -m all "echo '$contrl_ip repo.service.consul' >> /etc/hosts"
fi


# 遍历每个镜像并重新打标签
for image in $images; do
    # 获取镜像ID
    image_id=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep "$image" | awk '{print $2}')
    
    # 构建新的镜像名称，替换仓库地址
    new_image=$(echo $image | sed 's#^docker-bkrepo.cwoa.net/ce1b09/weops-docker/#repo.service.consul:8181/#')
    
    # 重新打标签
    docker tag "$image_id" "$new_image"
    
    echo "已将镜像 $image 重新标记为 $new_image"
    docker push "$new_image"
done
