# -*- coding: utf-8 -*-
import requests
from configparser import ConfigParser


class WikiConnect:
    __config = {}
    __api_path = '/w/api.php'
    __index_path = '/w/index.php'
    __connection = False
    __cookie_jar = None
    __session = None
    __tokens = {}
    __error = {}

    def __init__(self, config_file):
        self.__config = ConfigParser()
        self.__config.read(config_file)
        self.__config.sections()
        self.__session = requests.Session()

    def connect(self):
        if self.connected():
            return True
        if 'login' not in self.__config:
            return False
        payload = {
            'action': 'login',
            'lgname': self.config('login', 'lgname'),
            'lgpassword': self.config('login', 'lgpassword'),
            'format': 'json',
        }
        url = 'https://' + self.config('login', 'host') + self.__api_path
        r1 = self.__session.post(url, data=payload)

        r1j = r1.json()['login']
        if r1j['result'] == 'Success':
            return self.__connected(r1.cookies)
        payload['lgtoken'] = r1j['token']
        r2 = self.__session.post(url, data=payload)
        r2j = r2.json()['login']
        if r2j['result'] == 'Success':
            self.__connection = True
            return True
        return False

    def token(self, token_type):
        if token_type not in self.__tokens:
            token_req = self.query({'action': 'tokens', 'type': token_type})
            self.__tokens[token_type] = token_req[token_type + 'token']
        return self.__tokens[token_type]

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

    def request(self, base='api', params={}, method='get'):
        if method is 'post':
            headers = {
                'content-type': 'application/x-www-form-urlencoded',
            }
            result = self.__session.post(self.url(base), data=params, headers=headers)
        else:
            result = self.__session.get(self.url(base), params=params)
        return result

    def query(self, params={}, method='get'):
        payload = {
            'action': 'query',
            'format': 'json',
        }
        for index in params:
            payload[index] = params[index]
        result = self.request('api', payload, method)
        json = result.json()
        if payload['action'] in json:
            return result.json()[payload['action']]
        else:
            self.__error = json['error']
            return {}

    def category_members(self, category):
        category = category or self.config('wiki', 'category')
        params = {
            'list': 'categorymembers',
            'cmtitle': 'category:' + category,
            'cmsort': 'timestamp',
            'cmdir': 'desc',
        }
        return self.query(params=params)

    def category_titles(self, category):
        cat_json = self.category_members(category)
        category_members = cat_json['categorymembers']
        titles = []
        for article in category_members:
            titles.append(article['title'])
        return titles

    def text(self, title):
        payload = {
            'action': 'raw',
            'title': title,
        }
        result = self.request('index', payload, 'get')
        return result

    def revisions(self, title):
        payload = {
            'prop': 'revisions',
            'titles': title,
            'rvprop': 'ids|timestamp|user|comment|content',
        }
        result = self.query(payload)
        return result

    def push(self, title, text, comment=''):
        text += '\n[[קטגוריה:בוט חוקים]]\n'
        payload = {
            'action': 'edit',
            'title': title,
            'section': 0,
            'text': text,
            'contentformat': 'text/x-wiki',
            'contentmodel': 'wikitext',
            'token': self.token('edit'),
            'summary': comment,
        }
        result = self.query(payload, 'post')
        return result

