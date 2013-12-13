# -*- coding: utf-8 -*-
import requests
import os
from subprocess import Popen, PIPE, STDOUT
from wikiconnect import WikiConnect

def get_text(title, base):
  url = base + '?action=raw&title=' + title
  req = requests.get(url)
  return req

cwd = os.getcwd()
category_name = u'בוט חוקים'
source_suffix = u'/מקור'
host = 'https://he.wikisource.org'
api_path = host + '/w/api.php'
index_path = host + '/w/index.php'



url = api_path + '?action=query&list=categorymembers&cmtitle=category:' + category_name + '&cmsort=timestamp&cmdir=desc&format=json'
req = requests.get(url)
cat_json = req.json()
categories = cat_json['query']['categorymembers']

for article in categories:
  src_art = article['title'] + source_suffix
  dst_art = article['title']

  req = get_text(src_art, index_path)
  text = req.text

  p1 = Popen('./syntax-wiki.pl', stdout=PIPE, stdin=PIPE, stderr=STDOUT, shell=True)
  syntax = p1.communicate(input=text.encode('utf8'))[0]

  p2 = Popen('./format-wiki2.pl', stdout=PIPE, stdin=PIPE, stderr=STDOUT, shell=True)
  format = p2._communicate(input=syntax)[0]
  print format

