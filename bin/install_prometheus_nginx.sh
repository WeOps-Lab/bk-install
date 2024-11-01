#!/bin/bash
set -euo pipefail
warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -m --master               [必填] "prometheus master节点IP" ]
            [ -s --slave                [必填] "prometheus salve节点IP" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --master | -m)
            shift
            MASTER_IP=$1
            ;;
        --slave | -s)
            shift
            SLAVE_IP=$1
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

log "master ip: $MASTER_IP"
log "slave ip: $SLAVE_IP"
log "generate prometheus proxy config to /usr/local/openresty/nginx/conf/conf.d/prometheus.conf"
cat <<EOF > /usr/local/openresty/nginx/conf/conf.d/prometheus.conf
upstream PROMETHEUS {
        server $MASTER_IP:9093 max_fails=1 fail_timeout=30s;
        server $SLAVE_IP:9093 backup max_fails=1 fail_timeout=30s;
}

server {
    listen 80;
    server_name  prometheus.service.consul;

    client_max_body_size    512m;
    access_log  /data/bkce/logs/nginx/prometheus_access.log main;
    error_log  /data/bkce/logs/nginx/prometheus_error.log error;
    
    location / {
        proxy_pass http://PROMETHEUS;
        proxy_pass_header Server;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Scheme \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_redirect off;
        proxy_read_timeout 600;
    }
}
EOF

log "reload nginx"
/usr/local/openresty/nginx/sbin/nginx -s reload
log "reload done"