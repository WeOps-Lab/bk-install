import logging
import os
import time
from utils import get_env_variable 
from utils import safe_request

logger = logging.getLogger('monitor')

class MonitorInit:
    def __init__(self, session, config):
        self.session = session
        self.config = config
        self.exceptions = set()
        self.existing_plugins = self.fetch_existing_plugins()
        self.error_occurred = False  # 标志位，记录是否发生错误
        self.obj_list = []  # 初始化 obj_list 属性，用于记录需要初始化的对象列表
        logger.info("MonitorInit initialized")

    def start(self):
        logger.info("==================Starting monitor initialization==================")
        print("==================Starting monitor initialization==================")
        self.disable_plugin_debug()
        self.init_plugins()
        self.check_plugin_status()
        self.check_plugin_associations()
        self.finalize()

    def disable_plugin_debug(self):
        try:
            db_user = self.config.db_user
            db_password = self.config.db_password
            db_host = self.config.db_host

            check_value_command = f'''
                docker exec mysql-client mysql -u{db_user} -p{db_password} -h {db_host} -N --database bkmonitorv3_alert -e "select \`value\` from global_setting where \`key\`='SKIP_PLUGIN_DEBUG';"
            '''
            value = get_env_variable(check_value_command)
            if value == "true":
                logger.info("SKIP_PLUGIN_DEBUG configuration does not need to be changed, skipping")
                print("SKIP_PLUGIN_DEBUG configuration does not need to be changed, skipping")
            else:
                update_command = f'''
                    docker exec mysql-client mysql -u{db_user} -p{db_password} -h {db_host} -N --database bkmonitorv3_alert -e "update global_setting set \`value\`='true' where \`key\`='SKIP_PLUGIN_DEBUG';"
                '''
                get_env_variable(update_command)
                check_result = get_env_variable(check_value_command)
                if check_result == "true":
                    logger.info("SKIP_PLUGIN_DEBUG configuration updated successfully")
                    print("SKIP_PLUGIN_DEBUG configuration updated successfully")
                else:
                    logger.error("SKIP_PLUGIN_DEBUG configuration update failed")
                    print("SKIP_PLUGIN_DEBUG configuration update failed")
                    self.exceptions.add("disable_plugin_debug")
                    self.error_occurred = True
        except Exception as e:
            logger.error(f"Exception in disable_plugin_debug: {e}")
            self.exceptions.add("disable_plugin_debug")
            self.error_occurred = True

    def fetch_existing_plugins(self):
        url = f'{self.config.monitor_url}/rest/v2/collector_plugin/?search_key=&plugin_type=&page=1&page_size=100&order=-update_time&labels=&bk_biz_id=2'
        try:
            response = self.session.get(url, verify=False)
            response.raise_for_status()  # 确保请求成功
            result = response.json()
            
            # 打印返回结果以进行调试
            logger.debug(f"Fetch Plugins API Response: {result}")
            
            # 确保 result 中有正确的数据
            if not result.get("result"):
                logger.error(f"Error fetching plugins: {result.get('message', 'Unknown error')}")
                return {}

            # 获取插件列表
            plugins = result.get("data", {}).get("list", [])
            logger.debug(f"Fetched plugins: {plugins}")  # 修改此行将调试信息记录到日志中
            
            # 将插件ID映射为插件对象，仅包含 plugin_id, plugin_display_name, plugin_type 和 status
            plugin_ids = {
                plugin["plugin_id"]: {
                    "plugin_display_name": plugin["plugin_display_name"],
                    "plugin_type": plugin["plugin_type"],
                    "status": plugin["status"]
                }
                for plugin in plugins
            }
            logger.info(f"Fetched existing plugins: {plugin_ids.keys()}")
            return plugin_ids
        except Exception as e:
            logger.error(f"Error fetching existing plugins: {e}")
            self.exceptions.add("fetch_existing_plugins")
            return {}


    def init_plugins(self):
        try:
            bk_obj_id_list = os.listdir(r"plugins")
            for bk_obj_id in bk_obj_id_list:
                plugin_list = os.listdir(f"plugins/{bk_obj_id}")
                obj_detail = self.config.group_map.get(bk_obj_id, {})
                logger.info(obj_detail)
                
                print(f"\033[34m===@@@Processing object: {obj_detail.get('bk_obj_name', 'Unknown object')}\033[0m")

                obj_info = {
                    "bk_obj_id": bk_obj_id,
                    "plugin_list": [],
                    "bk_classification_id": obj_detail["bk_classification_id"],
                    "group_id": obj_detail.get("group_id", ""),
                    "bk_obj_name": obj_detail.get("bk_obj_name", ""),
                    "related_field": f"{bk_obj_id}_install_on_host",
                    "object_id": bk_obj_id,
                    "object_name": obj_detail.get("bk_obj_name", ""),
                    "director_fields": [],
                    "display_fields": [{
                        "option": None,
                        "bk_property_id": "bk_inst_name",
                        "bk_property_name": "Instance name",
                        "bk_property_type": "string"
                    }]
                }

                logger.info(f"Existing plugins: {self.existing_plugins}")  # 将调试信息记录到日志中

                for i in plugin_list:
                    try:
                        plugin_data = self.init_one_plugin(i, bk_obj_id)
                        if plugin_data:
                            obj_info["plugin_list"].append(plugin_data)
                    except Exception as e:
                        logger.error(f"Exception in processing plugin {i} for object {bk_obj_id}: {e}")
                        self.exceptions.add(f"init_one_plugin: {i}")

                if obj_info["plugin_list"]:  # 仅当 plugin_list 不为空时才添加到 obj_list
                    self.obj_list.append(obj_info)
                    logger.info(f"Object {obj_info['bk_obj_name']} need to initialize...")
                    print(f"Object {obj_info['bk_obj_name']} need to initialize...")
                else:
                    logger.info(f"Object {obj_info['bk_obj_name']} not need to initialize")
                logger.info(f"Object {obj_info['bk_obj_name']} Plugins imported finish")
                print(f"Object {obj_info['bk_obj_name']} Plugins imported finish")
            logger.info("All Plugins have been imported finish")
            print("All Plugins have been imported finish")
            self.init_bk_obj_and_group()
        except Exception as e:
            logger.error(f"Exception in init_plugins: {e}")
            self.exceptions.add("init_plugins")

    def init_one_plugin(self, file_name, bk_obj_id):
        try:
            file_path = f"plugins/{bk_obj_id}/{file_name}"
            logger.info(f"Importing plugin {file_name} from {file_path}")
            print(f"Importing plugin {file_name} from {file_path}")

            # 检查插件是否已经存在
            plugin_id = self.config.plugin_mapping.get(file_name)
            logger.info(f"Checking plugin ID: {plugin_id}")
            if not plugin_id:
                logger.error(f"Plugin {file_name} does not have a mapping in plugin_mapping, skipping import")
                print(f"Plugin {file_name} does not have a mapping in plugin_mapping, skipping import")
                return {}

            if plugin_id in self.existing_plugins:
                logger.info(f"Plugin {file_name} already exists, skipping import")
                print(f"Plugin {file_name} already exists, skipping import")
                return {}

            import_data = self.import_plugin(file_path, file_name)
            logger.info(f"import_data {import_data}")
            
            # 检查 import_plugin 方法返回的数据是否为空
            if not import_data:
                logger.info(f"Conflict detected or import failed for plugin {file_name}, skipping further steps")
                print(f"Conflict detected or import failed for plugin {file_name}, skipping further steps")
                return {}

            plugin_obj = self.create_plugin(import_data)
            logger.info(f"plugin_obj {plugin_obj}")
            
            # 确保 plugin_obj 不为空
            if not plugin_obj:
                logger.error(f"Failed to create plugin object for {file_name}")
                return {}

            task_id = self.register_plugin(plugin_obj)
            logger.info(f"task_id {task_id}")
            
            if not task_id:
                logger.error(f"Failed to register plugin {file_name}")
                return {}

            if type(task_id) != list:
                token = self.query_async_task_result(task_id)
            else:
                token = task_id

            result = self.plugin_release(plugin_obj, token)
            if not result:
                logger.error(f"Failed to release plugin {file_name}")
                return {}

            return {
                "plugin_id": plugin_obj["plugin_id"],
                "plugin_display_name": plugin_obj["plugin_display_name"],
                "plugin_type": "blueking",
                "unique_id": f"{plugin_obj['plugin_id']}_blueking",
                "is_support_remote": plugin_obj["is_support_remote"]
            }
        except Exception as e:
            logger.error(f"Exception in init_one_plugin: {e}")
            self.exceptions.add("init_one_plugin")
            return {}

    def init_bk_obj_and_group(self):
        try:
            url = f"{self.config.paas_url}/o/weops_saas/open_api/create_obj_and_group/"
            if not self.obj_list:
                logger.info("No objects to initialize")
                print("No objects to initialize")
                return
            data = {"obj_list": self.obj_list}
            logger.info(data)
            try:
                res = self.session.post(url, json=data, verify=False).json()
                if res["result"]:
                    logger.info(res)
                    logger.info(f"Successfully initialized {len(self.obj_list)} monitoring alarm objects")
                    logger.info("Successfully initialized monitoring alarm objects")
                    print("Successfully initialized monitoring alarm objects")
                    return
            except Exception as e:
                logger.error(e)
            logger.error("Failed to initialize monitoring alarm objects")
            print("Failed to initialize monitoring alarm objects")
        except Exception as e:
            logger.error(f"Exception in init_bk_obj_and_group: {e}")
            self.exceptions.add("init_bk_obj_and_group")

    def check_plugin_status(self):
        try:
            # 等待10秒，确保上一步的初始化完成
            time.sleep(10)

            logger.info("Checking plugin status")
            print("\033[34m===@@@Checking plugin status\033[0m")

            # 获取当前插件状态
            url = f'{self.config.monitor_url}/rest/v2/collector_plugin/?search_key=&plugin_type=&page=1&page_size=100&order=-update_time&labels=&bk_biz_id=2'
            response = self.session.get(url, verify=False)
            response.raise_for_status()
            plugins = response.json().get("data", {}).get("list", [])  # 修改为从 "list" 中获取插件数据
            
            abnormal_plugins = []
            missing_plugins = []
            plugin_files = []

            # 获取所有插件文件列表
            bk_obj_id_list = os.listdir(r"plugins")
            for bk_obj_id in bk_obj_id_list:
                plugin_list = os.listdir(f"plugins/{bk_obj_id}")
                plugin_files.extend(plugin_list)

            # 创建一个现有插件ID的集合以进行快速查找
            existing_plugin_ids = {plugin["plugin_id"] for plugin in plugins}

            # 检查插件状态
            for plugin in plugins:
                if plugin["status"] != "normal":
                    abnormal_plugins.append(plugin)
                plugin_file_name = next((k for k, v in self.config.plugin_mapping.items() if v == plugin["plugin_id"]), None)
                if plugin_file_name and plugin_file_name not in plugin_files:
                    missing_plugins.append(plugin_file_name)

            # 检查缺失插件
            for file_name in plugin_files:
                if file_name not in self.config.plugin_mapping:
                    missing_plugins.append(file_name)
                elif self.config.plugin_mapping[file_name] not in existing_plugin_ids:
                    missing_plugins.append(file_name)

            if abnormal_plugins or missing_plugins:
                logger.warning(f"Abnormal plugins: {abnormal_plugins}")
                print(f"Abnormal plugins: {abnormal_plugins}")
                logger.warning(f"Missing plugins: {missing_plugins}")
                print(f"Missing plugins: {missing_plugins}")
                self.error_occurred = True
            else:
                logger.info("All plugins checked, they are normal")
                print("All plugins checked, they are normal")

        except Exception as e:
            logger.error(f"Error checking plugin status: {e}")
            self.exceptions.add("check_plugin_status")
            self.error_occurred = True

    def check_plugin_associations(self):
        try:
            # 等待5秒，确保上一步的初始化完成
            time.sleep(5)

            logger.info("Checking object plugin associations")
            print("\033[34m===@@@Checking object plugin associations\033[0m")

            # 获取所有对象列表
            url = f'{self.config.paas_url}/o/monitorcenter_saas/monitor/?bk_obj_name=&order_by=-id&page_size=100&page=1'
            response = safe_request(self.session, 'get', url, 'check_plugin_associations', self.exceptions)
            
            if response:
                response_data = response.json()
                if not response_data.get('result'):
                    logger.error(f"Error checking plugin associations: {response_data.get('message', 'Unknown error')}")
                    self.exceptions.add("check_plugin_associations")
                    self.error_occurred = True
                    return
                
                results = response_data.get('data', {}).get('results', [])
                logger.info(f"Fetched monitor objects: {results}")

                # 过滤 group_map 中的 bk_obj_id
                filtered_results = [result for result in results if result['bk_obj_id'] in self.config.group_map]

                # 汇总未正常关联的对象的 bk_obj_id
                unassociated_objects = []

                # 检查每个对象的 plugin_list 是否为空
                for result in filtered_results:
                    if not result['plugin_list']:
                        logger.error(f"Object {result['bk_obj_id']} has no associated plugins")
                        unassociated_objects.append(result['bk_obj_id'])
                    else:
                        logger.info(f"Object {result['bk_obj_id']} has associated plugins: {result['plugin_list']}")

                # 打印汇总结果
                if unassociated_objects:
                    logger.error(f"Objects with no associated plugins: {unassociated_objects}")
                    print(f"\033[31mObjects with no associated plugins: {unassociated_objects}\033[0m")
                    self.exceptions.add("check_plugin_associations")
                    self.error_occurred = True
                else:
                    logger.info("All objects have associated plugins")
                    print("All objects have associated plugins")
            else:
                logger.error("Failed to fetch monitor objects for plugin association check")
                self.exceptions.add("check_plugin_associations")
                self.error_occurred = True

        except Exception as e:
            logger.error(f"Exception in check_plugin_associations: {e}")
            self.exceptions.add("check_plugin_associations")
            self.error_occurred = True


    def import_plugin(self, file_path, file_name):
        try:
            url = f'{self.config.monitor_url}/rest/v2/collector_plugin/import_plugin/'
            logger.debug(f"URL: {url}")
            logger.debug(f"File path: {file_path}, File name: {file_name}")

            files = {'file_data': (file_name, open(f'{file_path}', 'rb'), 'application/octet-stream')}
            logger.debug(f"Files: {files}")

            response = self.session.post(url, files=files, verify=False, data={'bk_biz_id': 2})
            logger.debug(f"Response status code: {response.status_code}")
            logger.debug(f"Response content: {response.content}")

            response.raise_for_status()  # Ensure we raise an error for bad status codes
            result = response.json()
            logger.debug(f"Response JSON: {result}")

            data = result['data']
            if data.get("conflict_title"):
                logger.info("Conflict detected, returning empty dictionary")
                return {}

            data["bk_biz_id"] = 0
            plugin_key = [
                'bk_biz_id', 'collector_json', 'config_json', 'config_version', 'description_md',
                'is_support_remote', 'label', 'logo', 'metric_json',
                'plugin_display_name', 'plugin_id', 'plugin_type', 'related_conf_count', 'signature', 'version_log'
            ]
            plugin_obj = {k: v for k, v in data.items() if k in plugin_key}
            logger.debug(f"Filtered plugin object: {plugin_obj}")

            plugin_obj["config_version_old"] = data["config_version"]
            plugin_obj["import_plugin_config"] = {
                "collector_json": data["collector_json"],
                "config_json": data["config_json"],
                "is_support_remote": data["is_support_remote"]
            }
            plugin_obj["import_plugin_metric_json"] = data["metric_json"]
            plugin_obj["label"] = "os"

            logger.info("Plugin imported successfully")
            return plugin_obj

        except Exception as e:
            logger.error(f"Error occurred: {e}", exc_info=True)
            self.exceptions.add("import_plugin")
            return {}

    def create_plugin(self, plugin_obj):
        try:
            if not plugin_obj:
                return {}
            url = f'{self.config.monitor_url}/rest/v2/collector_plugin/'
            response = self.session.post(url, verify=False, json=plugin_obj)
            result = response.json()['data']
            return result
        except Exception as e:
            logger.error(f"Error occurred: {e}", exc_info=True)
            self.exceptions.add("create_plugin")
            return {}

    def register_plugin(self, plugin_obj):
        try:
            if not plugin_obj:
                return ""
            url = f'{self.config.monitor_url}/rest/v2/register_plugin/'
            params = {
                "bk_biz_id": 2,
                "config_version": plugin_obj["config_version"],
                "info_version": plugin_obj["info_version"],
                "plugin_id": plugin_obj["plugin_id"],
            }
            response = self.session.post(url, verify=False, json=params)
            result = response.json()["data"]
            if "task_id" not in result:
                return result["token"]
            else:
                return result["task_id"]
        except Exception as e:
            logger.error(f"Error occurred: {e}", exc_info=True)
            self.exceptions.add("register_plugin")
            return ""

    def query_async_task_result(self, task_id):
        try:
            if not task_id:
                return []
            url = f"{self.config.monitor_url}/rest/v2/commons/query_async_task_result/?task_id={task_id}&bk_biz_id=2"
            is_completed = False
            token = []
            while not is_completed:
                try:
                    response = self.session.get(url, verify=False)
                    result = response.json()["data"]
                    is_completed = result["is_completed"]
                    if not is_completed:
                        time.sleep(1)
                    else:
                        token = result["data"]["token"]
                except Exception as e:
                    logger.error(f"Error occurred: {e}", exc_info=True)
                    return []
            return token
        except Exception as e:
            logger.error(f"Error occurred: {e}", exc_info=True)
            self.exceptions.add("query_async_task_result")
            return []

    def plugin_release(self, obj, token):
        try:
            if not obj:
                return False
            url = f"{self.config.monitor_url}/rest/v2/collector_plugin/{obj['plugin_id']}/release/"
            plugin_obj = {
                "bk_biz_id": 2,
                "config_version": obj["config_version"],
                "info_version": obj["info_version"],
                "token": token
            }
            response = self.session.post(url, verify=False, json=plugin_obj)
            result = response.json()
            return result["result"]
        except Exception as e:
            logger.error(f"Error occurred: {e}", exc_info=True)
            self.exceptions.add("plugin_release")
            return False

    def finalize(self):
        if self.error_occurred:
            logger.error("Monitor initialization encountered errors in the following steps:")
            for step in self.exceptions:
                logger.error(step)
            print("\033[31m==================Monitor initialization encountered errors==================\033[0m")
        else:
            logger.info("==================Monitor initialization completed==================")
            print("\033[32m==================Monitor initialization completed==================\033[0m")
