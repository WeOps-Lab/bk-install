import logging
from utils import safe_request

logger = logging.getLogger('cmdb')

class CMDBInit:
    def __init__(self, session, config):
        self.session = session
        self.config = config
        self.exceptions = set()
        logger.info("CMDBInit initialized")

    def start(self):
        logger.info("==================Starting CMDB initialization==================")
        print("==================Starting CMDB initialization==================")
        classification_list = self.search_cmdb_obj_id()
        if not classification_list:
            logger.error("No classification objects found")
            self.exceptions.add("search_cmdb_obj_id")
            self.finalize()
            return
        
        logger.info(f"Classification list: {classification_list}")

        network_exists = False
        device_exists = False

        for item in classification_list:
            if not network_exists and item["bk_classification_id"] == "bk_network":
                network_exists = True
                self.handle_default_bk_network(item)
            elif not device_exists and item["bk_classification_id"] == "bk_device":
                device_exists = True

            if network_exists and device_exists:
                break

        if not network_exists:
            logger.info("Classification bk_network has been handled")
            print("Classification bk_network has been handled")

        if not device_exists:
            self.create_cmdb_device_classification()
        else:
            logger.info("Classification bk_device already exists")
            print("Classification bk_device already exists")



        if not self.association_type_exists("install_on"):
            logger.info("Association type install_on does not exist, creating...")
            print("Association type install_on does not exist, creating...")
            self.create_install_on_associationtype()
            if not self.association_type_exists("install_on"):
                logger.error("Failed to create association type install_on")
                print("Failed to create association type install_on")
                self.exceptions.add("create_install_on_associationtype")
            else:
                logger.info("Check association type install_on created successfully")
                print(f"Check association type install_on created successfully")
        else:
            logger.info("Association type install_on already exists")
            print("Association type install_on already exists")

        self.weops_cmdb_migration()

        self.finalize()

    def search_cmdb_obj_id(self):
        try:
            url = f"{self.config.cmdb_url}/api/v3/find/classificationobject"
            response = safe_request(self.session, 'post', url, 'search_cmdb_obj_id', self.exceptions)
            
            if response:
                response_data = response.json()
                if not response_data.get("result"):
                    error_message = response_data.get('message', 'Unknown error')
                    logger.error(f"Failed to query classification objects: {error_message}")
                    self.exceptions.add("search_cmdb_obj_id")
                    return []
                logger.info("Successfully queried classification objects")
                return response_data.get("data", [])
                
            else:
                logger.error("No valid response received")
                self.exceptions.add("search_cmdb_obj_id")
                return []
        except Exception as e:
            logger.error(f"Exception in search_cmdb_obj_id: {e}")
            self.exceptions.add("search_cmdb_obj_id")
            return []

    def handle_default_bk_network(self, item):
        try:
            models = [(obj["id"], obj["bk_obj_id"], obj["bk_obj_name"]) for obj in item["bk_objects"]]

            for model_id, bk_obj_id, bk_obj_name in models:
                associations = self.search_cmdb_device_objectassociation(bk_obj_id)
                for ass in associations:
                    self.delete_cmdb_device_objectassociation(ass["id"])

            for model_id, bk_obj_id, bk_obj_name in models:
                self.delete_cmdb_device_obj(model_id)

            self.delete_cmdb_device_classification(item["id"])
        except Exception as e:
            logger.error(f"Exception in handle_default_bk_network: {e}")
            self.exceptions.add("handle_default_bk_network")

    def search_cmdb_device_objectassociation(self, bk_obj_id):
        try:
            url = f"{self.config.cmdb_url}/api/v3/find/objectassociation"
            kwargs = {"condition": {"bk_obj_id": bk_obj_id}}
            response = safe_request(self.session, 'post', url, 'search_cmdb_device_objectassociation', self.exceptions, json=kwargs)
            
            if response:
                response_data = response.json()
                if not response_data.get('result'):
                    error_message = response_data.get('message', 'Unknown error')
                    logger.error(f"Failed to query object associations: {error_message}")
                    self.exceptions.add("search_cmdb_device_objectassociation")
                    return []
                logger.info("Successfully queried object associations")
                return response_data.get("data", [])
            else:
                logger.error("No valid response received")
                self.exceptions.add("search_cmdb_device_objectassociation")
                return []
        except Exception as e:
            logger.error(f"Exception in search_cmdb_device_objectassociation: {e}")
            self.exceptions.add("search_cmdb_device_objectassociation")
            return []

    def create_cmdb_device_classification(self):
        try:
            url = f"{self.config.cmdb_url}/api/v3/create/objectclassification"
            kwargs = {
                "bk_supplier_account": "0",
                "bk_classification_id": "bk_device",
                "bk_classification_name": "网络模型"
            }
            response = safe_request(self.session, 'post', url, 'create_cmdb_device_classification', self.exceptions, json=kwargs)
            if response:
                response_data = response.json()
                if not response_data.get("result"):
                    error_message = response_data.get('bk_error_msg', 'Unknown error')
                    logger.error(f"Failed to create classification bk_device: {error_message}")
                    self.exceptions.add("create_cmdb_device_classification")
                else:
                    logger.info("Successfully created classification bk_device")
            else:
                logger.error("No valid response received")
                self.exceptions.add("create_cmdb_device_classification")
        except Exception as e:
            logger.error(f"Exception in create_cmdb_device_classification: {e}")
            self.exceptions.add("create_cmdb_device_classification")

    def create_install_on_associationtype(self):
        try:
            url = f"{self.config.cmdb_url}/api/v3/create/associationtype"
            kwargs = {
               "bk_asst_id": "install_on",
               "bk_asst_name": "安装于",
               "src_des": "安装于",
               "dest_des": "安装",
               "direction": "src_to_dest"
            }
            response = safe_request(self.session, 'post', url, 'create_install_on_associationtype', self.exceptions, json=kwargs)
            if response:
                response_data = response.json()
                if not response_data.get("result"):
                    error_message = response_data.get('bk_error_msg', 'Unknown error')
                    logger.error(f"Failed to create association type install_on: {error_message}")
                    self.exceptions.add("create_install_on_associationtype")
                else:
                    logger.info("Successfully created association type install_on")
                    print(f"Successfully created association type install_on")
            else:
                logger.error("No valid response received")
                self.exceptions.add("create_install_on_associationtype")
        except Exception as e:
            logger.error(f"Exception in create_install_on_associationtype: {e}")
            self.exceptions.add("create_install_on_associationtype")

    def delete_cmdb_device_objectassociation(self, association_id):
        try:
            url = f"{self.config.cmdb_url}/api/v3/delete/objectassociation/{association_id}"
            response = safe_request(self.session, 'delete', url, 'delete_cmdb_device_objectassociation', self.exceptions)
            if response:
                response_data = response.json()
                if not response_data.get('result'):
                    error_message = response_data.get('message', 'Unknown error')
                    logger.error(f"Failed to delete object association {association_id}: {error_message}")
                    self.exceptions.add("delete_cmdb_device_objectassociation")
            else:
                logger.error("No valid response received")
                self.exceptions.add("delete_cmdb_device_objectassociation")
        except Exception as e:
            logger.error(f"Exception in delete_cmdb_device_objectassociation: {e}")
            self.exceptions.add("delete_cmdb_device_objectassociation")

    def delete_cmdb_device_obj(self, bk_obj_id):
        try:
            url = f"{self.config.cmdb_url}/api/v3/delete/object/{bk_obj_id}"
            response = safe_request(self.session, 'delete', url, 'delete_cmdb_device_obj', self.exceptions)
            if response:
                response_data = response.json()
                if not response_data.get('result'):
                    error_message = response_data.get('message', 'Unknown error')
                    logger.error(f"Failed to delete object {bk_obj_id}: {error_message}")
                    self.exceptions.add("delete_cmdb_device_obj")
            else:
                logger.error("No valid response received")
                self.exceptions.add("delete_cmdb_device_obj")
        except Exception as e:
            logger.error(f"Exception in delete_cmdb_device_obj: {e}")
            self.exceptions.add("delete_cmdb_device_obj")

    def delete_cmdb_device_classification(self, network_id):
        try:
            url = f"{self.config.cmdb_url}/api/v3/delete/objectclassification/{network_id}"
            response = safe_request(self.session, 'delete', url, 'delete_cmdb_device_classification', self.exceptions)
            if response:
                response_data = response.json()
                if not response_data.get("result"):
                    error_message = response_data.get('message', 'Unknown error')
                    logger.error(f"Failed to delete classification bk_network: {error_message}")
                    self.exceptions.add("delete_cmdb_device_classification")
                else:
                    logger.info("Successfully deleted classification bk_network")
            else:
                logger.error("No valid response received")
                self.exceptions.add("delete_cmdb_device_classification")
        except Exception as e:
            logger.error(f"Exception in delete_cmdb_device_classification: {e}")
            self.exceptions.add("delete_cmdb_device_classification")

    def association_type_exists(self, association_type_id):
        try:
            url = f"{self.config.cmdb_url}/api/v3/find/associationtype"
            kwargs = {"condition": {"bk_asst_id": association_type_id}}
            response = safe_request(self.session, 'post', url, 'association_type_exists', self.exceptions, json=kwargs)
            if response:
                response_data = response.json()
                logger.info(f"Query for association type {association_type_id} returned {response_data}")
                if response_data.get("result"):
                    info_list = response_data.get("data", {}).get("info", [])
                    if not info_list:  # 检查 info_list 是否为空
                        logger.info(f"No association types found for {association_type_id}")
                        return False
                    for item in info_list:
                        if item.get("bk_asst_id") == association_type_id:
                            return True
                return False
            else:
                return False
        except Exception as e:
            logger.error(f"Exception in association_type_exists: {e}")
            self.exceptions.add("association_type_exists")
            return False

    def weops_cmdb_migration(self):
        try:
            logger.info("Sending CMDB migration request to WeOps")
            print("Sending CMDB migration request to WeOps")
            migration_url = f"{self.config.paas_url}/o/weops_saas/resource/objects/migrate"
            response = safe_request(self.session, 'get', migration_url, 'weops_cmdb_migration', self.exceptions)
            if response:
                response_data = response.json()
                if not response_data.get("result"):
                    error_message = response_data.get('message', 'Unknown error')
                    logger.error(f"Failed to migrate CMDB: {error_message}")
                    print(f"Failed to migrate CMDB: {error_message}")
                    self.exceptions.add("weops_cmdb_migration")
                else:
                    logger.info("CMDB migration request sent successfully")
                    print("CMDB migration request sent successfully")
            else:
                logger.error("CMDB migration request failed")
                print("CMDB migration request failed")
                self.exceptions.add("weops_cmdb_migration")
        except Exception as e:
            logger.error(f"Exception in weops_cmdb_migration: {e}")
            self.exceptions.add("weops_cmdb_migration")

    def finalize(self):
        if self.exceptions:
            logger.error("CMDB initialization encountered errors in the following steps:")
            for step in self.exceptions:
                logger.error(step)
            print("\033[31m==================CMDB initialization encountered errors==================\033[0m")
        else:
            logger.info("==================CMDB initialization completed==================")
            print("\033[32m==================CMDB initialization completed==================\033[0m")
