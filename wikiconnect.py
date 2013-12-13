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
        login = self.__config['login']
        payload = {
              'action' : 'login',
              'lgname' : login['lgname'],
              'lgpassword' : login['lgpassword'],
              'format' : 'json',
        }
        url = 'https://' + login['host'] + self.__api_path
        r1 = requests.post(url, data=payload)

        r1j = r1.json()
        if r1j['login']['result'] == 'Success':
            return self.__connected(r1.cookies)
        payload['lgtoken'] = r1j['login']['token']
        r2 = requests.post(url, data=payload, cookies=r1.cookies)
        r2j = r2.json()
        if r2j['login']['result'] == 'Success':
            return self.__connected(r2.cookies)
        return False

    def __connected(self, cookie_jar):
        self.__cookie_jar = cookie_jar
        # TODO: add a check for sessionid to make sure cookie is useful
        self.__connection = True
        return self.connected()

    def connected(self):
        return self.__connection

    def config(self, section, key, value):
        if key is None:
            return self.__config
        if section is None:
            return self.__config[section] or None
        if value is None:
            return self.__config[section][value] or None
        self.__config[section][key] = value

    def url(self, path):
        url = 'https://' + self.config('login', 'host')
        if path is 'index':
            url += self.__index_path
        else:
            url += self.__api_path
        return url

    def request(self, base, params, method, use_cookie):
        params = params or {}
        method = method or 'get'
        base = base or 'api'
        use_cookie = use_cookie or False
        result = requests[method](self.url(base), params=params)
        return result


