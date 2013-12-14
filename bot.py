#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#import os
import re
from subprocess import Popen, PIPE, STDOUT
from wikiconnect import WikiConnect
from argparse import ArgumentParser


parser = ArgumentParser(description='Process law-source files to wiki-source.')
parser.add_argument('-t', '--title', help='Wiki titles to fetch by the bot', dest='titles', action='append')
parser.add_argument('-d', '--dry-run', help='Run the process with no commit', dest='dry_run', action='store_true')
parser.add_argument('-o', '--output', help='Output the final format', dest='output', action='store_true')
parser.add_argument('-O', '--outpot-to', help='Output the final format to file', dest='output_to')
args = parser.parse_args()

if args.dry_run is True:
    print('Will dry-run now, no changes will be uploaded to wiki-source.')

category = 'בוט חוקים'
source_suffix = '/מקור'

wiki = WikiConnect('config.ini')
titles = args.titles or wiki.category_titles(category)
wiki.connect()

for title in titles:
    regex = re.search('^(.*)/מקור$', title)
    src_title = title + source_suffix if regex is None else title
    dst_title = title if regex is None else regex.group(1)

    # dst_revisions = wiki.revisions(dst_art)
    # dst_page_id, dst_page = dst_revisions['pages'].popitem()
    # dst_revision = dst_page['revisions'][0]

    src_revisions = wiki.revisions(src_title)
    src_page_id, src_page = src_revisions['pages'].popitem()
    src_revision = src_page['revisions'][0]

    dst_comment = '[' + str(src_revision['revid']) + ']'
    if src_revision['comment'] is not '':
        dst_comment += ' ' + src_revision['comment']

    # print(dst_comment)

    src_text = src_revision['*']

    p1 = Popen('./syntax-wiki.pl', stdout=PIPE, stdin=PIPE, stderr=STDOUT, shell=True)
    w_syntax = p1.communicate(input=src_text.encode('utf8'))[0]
    p2 = Popen('./format-wiki2.pl', stdout=PIPE, stdin=PIPE, stderr=STDOUT, shell=True)
    w_format = p2.communicate(input=w_syntax)[0]
    if args.dry_run is False:
        result = wiki.push(dst_title, w_format.decode('utf8'), dst_comment)
        print(result)
    if args.output_to is not None:
        print('Output to file is not yet implemented... sorry!')
    if args.output is True:
        print(w_format.decode('utf8'))


