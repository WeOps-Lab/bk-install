#!/bin/bash
set -euo pipefail
PROGRAM=$(basename "$0")
EXITCODE=0

source ../weops_version
# IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/prometheus:2.38.0"

VERSION="1.0.0"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -a --auth             [必填] "prometheus basic auth密码" ]
            [ -u --user             [必填] "prometheus basic auth用户" ]
            [ -s --secret           [必填] "prometheus basic auth密钥,base64格式编码" ]
            [ -m --master           [必填] "prometheus master节点" ]
            [ -b --bind             [必填] "prometheus绑定的ip地址" ]
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
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --auth | -a)
            shift
            PROMETHEUS_AUTH=$1
            ;;
        --user | -u)
            shift
            PROMETHEUS_USER=$1
            ;;
        --secret | -s)
            shift
            PROMETHEUS_SECRET=$1
            ;;
        --master | -m)
            shift
            PROMETHEUS_MASTER=$1
            ;;
        --bind | -b)
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

if [[ -d /data/weops/prometheus/tsdb ]]; then
    warning "Promtheus tsdb path already exists, skip."
else
    install -d -g 1001 -o 1001  /data/weops/prometheus/tsdb
fi

if [[ -f /data/weops/prometheus/prometheus-web.yml ]]; then
    warning "Prometheus web config already exists, overwrite it."
fi
cat << EOF > /data/weops/prometheus/prometheus.yml
global:
  scrape_interval: 1m # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 1m # Evaluate rules every 15 seconds. The default is every 1 minute.

rule_files:
- /opt/bitnami/prometheus/conf/rules.yml
- /opt/bitnami/prometheus/conf/rules/extra_rules.yml

remote_write:
  - url: "http://${PROMETHEUS_USER}:${PROMETHEUS_AUTH}@kafka-adapter.service.consul:8080/receive"
    write_relabel_configs:
    - action: labeldrop
      regex: container_label_(.+)|id|name
EOF

if [[ -f /data/weops/prometheus/prometheus.yml ]]; then
    warning "Prometheus config already exists, overwrite it."
fi
cat << EOF > /data/weops/prometheus/prometheus-web.yml
basic_auth_users:
  ${PROMETHEUS_USER}: $(echo $PROMETHEUS_SECRET|base64 -d)
EOF

if [[ -f /data/weops/prometheus/rules.yml ]]; then
    warning "Prometheus rules already exists, overwrite it."
