#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#import os
import re
import logging
from subprocess import Popen, PIPE
from wikiconnect import WikiConnect
from argparse import ArgumentParser


parser = ArgumentParser(description='Process law-source files to wiki-source.')
parser.add_argument('titles', help='Wiki titles to fetch by the bot', nargs='*', metavar='TITLE', default=[])
parser.add_argument('-d', '--dry-run', help='Run the process with no commit', dest='dry_run', action='store_true')
parser.add_argument('-f', '--force', help='Force changing contents of destination', dest='force', action='store_true')
parser.add_argument('-l', '--log', help='Set a custom log file', dest='log', type=str)
# parser.add_argument('--log-level', help='Set a custom log level for console log', dest='log_level', type=str)
parser.add_argument('-o', '--output', help='Output the final format', dest='output', action='store_true')
parser.add_argument('-O', '--outpot-to', help='Output the final format to file', dest='output_to')
parser.add_argument('-s', '--silent', help='Do not output the log info to stdout', dest='silent', action='store_true')
parser.add_argument('-v', '--verbose', help='Output full process log to stdout', dest='verbose', action='store_true')
args = parser.parse_args()

logger = logging.getLogger('WikiBot')
logger.setLevel(logging.DEBUG)

log_file = args.log or '/var/log/bot.wiki.log'
file_logger = logging.FileHandler(log_file)
file_logger.setLevel(logging.INFO)
file_formatter = logging.Formatter('%(asctime)s %(name)-12s %(levelname)-8s %(message)s', '%Y-%m-%d %H:%M:%S')
file_logger.setFormatter(file_formatter)
logger.addHandler(file_logger)

if not args.silent:
    console_logger = logging.StreamHandler()
    console_logger.setLevel(logging.ERROR)
    if args.verbose is True:
        console_logger.setLevel(logging.DEBUG)
    console_formatter = logging.Formatter('%(name)-12s: %(levelname)-8s %(message)s')
    console_logger.setFormatter(console_formatter)
    logger.addHandler(console_logger)

if args.dry_run is True:
    logger.info('will dry-run, no changes will be uploaded to wiki-source')

category = 'בוט חוקים'
logger.debug('using category "%s"', category)
source_suffix = '/מקור'
logger.debug('using source suffix "%s"', source_suffix)

credential_file = 'config.ini'
wiki = WikiConnect(credential_file)
connected = wiki.connect()

if not args.titles:
    titles = wiki.category_titles(category)
    logger.debug('got titles from category on wiki site')
else:
    titles = args.titles
    logger.debug('got titles from input arguments')

for title in titles:
    regex = re.search('^(.*)/מקור$', title)
    src_title = title + source_suffix if not regex else title
    dst_title = title if not regex else regex.group(1)
    logger.info('working on title: %s', src_title)

    src_revisions = wiki.revisions(src_title)
    src_page_id, src_page = src_revisions['pages'].popitem()
    logger.debug('page id is %s', src_page_id)
    src_revision = src_page['revisions'][0]
    logger.info('working on revision id %s', src_revision['revid'])

    if not args.force:
        dst_revisions = wiki.revisions(dst_title)
        dst_page_id, dst_page = dst_revisions['pages'].popitem()
        dst_revision = dst_page['revisions'][0]
        logger.debug('destination comment: %s', dst_revision['comment'])
        dst_comment_regex = re.search('^\[(\d+)]', dst_revision['comment'])
        if not dst_comment_regex:
            logger.debug('destination has no revid in comment, going forward')
        else:
            dst_revid = dst_comment_regex.group(1)
            logger.debug('destination source revid: %s', dst_revid)
            if dst_revid == str(src_revision['revid']):
                logger.debug('destination revision id is %s', dst_revid)
                logger.info('current source is already in final format, skipping')
                continue
            else:
                logger.debug('destination source revid is different, going forward')
    else:
        logger.debug('skipping the check of destination source revid')

    dst_comment = '[' + str(src_revision['revid']) + ']'
    if src_revision['comment'] is not '':
        dst_comment += ' ' + src_revision['comment']
    src_text = src_revision['*']

    p1 = Popen('./syntax-wiki.pl', stdout=PIPE, stdin=PIPE, shell=True)
    w_syntax = p1.communicate(input=src_text.encode('utf8'))[0]
    logger.info('parsed text syntax with syntax-wiki.pl')
    p2 = Popen('./format-wiki2.pl', stdout=PIPE, stdin=PIPE, shell=True)
    w_format = p2.communicate(input=w_syntax)[0]
    logger.info('parsed text format with format-wiki2.pl')
    if args.dry_run is False:
        result = wiki.push(dst_title, w_format.decode('utf8'), dst_comment)
        logger.info('pushed final wikitext for page %s', dst_title)
        logger.debug('push comment is: %s', dst_comment)
        for key in result:
            logger.debug('key[%s]: %s', key, result[key])
    if args.output_to is not None:
        logger.info('Output to file is not yet implemented... sorry!')
    if args.output is True:
        print(w_format.decode('utf8'))


