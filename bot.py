# -*- coding: utf-8 -*-
import os
from subprocess import Popen, PIPE, STDOUT
from wikifetch import WikiFetch
from argparse import ArgumentParser


parser = ArgumentParser(description='Process law-source files to wiki-source.')
parser.add_argument('-t', '--title', help='Wiki titles to fetch by the bot', dest='titles', action='append')
# parser.add_argument('-o', '--output', help='Output the final format', dest='output', action='store_true')
args = parser.parse_args()

wiki = WikiFetch('config.ini')
#wiki.connect()
titles = args.titles or wiki.category_titles(wiki.config('wiki', 'category'))

for title in titles:
    src_art = title + wiki.config('wiki', 'source_suffix')
    dst_art = title
    req = wiki.text(src_art)
    src_text = req.text
    p1 = Popen('./syntax-wiki.pl', stdout=PIPE, stdin=PIPE, stderr=STDOUT, shell=True)
    w_syntax = p1.communicate(input=src_text.encode('utf8'))[0]
    p2 = Popen('./format-wiki2.pl', stdout=PIPE, stdin=PIPE, stderr=STDOUT, shell=True)
    w_format = p2.communicate(input=w_syntax)[0]
    print(w_format.decode('utf8'))

