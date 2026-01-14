import argparse
import logging
import requests
import time

from config import Config
from init_cmdb import CMDBInit
from init_monitor import MonitorInit
from init_monitor_other import MonitorOtherInit
from init_itsm import ITSMInit
from modify_login_session import ModifyLoginSession

import logging_config  # 导入日志配置


logger = logging.getLogger('main')

def log_execution_time(module_name, start_time, end_time):
    elapsed_time = end_time - start_time
    logger.info(f"{module_name} initialization completed in {elapsed_time:.2f} seconds")
    print(f"\033[32m{module_name} initialization completed in {elapsed_time:.2f} seconds\033[0m")

def initialize_module(module_class, session, config, module_name):
    start_time = time.time()
    try:
        module_instance = module_class(session, config)
        module_instance.start()
    except Exception as e:
        logger.error(f"Error during {module_name} initialization: {e}")
    finally:
        end_time = time.time()
        log_execution_time(module_name, start_time, end_time)

def main():
    parser = argparse.ArgumentParser(description="Initialize WeOps Service")
    parser.add_argument("--cmdb", action="store_true", help="Enable CMDB initialization")
    parser.add_argument("--monitor", action="store_true", help="Enable monitor initialization")
    parser.add_argument("--itsm", action="store_true", help="Enable ITSM initialization")

    args = parser.parse_args()

    config = Config()
    session = requests.Session()  # 创建一个会话对象

    # 实例化 ModifyLoginSession 来完成登录和CSRF初始化
    modify_login = ModifyLoginSession(session, config)
    
    if args.cmdb:
        initialize_module(CMDBInit, session, config, "CMDB")

    if args.monitor:
        initialize_module(MonitorInit, session, config, "Monitor")
        initialize_module(MonitorOtherInit, session, config, "MonitorOther")

    if args.itsm:
        initialize_module(ITSMInit, session, config, "ITSM")

if __name__ == "__main__":
    main()
