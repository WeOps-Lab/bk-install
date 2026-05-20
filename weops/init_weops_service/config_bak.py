import logging
from utils import get_env_variable, get_app_secret

logger = logging.getLogger('main')

class Config:
    def __init__(self):
        self.env_vars = {
            'db_user': "$BK_MYSQL_ADMIN_USER",
            'db_password': "$BK_MYSQL_ADMIN_PASSWORD",
            'db_host': "$BK_MYSQL_IP",
            'bk_user': "$BK_PAAS_ADMIN_USERNAME",
            'bk_password': "$BK_PAAS_ADMIN_PASSWORD",
            'paas_url': "$BK_PAAS_PUBLIC_URL",
            'cmdb_url': "$BK_CMDB_PUBLIC_URL"
        }

        self.empty_vars = []

        # 使用映射字典获取环境变量值
        self.db_user = self.get_env_variable_checked('db_user')
        self.db_password = self.get_env_variable_checked('db_password')
        self.db_host = self.get_env_variable_checked('db_host')
        self.bk_user = self.get_env_variable_checked('bk_user')
        self.bk_password = self.get_env_variable_checked('bk_password')
        self.paas_url = self.get_env_variable_checked('paas_url')
        self.cmdb_url = self.get_env_variable_checked('cmdb_url')
        self.monitor_url = f"{self.paas_url.strip('/')}/o/bk_monitorv3"

        self.app_code = "weops_saas"
        self.app_secret = get_app_secret(self.db_user, self.db_password, self.db_host, self.app_code)
        self.config_list = [self.bk_user, self.bk_password, self.paas_url, self.cmdb_url, self.monitor_url]

        if self.empty_vars:
            logger.error(f"The following environment variables are empty: {', '.join(self.empty_vars)}")
            raise ValueError(f"The following environment variables are empty: {', '.join(self.empty_vars)}")

        self.group_map = self.load_group_map()
        self.plugin_mapping = self.generate_plugin_mapping()

    def get_env_variable_checked(self, var_name):
        command = f"source /data/install/utils.fc && echo {self.env_vars[var_name]}"
        value = get_env_variable(command)
        if not value:
            self.empty_vars.append(var_name)
            logger.error(f"Environment variable {var_name} is empty.")
        return value

    def load_group_map(self):
        # 返回监控对象&对象分组映射
        return {
            # 示例：
            # "${bk_obj_id}": {"bk_obj_name": "${bk_obj_name}", "bk_classification_id": "${bk_classification_id}", "group_id": "${group_id}", "group_name": "${group_name}"}

            # Database configurations
            "mssql": {"bk_obj_name": "MSSQL", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "mysql": {"bk_obj_name": "MySQL", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "oracle": {"bk_obj_name": "Oracle", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "mongodb": {"bk_obj_name": "MongoDB", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "redis": {"bk_obj_name": "Redis", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "postgresql": {"bk_obj_name": "PGSQL", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "elasticsearch": {"bk_obj_name": "ElasticSearch", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "oceanbase": {"bk_obj_name": "OceanBase", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "doris": {"bk_obj_name": "Doris", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "sybase": {"bk_obj_name": "Sybase", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "shentongdb": {"bk_obj_name": "ShentongDB", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "clickhouse": {"bk_obj_name": "ClickHouse", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "dm": {"bk_obj_name": "DM", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "opengauss": {"bk_obj_name": "OpenGauss", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "db2": {"bk_obj_name": "DB2", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "kingbase": {"bk_obj_name": "KingBase", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            "vastbase": {"bk_obj_name": "VastBase", "bk_classification_id": "bk_database", "group_id": "SQL", "group_name": "数据库"},
            # Middleware configurations
            "apache": {"bk_obj_name": "Apache", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "tomcat": {"bk_obj_name": "Tomcat", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "nginx": {"bk_obj_name": "Nginx", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "kafka": {"bk_obj_name": "Kafka", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "rabbitmq": {"bk_obj_name": "RabbitMQ", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "iis": {"bk_obj_name": "IIS", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "exchange_server": {"bk_obj_name": "Exchange_Server", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "active_directory": {"bk_obj_name": "Active_Directory", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "zookeeper": {"bk_obj_name": "ZooKeeper", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "ibmmq": {"bk_obj_name": "IBM_MQ", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "nacos": {"bk_obj_name": "Nacos", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "minio": {"bk_obj_name": "Minio", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "weblogic": {"bk_obj_name": "WebLogic", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "haproxy": {"bk_obj_name": "HAProxy", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "rocketmq": {"bk_obj_name": "RocketMQ", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "tongweb": {"bk_obj_name": "TongWeb", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "inforsuite_as": {"bk_obj_name": "InforSuite_AS", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "apusic": {"bk_obj_name": "Apusic", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
            "keepalived": {"bk_obj_name": "Keepalived", "bk_classification_id": "bk_middleware", "group_id": "middleware", "group_name": "中间件"},
        }

    def generate_plugin_mapping(self):
        # 返回监控插件映射
        return {
            # 示例：
            # '${plugin_file_name}': '${plugin_id}'

            # Database Plugins
            'weops_mssql_exporter_v4.2.2.tgz': 'weops_mssql_exporter',
            'weops_mysql_exporter_v4.2.4.tgz': 'weops_mysql_exporter',
            'weops_oracledb_exporter_v3.1.4.tgz': 'weops_oracledb_exporter',
            'weops_mongodb_exporter_v3.3.4.tgz': 'weops_mongodb_exporter',
            'weops_redis_exporter_v4.0.4.tgz': 'weops_redis_exporter',
            'weops_postgres_exporter_v3.1.4.tgz': 'weops_postgres_exporter',
            'weops_elasticsearch_exporter_v4.3.3.tgz': 'weops_elasticsearch_exporter',
            'weops_oceanbase_exporter_v4.2.1.tgz': 'weops_oceanbase_exporter',
            'dorisbe_bkpull.tgz': 'dorisbe_bkpull',
            'dorisfe_bkpull.tgz': 'dorisfe_bkpull',
            'weops_sybase_exporter_v4.2.1.tgz': 'weops_sybase_exporter',
            'weops_shentongdb_exporter_v1.0.1.tgz': 'weops_shentongdb_exporter',
            'weops_clickhouse_exporter_v3.1.5.tgz': 'weops_clickhouse_exporter',
            'weops_dm_exporter_v4.2.1.tgz': 'weops_dm_exporter',
            'weops_opengauss_exporter_v4.2.1.tgz': 'weops_opengauss_exporter',
            'weops_db2_exporter_v1.2.5.tgz': 'weops_db2_exporter',
            'weops_kingbase_exporter_v4.2.1.tgz': 'weops_kingbase_exporter',
            'weops_vastbase_exporter_v4.2.1.tgz': 'weops_vastbase_exporter',
            
            # Middleware Plugins
            'weops_ad_exporter_v2.6.0.tgz': 'weops_ad_exporter',
            'weops_apache_exporter_v1.0.3.tgz': 'weops_apache_exporter',
            'weops_exchange_exporter_v2.6.0.tgz': 'weops_exchange_exporter',
            'weops_ibmmq_exporter_v5.5.3.tgz': 'weops_ibmmq_exporter',
            'weops_IIS_exporter_v2.6.0.tgz': 'weops_IIS_exporter',
            'weops_kafka_exporter_v2.8.1.tgz': 'weops_kafka_exporter',
            'weops_nginx_exporter_v7.3.3.tgz': 'weops_nginx_exporter',
            'weops_rabbitmq_exporter_v2.1.9.tgz': 'weops_rabbitmq_exporter',
            'weops_tomcat_jmx_v2.1.0.tgz': 'weops_tomcat_jmx',
            'weops_zookeeper_exporter_v2.1.13.tgz': 'weops_zookeeper_exporter',
            'minio_bucket_bkpull.tgz': 'minio_bucket_bkpull',
            'minio_cluster_bkpull.tgz': 'minio_cluster_bkpull',
            'minio_resources_bkpull.tgz': 'minio_resources_bkpull',
            'nacos_bkpull.tgz': 'nacos_bkpull',
            'weops_weblogic_exporter_v2.1.1.tgz': 'weops_weblogic_exporter',
            'weops_haproxy_exporter_v0.15.0.tgz': 'weops_haproxy_exporter',
            'weops_rocketmq_exporter_v0.1.2.tgz': 'weops_rocketmq_exporter',
            'tongweb8_bkpull.tgz': 'tongweb8_bkpull',
            'weops_inforsuite_as_exporter_v2.1.0.tgz': 'weops_inforsuite_as_exporter',
            'weops_apusic_jmx_exporter_v1.1.2.tgz': 'weops_apusic_jmx_exporter',
            'weops_keepalived_exporter_v1.7.0.tgz': 'weops_keepalived_exporter',
        }