fi
cat << "EOF" > /data/weops/prometheus/rules.yml
groups:
- name: internal_metrics
  interval: 60s
  rules:
  # node cpu使用率
  - record: node_cpu_utilization
    expr: sum without (cpu) (1 - sum without (mode) (rate(node_cpu_seconds_total{mode=~"idle|iowait|steal",node!=""}[2m])))/ ignoring(cpu) group_left count without (cpu, mode) (node_cpu_seconds_total{mode="idle",node!=""})
  # node 磁盘使用量
  - record: node_filesystem_usage_bytes
    expr: node_filesystem_size_bytes{fstype!="", cluster!=""} - node_filesystem_avail_bytes{fstype!="", cluster!=""}
  # node 磁盘使用率
  - record: node_filesystem_utilization
    expr: node_filesystem_usage_bytes{cluster!=""} / node_filesystem_size_bytes{cluster!=""}
  # node 每分钟流量接收速率
  - record: node_network_receive
    expr: sum without(device)(rate(node_network_receive_bytes_total{cluster!=""}[2m]))
  # node 每分钟流量发送速率
  - record: node_network_transmit
    expr: sum without(device)(rate(node_network_transmit_bytes_total{cluster!=""}[2m]))
  # node 应用内存使用量
  - record: node_app_memory_usage_bytes
    expr: node_memory_MemTotal_bytes{cluster!=""} - node_memory_MemAvailable_bytes{cluster!=""}
  # node 应用内存使用率
  - record: node_app_memory_utilization
    expr: node_app_memory_usage_bytes{cluster!=""} / node_memory_MemTotal_bytes{cluster!=""}
  # node 物理内存使用量
  - record: node_physical_memory_usage_bytes
    expr: node_memory_MemTotal_bytes{cluster!=""} - node_memory_MemFree_bytes{cluster!=""}
  # node 物理内存使用率
  - record: node_physical_memory_utilization
    expr: node_physical_memory_usage_bytes{cluster!=""} / node_memory_MemTotal_bytes{cluster!=""}
  
  # pod cpu 10秒平均负载
  - record: pod_cpu_load
    expr: sum without(container) (container_cpu_load_average_10s{cluster!="",image!=""})
  # pod 每分钟发送流量
  - record: pod_network_transmit
    expr: sum without(interface, image)(rate(container_network_transmit_bytes_total{cluster!="",image!="", pod!=""}[2m]))
  # pod 每分钟接收流量
  - record: pod_network_receive
    expr: sum without(interface, image)(rate(container_network_receive_bytes_total{cluster!="", image!="", pod!=""}[2m]))
  # pod 容器内存使用率
  - record: container_memory_utilization
    expr: container_memory_usage_bytes{cluster!="", container!="", image!="", namespace!="", pod!=""} / container_spec_memory_limit_bytes {cluster!="", container!="", image!="", namespace!="", pod!=""}
  # pod 内存使用率
  - record: pod_memory_utilization
    expr: sum without(container)(container_memory_usage_bytes{cluster!="", container!="", image!="", namespace!="", pod!=""} / container_spec_memory_limit_bytes {cluster!="", container!="", image!="", namespace!="", pod!=""})
  # pod 容器CPU使用率
  - record: container_cpu_utilization
    expr: sum without(cpu)(irate(container_cpu_usage_seconds_total{cluster!="",container!="",image!="",namespace!="",pod!=""}[2m]))
  # pod CPU使用率
  - record: pod_cpu_utilization
    expr: sum without(cpu,container)(irate(container_cpu_usage_seconds_total{cluster!="",container!="",image!="",namespace!="",pod!=""}[2m]))
  # pod 内存使用量
  - record: pod_memory_usage
    expr: sum without(container)(container_memory_usage_bytes{cluster!="",container!="",namespace!="",pod!="",image!=""})
- name: ifmib
  interval: 30s
  rules:
  - record: ifInBroadcastPkts_5min
    expr: increase(ifInBroadcastPkts[5m])
  - record: ifInDiscards_5min
    expr: increase(ifInDiscards[5m])
  - record: ifInErrors_5min
    expr: increase(ifInErrors[5m])
  - record: ifInMulticastPkts_5min
    expr: increase(ifInMulticastPkts[5m])
  - record: ifInOctets_5min
    expr: irate(ifInOctets[5m])*8
  - record: ifInUcastPkts_5min
    expr: increase(ifInUcastPkts[5m])
  - record: ifOutBroadcastPkts_5min
    expr: increase(ifOutBroadcastPkts[5m])
  - record: ifOutDiscards_5min
    expr: increase(ifOutDiscards[5m])
  - record: ifOutErrors_5min
    expr: increase(ifOutErrors[5m])
  - record: ifOutMulticastPkts_5min
    expr: increase(ifOutMulticastPkts[5m])
  - record: ifOutOctets_5min
    expr: irate(ifOutOctets[5m])*8
  - record: ifOutUcastPkts_5min
    expr: increase(ifOutUcastPkts[5m])
EOF

if [[ -d /data/weops/prometheus/templates ]]; then
    warning "Prometheus templates already exists, skip."
else
    install -d /data/weops/prometheus/templates
fi

if [[ -f /data/weops/prometheus/templates/extra_rules.yml.tpl ]]; then
    warning "Prometheus extra rules template already exists, overwrite it."
fi
cat << "EOF" > /data/weops/prometheus/templates/extra_rules.yml.tpl
groups:
- name: extra_metrics
  interval: 30s
  rules:
{{ range ls "weops/global/metrics" }}{{ with $d := .Value| parseYAML }}  - record: {{ $d.record }}
    expr: {{ $d.expr }}{{end}}
{{ end }}
EOF

