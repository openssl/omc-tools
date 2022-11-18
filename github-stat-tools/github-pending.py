#! /usr/bin/env python3

import sys
import subprocess
import requests
import json
import pprint
from datetime import datetime, timezone
from optparse import OptionParser

dryrun = False
debug = False
now = datetime.now(timezone.utc)

### Helpers

def search(host, q, headers):
    search_urls = {
        'github.com': 'https://api.github.com/search/issues'
    }

    url = search_urls[host] + '?q=' + '%20'.join(q)
    if debug: print(f'DEBUG[search]: {url=}', file=sys.stderr)
    res = requests.get(url, headers=headers).json()
    if debug: print(f'DEBUG[search]: {res=}', file=sys.stderr)
    return res

### Result backends

# Zabbix doesn't support much in terms of indexable <key:value>s alongside
# the metric, like Prometheus or Loki do.  Instead, we feed all of them as
# separate values in one input, with the hope that they all get the same
# time stamp
def backend_zabbix(host, basekey, values):
    zabbix_command = ['zabbix_sender', '-z', 'm.openssl.org', '-i', '-']
    zabbix_lines = [f'{host} {basekey}.{k} {v}' for k,v in values.items()]
    zabbix_input = "\n".join(zabbix_lines) + "\n"
    if debug or dryrun:
        prefix = 'DEBUG[backend_zabbix]: ' if debug else ''
        intro = 'would run this command:' if dryrun else 'running this command:'
        for l in [ intro,
                   '',
                   ' '.join([ *zabbix_command, '<<_____']),
                   *zabbix_lines,
                   '_____',
                   '' ]:
            print(f'{prefix}{l}', file=sys.stderr)

    if not dryrun:
        subprocess.run(zabbix_command, input=zabbix_input, text=True);

# Echoing is done in a way that's similar to Prometheus / Loki input.
# The "metric" value is treated specially, so it becomes the actual sole
# value, while the rest of the values are indexing label values.
def backend_echo(host, basekey, values):
    t = now.isoformat()
    s = f'{basekey}' + '{' + ', '.join(
        [ f'host="{host}"',
          *( f'{k}="{v}"' for k,v in values.items() if k != 'metric' ) ]
    ) + '}'
    print(f'{t}: {s} {values["metric"]}')

### Main

# defaults
host = 'github.com'
backend = 'echo'
# blank token is fine, but you may hit API rate limiting
git_token = ''

# parse options
parser = OptionParser()

parser.add_option('-b', '--backend',
                  help='the output backend.  Accepted choices: echo, zabbix',
                  dest='backend')
parser.add_option('--host',
                  help='the github host to check',
                  dest='host')
parser.add_option('-t', '--token',
                  help='file containing github authentication token for example "18asdjada..."',
                  dest='token')
parser.add_option('-d', '--debug', action='store_true', help='be noisy',
                  dest='debug')
parser.add_option('-n', '--dry-run', action='store_true', help='be noisy',
                  dest='dryrun')

(options, args) = parser.parse_args()

if options.backend:
    backend = options.backend
if options.host:
    host = options.host
if options.token:
    fp = open(options.token, 'r')
    git_token = fp.readline().strip('\n')
debug = options.debug
dryrun = options.dryrun

# info databases
backends = {
    'zabbix': backend_zabbix,
    'echo': backend_echo,
}

headers = {
    'Accept': 'application/vnd.github+json',
    'Authorization': git_token,
}

# Do stuff
open_issues = search(
    host, [ 'repo:openssl/openssl', 'type:issue', 'state:open' ], headers
)
open_pulls = search(
    host, [ 'repo:openssl/openssl', 'type:pr', 'state:open' ], headers
)

backends[backend](host, 'openssl.issues.gap',
                  { 'repo': 'openssl/openssl',
                    'metric': open_issues['total_count'] })
backends[backend](host, 'openssl.prs.gap',
                  { 'repo': 'openssl/openssl',
                    'metric': open_pulls['total_count'] })
