#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0
source ../weops_version
#IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/trino:422-amd64-v1.0.6"

VERSION="1.0.0"
PORT=8081


usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -m --mongodb-url          [必填] "mongodb的连接地址" ]
            [ -e --elasticsearch-url    [必填] "elasticsearch的连接地址" ]
            [ -eu --elasticsearch-username                 [必填] "elasticsearch的用户名" ]
            [ -ep --elasticsearch-paasword                 [必填] "elasticsearch的密码" ]
            [ -my --mysql-url         [必填] "mysql的url" ]
            [ -mu --mysql-username     [必填] "mysql的用户名" ]
            [ -mp --mysql-password     [必填] "mysql的密码" ]
            [ -i --influxdb-url        [必填] "influxdb的url" ]
            [ -ip --influxdb-password  [必填] "influxdb的密码" ]
            [ -iu --influxdb-username  [必填] "influxdb的用户名" ]
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
        --mongodb-url | -m)
            shift
            MONGODB_URL=$1
            ;;
        --elasticsearch-url | -e)
            shift
            ELASTICSEARCH_URL=$1
            ;;
        --elasticsearch-username | -eu)
            shift
            ELASTICSEARCH_USERNAME=$1
            ;;
        --elasticsearch-password | -ep)
            shift
            ELASTICSEARCH_PASSWORD=$1
            ;;
        --mysql-url | -my)  
            shift
            MYSQL_URL=$1
            ;;
        --mysql-username | -mu)
            shift
            MYSQL_USERNAME=$1
            ;;
        --mysql-password | -mp) 
            shift
            MYSQL_PASSWORD=$1
            ;;
        --influxdb-url | -i)   
            shift
            INFLUXDB_URL=$1
            ;;
        --influxdb-username | -iu)
            shift
            INFLUXDB_USERNAME=$1
            ;;
        --influxdb-password | -ip)
            shift
            INFLUXDB_PASSWORD=$1
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
if [[ -z $MONGODB_URL ]]; then
    error "缺少必填参数: --mongodb-url"
fi

if [[ -z $ELASTICSEARCH_URL ]]; then
    error "缺少必填参数: --elasticsearch-url"
fi

if [[ -z $MYSQL_URL ]]; then
    error "缺少必填参数: --mysql-url"
fi

if [[ -z $MYSQL_USERNAME ]]; then
    error "缺少必填参数: --mysql-username"
fi

if [[ -z $MYSQL_PASSWORD ]]; then
    error "缺少必填参数: --mysql-password"
fi

if [[ -z $INFLUXDB_URL ]]; then
    error "缺少必填参数: --influxdb-url"
fi

if [[ -z $INFLUXDB_USERNAME ]]; then
    error "缺少必填参数: --influxdb-username"
fi  

if [[ -z $INFLUXDB_PASSWORD ]]; then
    error "缺少必填参数: --influxdb-password"
fi  

if [[ -d /data/bkce/weops/trino/config/catalog ]]; then
    warning "已存在trino配置文件目录,跳过"
else
    install -d -m 755 /data/bkce/weops/trino/config/catalog
    chown -R 1000:1000 /data/bkce/weops/trino
fi


if [[ -f /data/bkce/weops/trino/config/config.properties ]]; then
    warning "已存在trino配置文件,文件会被覆盖"
fi
cat << EOF > /data/bkce/weops/trino/config/config.properties
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=8081
discovery.uri=http://localhost:8081
EOF

if [[ -f /data/bkce/weops/trino/config/jvm.config ]]; then
    warning "已存在trino jvm配置文件,文件会被覆盖"
fi
cat << EOF > /data/bkce/weops/trino/config/catalog/elasticsearch.properties
connector.name=elasticsearch
elasticsearch.host=${ELASTICSEARCH_URL}
elasticsearch.auth.user=${ELASTICSEARCH_USERNAME}
elasticsearch.auth.password=${ELASTICSEARCH_PASSWORD}
elasticsearch.security=PASSWORD
elasticsearch.port=9200
elasticsearch.default-schema-name=default
EOF

if [[ -f /data/bkce/weops/trino/config/catalog/mongodb.properties ]]; then
    warning "已存在trino mongodb配置文件,文件会被覆盖"
fi
cat << EOF > /data/bkce/weops/trino/config/catalog/mongodb.properties
connector.name=mongodb
mongodb.connection-url=${MONGODB_URL}
mongodb.case-insensitive-name-matching=true
EOF

if [[ -f /data/bkce/weops/trino/config/catalog/mysql.properties ]]; then
    warning "已存在trino mysql配置文件,文件会被覆盖"
fi
cat << EOF > /data/bkce/weops/trino/config/catalog/mysql.properties
connector.name=mysql
connection-url=${MYSQL_URL}
connection-user=${MYSQL_USERNAME}
connection-password=${MYSQL_PASSWORD}
EOF

if [[ -f /data/bkce/weops/trino/config/catalog/influxdb.properties ]]; then
    warning "已存在trino influxdb配置文件,文件会被覆盖"
fi
cat << EOF > /data/bkce/weops/trino/config/catalog/influxdb.properties
connector.name=influxdb
influx.endpoint=${INFLUXDB_URL}
influx.username=${INFLUXDB_USERNAME}
influx.password=${INFLUXDB_PASSWORD}
EOF

if [[ -f /data/bkce/weops/trino/config/jvm.config ]]; then
    warning "已存在trino jvm配置文件,文件会被覆盖"
fi
cat << EOF > /data/bkce/weops/trino/config/jvm.config
-server
-agentpath:/usr/lib/trino/bin/libjvmkill.so
-Xmx2G
-XX:MaxRAMPercentage=80
-XX:G1HeapRegionSize=32M
-XX:+ExplicitGCInvokesConcurrent
-XX:+HeapDumpOnOutOfMemoryError
-XX:+ExitOnOutOfMemoryError
-XX:-OmitStackTraceInFastThrow
-XX:ReservedCodeCacheSize=256M
-XX:PerMethodRecompilationCutoff=10000
-XX:PerBytecodeRecompilationCutoff=10000
-Djdk.attach.allowAttachSelf=true
-Djdk.nio.maxCachedBufferSize=2000000
-XX:+UnlockDiagnosticVMOptions
-XX:+UseAESCTRIntrinsics
-XX:-G1UsePreventiveGC
EOF


if [[ $(docker ps -a|grep trino) ]]; then
    warning "已存在trino容器,将删除"
    docker rm -f trino
fi 

docker run -d -v /data/bkce/weops/trino/config/config.properties:/etc/trino/config.properties:ro \
            -v /data/bkce/weops/trino/config/catalog:/etc/trino/catalog:ro \
            -v /data/bkce/weops/trino/config/jvm.config:/etc/trino/jvm.config:ro \
            --restart=always \
            --net=host \
            --name=trino \
            ${TRINO_IMAGE}