import logging
from utils import safe_request

logger = logging.getLogger('itsm')

class ITSMInit:
    def __init__(self, session, config):
        self.session = session
        self.config = config
        self.exceptions = set()
        logger.info("ITSMInit initialized")

    def start(self):
        logger.info("==================Starting ITSM initialization==================")
        print("==================Starting ITSM initialization==================")

        self.init_api_quote_count()
        self.register_cmsi_msg()
        
        self.finalize()

    def init_api_quote_count(self):
        url = f"{self.config.paas_url}/o/bk_itsm/api/api_quote_count/init_api_quote_count/"
        response = safe_request(self.session, 'post', url, 'init_api_quote_count', self.exceptions)
        if response:
            logger.info("Successfully initialized ITSM API configuration")
            print("Successfully initialized ITSM API configuration")
        else:
            logger.error("Failed to initialize ITSM API configuration")
            print("Failed to initialize ITSM API configuration")

    def register_cmsi_msg(self):
        url = f"{self.config.paas_url}/o/bk_itsm/helper/register_cmsi_msg"
        response = safe_request(self.session, 'get', url, 'register_cmsi_msg', self.exceptions)
        if response:
            logger.info("Successfully registered CMSI message")
            print("Successfully registered CMSI message")
        else:
            logger.error("Failed to register CMSI message")
            print("Failed to register CMSI message")

    def finalize(self):
        if self.exceptions:
            logger.error("ITSM initialization encountered errors in the following steps:")
            for step in self.exceptions:
                logger.error(step)
            print("\033[31m==================ITSM initialization encountered errors==================\033[0m")
        else:
            logger.info("==================ITSM initialization completed==================")
            print("\033[32m==================ITSM initialization completed==================\033[0m")
