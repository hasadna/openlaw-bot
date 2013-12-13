# -*- coding: utf-8 -*-
import requests
from wikiconnect import WikiConnect

class WikiFetch(WikiConnect):
    def __init__(self, config_file):
        WikiConnect.__init__(self, config_file)

    def query(self, params):
        payload = {
            'action': 'query',
            'format': 'json',
        }
        for index, value in params:
            payload[index] = value
        result = self.request('api', payload, 'get')

    def category_members(self, category):
        category = category or self.config('wiki', 'category')
        params = {
            'list': 'categorymembers',
            'cmtitle': 'category:' + category,
            'cmsort': 'timestamp',
            'cmdir': 'desc',
        }
        result = self.query(params=params)