if [[ -f /data/weops/prometheus/rules/extra_rules.yml ]]; then
    warning "Prometheus extra rules already exists, overwrite it."
else
    install -d -g 1001 -o 1001 /data/weops/prometheus/rules
fi
echo "" > /data/weops/prometheus/rules/extra_rules.yml

if [[ -f /data/weops/prometheus/extra_rules.hcl ]]; then
    warning "weops-template hcl file already exists, overwrite it."
fi
cat << EOF > /data/weops/prometheus/extra_rules.hcl
template {
  source = "/data/weops/prometheus/templates/extra_rules.yml.tpl"
  destination = "/data/weops/prometheus/extra_rules.yml"
  command = "curl -X POST http://${PROMETHEUS_USER}:${PROMETHEUS_AUTH}@prometheus.service.consul/-/reload || echo panic"
}
EOF

if [[ -d /data/weops/prometheus/rules ]]; then
    warning "Prometheus rules path already exists, skip."
else
    install -d -g 1001 -o 1001 /data/weops/prometheus/rules
fi

if systemctl is-active --quiet weops-template; then
    warning "weops-template service already exists, skip."
else
    cat << "EOF" > /usr/lib/systemd/system/weops-template.service
[Unit]
Description=Generic template rendering and notifications with Consul for weops proxy
Documentation=https://wedoc.canway.net
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/consul-template -consul-addr 127.0.0.1:8501 -config /data/weops/prometheus/extra_rules.hcl
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF
fi

if [[ $(docker ps -a | grep prometheus) ]]; then
    warning "Prometheus container already exists, delete it."
    docker rm -f prometheus
fi


docker run -d --restart=always --net=host \
-v /data/weops/prometheus/prometheus-web.yml:/opt/bitnami/prometheus/conf/prometheus-web.yml \
-v /data/weops/prometheus/prometheus.yml:/opt/bitnami/prometheus/conf/prometheus.yml \
-v /data/weops/prometheus/rules.yml:/opt/bitnami/prometheus/conf/rules.yml \
-v /data/weops/prometheus/rules:/opt/bitnami/prometheus/conf/rules \
-v /data/weops/prometheus/tsdb:/opt/bitnami/prometheus/tsdb \
--name=prometheus $PROMETHEUS_IMAGE \
--web.listen-address=0.0.0.0:9093 \
--web.enable-remote-write-receiver \
--web.config.file=/opt/bitnami/prometheus/conf/prometheus-web.yml \
--storage.tsdb.path=/opt/bitnami/prometheus/tsdb \
--web.enable-lifecycle \
--config.file=/opt/bitnami/prometheus/conf/prometheus.yml --storage.tsdb.retention.time=30m

systemctl enable --now weops-template
if [[ $PROMETHEUS_MASTER == "true" ]]; then
  if [[ -f /etc/consul.d/service/prometheus.json ]]; then
    warning "Consul service definition already exists, overwrite it."
  fi
  cat << EOF > /etc/consul.d/service/prometheus.json
{
    "service": {
        "id": "prometheus-master",
        "name": "prometheus",
        "address": "paas.service.consul",
        "port": 80,
        "check": {
            "tcp": "${BIND_IP}:9093",
            "interval": "10s",
            "timeout": "3s"
        }
    }
}
EOF
  consul reload
else
  if [[ -f /etc/consul.d/service/prometheus.json ]]; then
    warning "Consul service definition already exists, delete it."
  fi
  cat << EOF > /etc/consul.d/service/prometheus.json
{
    "service": {
        "id": "prometheus-backup",
        "name": "prometheus",
        "address": "paas.service.consul",
        "port": 80,
        "check": {
            "tcp": "${BIND_IP}:9093",
            "interval": "10s",
            "timeout": "3s"
        }
    }
}
EOF
  consul reload
fi