# -*- coding: utf-8 -*-
from wikiconnect import WikiConnect


class WikiFetch(WikiConnect):
    def query(self, params={}):
        payload = {
            'action': 'query',
            'format': 'json',
        }
        for index in params:
            payload[index] = params[index]
        result = self.request('api', payload, 'get')
        return result.json()['query']

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


