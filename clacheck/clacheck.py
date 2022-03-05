#! /usr/bin/env python3
"""GitHub web hook.  Take PullRequest messages, and check the authors
for the CLA.

Look for <EDIT> comments for pointers on where to customize
"""

import cgi, cgitb
import json, urllib.request, urllib.parse, urllib.error, os, re, sys, http.client, hashlib, hmac

cgitb.enable()

env = os.environ
textplain = "Content-type: text/plain\n\n"
what = env.get('HTTP_X_GITHUB_EVENT', 'ping')
signatures = {
    'sha256': env.get('HTTP_X_HUB_SIGNATURE_256'),
}
From = re.compile("^From:.*<(.*)>")
Trivial = re.compile("^\s*CLA\s*:\s*TRIVIAL", re.IGNORECASE)
URLpattern = re.compile("https?://([^/]*)/(.*)")
SUCCESS = 'success'
FAILURE = 'failure'
data_location = env.get('DATA', '/var/cache/openssl/checkouts/data');
CLAFILE = os.path.join(data_location, 'cladb.txt')

CLA_LABEL = 'hold: cla required'

null_actions = (
        'assigned', 'unassigned', 'labeled', 'unlabeled', 'closed',
        'review_requested', 'review_request_removed',
        )

#<EDIT> target_url value
statusbody = """
{
    "state": "%(state)s",
    "target_url": "https://www.openssl.org/policies/cla.html",
    "description": "%(description)s",
    "context": "cla-check"
}
"""

# Tokens/secrets: one for authenticating github (incoming) and one for
# the authentication of this client (outgoing)
secrets_location=env.get('OSSL_SECRETS', '/var/www')
incoming_token = open(os.path.join(secrets_location,
                                   'clacheck-github-sig-secret.dat')).read().strip()
outgoing_token = open(os.path.join(secrets_location,
                                   'clacheck-webhook-token.dat')).read().strip()

def url_split(url):
    m = URLpattern.match(url)
    return (m.group(1), '/' + m.group(2))

def update_status(pr, state, description):
    d = { 'state': state, 'description': description }
    headers = {
            'Authorization': 'token ' + outgoing_token,
            'User-Agent': 'openssl-machine',
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
            }
    host,url = url_split(pr['_links']['statuses']['href'])
    print(textplain, "CLA check", state, description)
    conn = http.client.HTTPSConnection(host)
    conn.request('POST', url, statusbody % d, headers)
    conn.getresponse().read()
    host,url = url_split(pr['issue_url'])
    if state == SUCCESS:
        url = url + '/labels/' + urllib.parse.quote(CLA_LABEL)
        print('Delete', url)
        conn.request('DELETE', url, None, headers)
    elif state == FAILURE:
        url = url + '/labels'
        print('Add need-cla', url)
        conn.set_debuglevel(99)
        conn.request('POST', url, '[ "{}" ]'.format(CLA_LABEL), headers)
    reply = conn.getresponse().read()
    print("--\n", reply)

def have_cla(name):
    """Is |name| in the cladb?"""
    for line in open(CLAFILE):
        line = line.strip()
        if not line or line[0] == '#':
            continue
        n = line.split()
        if len(n) and n[0] == name.lower():
            return 1
    return 0

def process():
    payload = sys.stdin.read()

    digestname = 'sha256'
    digestmethod = hashlib.sha256
    incoming_signature = signatures[digestname]
    if incoming_signature:
        eval_signature = hmac.new(key=bytes(incoming_token, 'utf-8'),
                                  msg=bytes(payload, 'utf-8'),
                                  digestmod=digestmethod).hexdigest()
    if not (incoming_signature
            and incoming_signature == (digestname + '=' + eval_signature)):
        print("Status: 401\n", textplain, "Unauthorized")
        return

    if what != 'pull_request':
        print(textplain, "Request", what)
        return
    data = json.loads(payload)
    action = data.get('action', None)
    if action is None or action in null_actions:
        print(textplain, "No-op action", action)
        return
    pr = data.get('pull_request', None)
    if pr is None:
        print(textplain, "PR data missing")
        return
    patch_url = pr.get('patch_url', None)
    if patch_url is None:
        print(textplain, "patch_url missing")
        return
    missing = {}
    for line in urllib.request.urlopen(patch_url):
        m = Trivial.match(line)
        if m:
            update_status(pr, SUCCESS, "Trivial")
            return
        m = From.match(line)
        if m and not have_cla(m.group(1)):
            missing[m.group(1)] = 1
    if len(missing) == 0:
        update_status(pr, SUCCESS, 'CLA on file')
    else:
        update_status(pr, FAILURE, "CLA missing: " + str(list(missing.keys())))

process()
