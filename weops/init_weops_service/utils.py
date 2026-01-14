import subprocess
import logging
import requests

logger = logging.getLogger('utils')

def get_env_variable(command):
    try:
        output = subprocess.check_output(command, shell=True, executable="/bin/bash", universal_newlines=True)
        return output.strip()
    except subprocess.CalledProcessError as e:
        logger.error(f"Error executing command '{command}': {e}")
        return None

def get_app_secret(db_user, db_password, db_host, app_code):
    app_secret_command = f'''
        docker exec mysql-client mysql -u{db_user} -p{db_password} -h {db_host} -N --database open_paas <<EOF
        select auth_token from paas_app where code="{app_code}";
EOF'''
    return get_env_variable(app_secret_command)

def safe_request(session, method, url, method_name, exceptions, **kwargs):
    try:
        logger.info(f"Request method_name: {method_name}, method: {method}, URL: {url}, Params: {kwargs}")
        if method == 'get':
            response = session.get(url, **kwargs)
        elif method == 'post':
            response = session.post(url, **kwargs)
        elif method == 'delete':
            response = session.delete(url, **kwargs)
        response.raise_for_status()
        logger.info(f"Response status code: {response.status_code}")
        logger.info(f"Response content: {response.text}")
        return response
    except requests.exceptions.HTTPError as e:
        logger.error(f"HTTP error occurred in {method_name}: {e}")
    except requests.exceptions.ConnectionError as e:
        logger.error(f"Connection error occurred in {method_name}: {e}")
    except requests.exceptions.Timeout as e:
        logger.error(f"Timeout error occurred in {method_name}: {e}")
    except requests.exceptions.RequestException as e:
        logger.error(f"Request error occurred in {method_name}: {e}")
    exceptions.add(method_name)
    return None
