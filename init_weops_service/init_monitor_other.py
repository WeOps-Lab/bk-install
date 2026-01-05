import logging
from utils import safe_request

logger = logging.getLogger('monitor')

class MonitorOtherInit:
    def __init__(self, session, config):
        self.session = session
        self.config = config
        self.exceptions = set()
        logger.info("MonitorOtherInit initialized")

    def start(self):
        logger.info("==================Starting other monitor initialization==================")
        print("==================Starting other monitor initialization==================")

        self.sync_monitor_object()
        self.sync_alarm_center_group()
        self.init_metric_group()
        self.init_dashboard()
        self.sync_metrics()
        
        self.finalize()

    def sync_monitor_object(self):
        url = f"{self.config.paas_url}/o/weops_saas/monitor_mgmt/monitor_object/sync_monitor_object_to_monitor_and_uac/"
        response = safe_request(self.session, 'get', url, 'sync_monitor_object', self.exceptions)
        if response:
            logger.info("Successfully synchronized monitor object")
            print("Successfully synchronized monitor object")
        else:
            logger.error("Failed to synchronize monitor object")
            print("Failed to synchronize monitor object")

    def sync_alarm_center_group(self):
        url = f"{self.config.paas_url}/o/weops_saas/system/mgmt/role_manage/sync_alarm_center_group/"
        response = safe_request(self.session, 'get', url, 'sync_alarm_center_group', self.exceptions)
        if response:
            logger.info("Successfully synchronized alarm center group")
            print("Successfully synchronized alarm center group")
        else:
            logger.error("Failed to synchronize alarm center group")
            print("Failed to synchronize alarm center group")

    def init_metric_group(self):
        url = f"{self.config.paas_url}/o/weops_saas/monitor_mgmt/init_metric_group/"
        response = safe_request(self.session, 'get', url, 'init_metric_group', self.exceptions)
        if response:
            logger.info("Successfully initialized metric group")
            print("Successfully initialized metric group")
        else:
            logger.error("Failed to initialize metric group")
            print("Failed to initialize metric group")

    def init_dashboard(self):
        url = f"{self.config.paas_url}/o/weops_saas/monitor_mgmt/init_dashboard/"
        response = safe_request(self.session, 'get', url, 'init_dashboard', self.exceptions)
        if response:
            logger.info("Successfully initialized dashboard")
            print("Successfully initialized dashboard")
        else:
            logger.error("Failed to initialize dashboard")
            print("Failed to initialize dashboard")

    def sync_metrics(self):
        url = f"{self.config.paas_url}/o/weops_saas/monitor_mgmt/metric_group/sync_metrics/"
        response = safe_request(self.session, 'post', url, 'sync_metrics', self.exceptions, json={})
        if response and response.json().get("result") == True:
            logger.info("Successfully synchronized metrics")
            print("Successfully synchronized metrics")
        else:
            logger.error("Failed to synchronize metrics")
            print("Failed to synchronize metrics")

    def finalize(self):
        if self.exceptions:
            logger.error("Monitor other initialization encountered errors in the following steps:")
            for step in self.exceptions:
                logger.error(step)
            print("\033[31m==================Monitor other initialization encountered errors==================\033[0m")
        else:
            logger.info("==================Monitor other initialization completed==================")
            print("\033[32m==================Monitor other initialization completed==================\033[0m")
