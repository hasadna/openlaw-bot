# -*- coding: utf-8 -*-
import requests
from configparser import ConfigParser


class WikiConnect:
    __config = {}
    __api_path = '/w/api.php'
    __index_path = '/w/index.php'
    __connection = False
    __cookie_jar = None

    def __init__(self, config_file):
        self.__config = ConfigParser()
        self.__config.read(config_file)
        self.__config.sections()

    def connect(self):
        if 'login' not in self.__config:
            return None
        payload = {
            'action': 'login',
            'lgname': self.config('login', 'lgname'),
            'lgpassword': self.config('login', 'lgpassword'),
            'format': 'json',
        }
        url = 'https://' + self.config('login', 'host') + self.__api_path
        r1 = requests.post(url, data=payload)

        r1j = r1.json()['login']
        if r1j['result'] == 'Success':
            return self.__connected(r1.cookies)
        payload['lgtoken'] = r1j['token']
        r2 = requests.post(url, data=payload, cookies=r1.cookies)
        r2j = r2.json()['login']
        if r2j['result'] == 'Success':
            return self.__connected(r2.cookies)
        return False

    def __connected(self, cookie_jar):
        self.__cookie_jar = cookie_jar
        # TODO: add a check for sessionid to make sure cookie is useful
        self.__connection = True
        return self.connected()

    def connected(self):
        return self.__connection

    def config(self, section=None, key=None, value=None):
        if section is None:
            return self.__config
        if key is None:
            return self.__config[section] or None
        if value is None:
            return self.__config[section][key] or None
        self.__config[section][key] = value

    def url(self, path):
        url = 'https://' + self.config('login', 'host')
        if path is 'index':
            url += self.__index_path
        else:
            url += self.__api_path
        return url

    def request(self, base='api', params={}, method='get', use_cookie=False):
        if method == 'post':
            result = requests.post(self.url(base), params=params)
        else:
            result = requests.get(self.url(base), params=params)
        return result


