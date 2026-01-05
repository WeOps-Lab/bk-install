import logging
import logging.config
import os

LOG_DIR = 'logs'
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR)

LOGGING_CONFIG = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'standard': {
            'format': '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        },
    },
    'handlers': {
        'main_file': {
            'level': 'INFO',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.path.join(LOG_DIR, 'init_weops_service.log'),
            'maxBytes': 0,
            'backupCount': 2,
            'formatter': 'standard',
        },
        'utils_file': {
            'level': 'INFO',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.path.join(LOG_DIR, 'uwsgi_utils.log'),
            'maxBytes': 0,
            'backupCount': 2,
            'formatter': 'standard',
        },
        'error_file': {
            'level': 'ERROR',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.path.join(LOG_DIR, 'error.log'),
            'maxBytes': 0,
            'backupCount': 2,
            'formatter': 'standard',
        },
        'debug_file': {
            'level': 'DEBUG',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.path.join(LOG_DIR, 'debug.log'),
            'maxBytes': 0,
            'backupCount': 2,
            'formatter': 'standard',
        },
    },
    'loggers': {
        'cmdb': {
            'handlers': ['main_file', 'error_file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'monitor': {
            'handlers': ['main_file', 'error_file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'itsm': {
            'handlers': ['main_file', 'error_file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'login': {
            'handlers': ['main_file', 'error_file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'main': {
            'handlers': ['main_file', 'error_file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'utils': {
            'handlers': ['utils_file', 'error_file', 'debug_file'],
            'level': 'DEBUG',
            'propagate': False,
        },
    }
}

logging.config.dictConfig(LOGGING_CONFIG)
