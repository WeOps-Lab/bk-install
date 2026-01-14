import logging
from utils import safe_request

logger = logging.getLogger('login')

class ModifyLoginSession:
    csrf_urls = [
        '/o/weops_saas/index/biz/list/',
        '/o/bk_itsm/',
        '/o/bk_monitorv3/',
        # 添加更多 URL
    ]

    def __init__(self, session, config):
        self.session = session
        self.config = config
        self.bk_paas_path = config.paas_url.strip("/")
        self.cmdb_url = config.cmdb_url.strip("/")
        self.username = config.bk_user
        self.password = config.bk_password
        self.session.headers.update({'referer': self.bk_paas_path})
        self.csrfmap = {}
        self.exceptions = set()

        if not self.login():
            logger.error("Login failed during initialization, exiting program")
            print("Login failed, please check 'init_weops_service.log' for details")
            exit(1)

        self.init_csrf()
        self.finalize()

    def get_csrftoken(self, url, token_name):
        try:
            response = safe_request(self.session, 'get', url, 'get_csrftoken', self.exceptions)
            if response and hasattr(response, 'cookies'):
                logger.info(f"Response cookies: {response.cookies}")
                if token_name in response.cookies:
                    return response.cookies[token_name]
                else:
                    logger.error(f"Cookie does not contain {token_name}")
            else:
                logger.error("Response does not contain cookies")
        except Exception as e:
            logger.error(f"Error executing get_csrftoken method: {e}")
            self.exceptions.add("get_csrftoken")
        return None

    def init_csrf(self):
        self.session.headers.update({'AUTH_APP': 'WEOPS'})
        urls = [f'{self.config.paas_url}{path}' for path in self.csrf_urls]
        for url in urls:
            try:
                response = self.session.get(url)
                logging.info(f'Requested {url} for CSRF tokens. Received cookies: {response.cookies}')
            except Exception as e:
                logging.error(f'Error during CSRF token retrieval from {url}: {e}')
                self.exceptions.add("init_csrf")

    def login(self, login_url=None):
        logger.info("==================Starting Modify Login Session==================")
        print("==================Starting Modify Login Session==================")
        login_url = login_url or self.bk_paas_path + '/login/?c_url=/'
        login_csrftoken = self.get_csrftoken(login_url, 'bklogin_csrftoken')
        if not login_csrftoken:
            logger.error("Failed to get CSRF Token")
            return False

        logger.info(f"Login URL: {login_url}")
        logger.info(f"CSRF Token: {login_csrftoken}")

        login_form = {
            'csrfmiddlewaretoken': login_csrftoken,
            'username': self.username,
            'password': self.password,
            'next': '',
            'app_id': ''
        }
        login_header = {
            "connection": "keep-alive",
            'Cache-Control': 'max-age=0',
            'WEOPS-IGNORE-DECRYPT': 'true',
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
                          'Chrome/108.0.0.0 Safari/537.36 Edg/108.0.1462.54 ',
            'Accept': 'gzip, deflate'
        }

        logger.info(f"Login form data: {login_form}")

        try:
            resp = self.session.post(login_url, data=login_form, headers=login_header, verify=False)
            logger.info(f"Login response status code: {resp.status_code}")

            if resp.status_code == 200:
                cookies1 = resp.request.headers['Cookie'].split(';')
                logger.info(f"Cookies: {cookies1}")
                token = None
                for i in cookies1:
                    l = i.split("=")
                    if l[0].strip() == "bk_token":
                        token = l[1]
                if token:
                    logger.info(f"Login successful, bk_token: {token}")
                    self.session.cookies.set('bk_token', token)
                    return True
                else:
                    logger.error("Login response does not contain bk_token")
            else:
                logger.error(f"Login failed, status code: {resp.status_code}")
        except Exception as e:
            logger.error(f"Error executing login method: {e}")
            self.exceptions.add("login")

        return False

    def finalize(self):
        if self.exceptions:
            logger.error("Modify Login Session encountered errors in the following steps:")
            for step in self.exceptions:
                logger.error(step)
            print("\033[31m==================Modify Login Session encountered errors==================\033[0m")
        else:
            logger.info("==================Modify Login Session completed==================")
            print("\033[32m==================Modify Login Session completed==================\033[0m")
