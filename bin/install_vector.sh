#!/usr/bin/env bash
# 通用脚本框架变量
set -euo pipefail
PROGRAM=$(basename "$0")
EXITCODE=0

source /data/install/weops_version
#IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/vector:0.34.1-debian"

VERSION="1.0.0"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -u --username             [必填] "用户名" ]
            [ -p --password             [必填] "密码" ]
            [ -w --prometheus-remotewrite-url [必填] "prometheus-remotewrite-url" ]
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
        --username | -u)
            shift
            USERNAME=$1
            ;;
        --password | -p)
            shift
            PASSWORD=$1
            ;;
        --prometheus-remotewrite-url | -w)
            shift
            PROMETHEUS_REMOTEWRITE_URL=$1
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
if [[ -z ${USERNAME} ]]; then
    error "用户名不能为空"
fi

if [[ -z ${PASSWORD} ]]; then
    error "密码不能为空"
fi

if [[ -z ${PROMETHEUS_REMOTEWRITE_URL} ]]; then
    error "prometheus-remotewrite-url不能为空"
fi

if [[ -d /data/weops/vector ]]; then
    warning "已存在/data/weops/vector目录,跳过"
else
    install -d -m 0644 /data/weops/vector
fi

cat <<EOF > /data/weops/vector/vector.yaml
api:
  enabled: false
sources:
  # 接收kafka数据
  kafka_in:
    type: kafka
    bootstrap_servers: "kafka.service.consul:9092"
    group_id: "vector"
    topics:
      - ^0bkmonitor_.*
transforms:
  # 转换kafka数据
  parse_kafka:
    type: remap
    inputs:
      - kafka_in
    source: |-
      .all_data = parse_json!(.message)
      if exists(.all_data.type) && exists(.all_data.service.type){
        if (.all_data.type == "metricbeat") && (.all_data.service.type == "prometheus"){
          .metrics = .all_data.prometheus.collector.metrics
          .bk_data.bk_biz_id = to_string!(.all_data.bk_biz_id)
          .bk_data.bk_cloud_id = to_string!(.all_data.bk_cloud_id)
          .bk_data.bk_data_id = to_string!(.all_data.dataid)
          .bk_group_info = .all_data.group_info
        }
      }
  # 转换为vector prometheus exporter 指标格式
  to_metric:
    type: lua
    inputs:
      - parse_kafka
    version: '2'
    hooks:
      process: |
        function (event, emit)
          -- 指标和维度
          local metrics = event.log.metrics
          local bk_data = event.log.bk_data
          local group_info = event.log.bk_group_info
          -- 检查解析后的数据
          if event.log.metrics == nil then
            return
          end
          if event.log.bk_data == nil then
            return
          end
          -- 推送事件
          for _, m in ipairs(metrics) do
            m.labels.bk_data_id = bk_data.bk_data_id
            m.labels.bk_biz_id = bk_data.bk_biz_id
            m.labels.bk_cloud_id = bk_data.bk_cloud_id
            if group_info then
              for _, g in ipairs(group_info) do
                m.labels.bk_collect_config_id = g.bk_collect_config_id or ""
                m.labels.bk_target_cloud_id = g.bk_target_cloud_id or ""
                m.labels.bk_target_ip = g.bk_target_ip or ""
                m.labels.bk_target_service_category_id = g.bk_target_service_category_id or ""
                m.labels.bk_target_service_instance_id = g.bk_target_service_instance_id or ""
                m.labels.bk_target_topo_id = g.bk_target_topo_id or ""
                m.labels.bk_target_topo_level = g.bk_target_topo_level or ""
              end
            end
            
            local new_event = {
              metric = {
                gauge = {
                  value = m.value
                },
                name = m.key,
                tags = m.labels
              }
            }
            if m.labels.protocol == nil then
              emit(new_event)
            end
          end
        end
sinks:
  prometheus_remote_write:
    type: prometheus_remote_write
    inputs:
      - to_metric
    endpoint: "${PROMETHEUS_REMOTEWRITE_URL}"
    auth:
      strategy: "basic"
      user: "${USERNAME}"
      password: "${PASSWORD}"
EOF


if [[ $(docker ps -a|grep vector) ]]; then
    warning "已存在vector容器,将删除"
    docker rm -f vector
fi

docker run -d --net=host -v /data/weops/vector/vector.yaml:/etc/vector/vector.yaml:ro \
    --name vector \
    --privileged \
    ${VECTOR_IMAGE} --watch-config