#!/bin/bash
# 部署regestry
source /data/install/tools.sh
source /data/install/functions.sh
reg_consul_svc repo 8181 $LAN_IP
if [[ ! -d /data/registry ]];then
    mkdir -p /data/registry
fi

if [[ ! -f /opt/registry.conf ]];then
    cat <<EOF > /opt/registry.conf
version: 0.1
log:
  fields:
    service: registry
http:
  addr: :8181
storage:
  filesystem:
    rootdirectory: /data/registry
EOF
fi

if [[ ! $(docker ps -a|grep registry) ]];then
    docker run -d --net=host --restart=always --name registry -v /opt/registry.conf:/etc/docker/registry/config.yml:ro -v /data/registry:/data/registry docker-bkrepo.cwoa.net/ce1b09/weops-docker/registry:latest-arm
fi

images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^docker-bkrepo.cwoa.net/ce1b09/weops-docker/")

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