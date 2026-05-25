#! /usr/bin/env python3
# requires python 3
#
# Do we have any open PR's that have label "Approval: done"
# that are over 24 hours without any other comments?
#
# get a token.... https://github.com/settings/tokens/new -- just repo is fine
# pop it in token.txt or you'll get a bad API limit
#
# note that we'd use pyGithub but we can't as it doesn't fully handle the timeline objects
# as of Feb 2020
#
# mark@openssl.org Feb 2020
import json
import os
from datetime import datetime
from datetime import timezone

import requests

DEBUG = os.getenv("DEBUG", "").lower() == "true"
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
COMMIT = os.getenv("COMMIT", "").lower() == "true"

API_URL = "https://api.github.com/repos/openssl/openssl"

HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "X-GitHub-Api-Version": "2022-11-28",
}


def convertdate(date):
    return datetime.strptime(date.replace("Z", "+0000"), "%Y-%m-%dT%H:%M:%S%z")


def getpullrequests():
    """
    Get all the open pull requests, filtering by approval: done label
    """
    url = f"{API_URL}/pulls?per_page=100&page=1"  # defaults to open
    res = requests.get(url, headers=HEADERS)
    repos = res.json()
    prs = []
    while "next" in res.links.keys():
        res = requests.get(res.links["next"]["url"], headers=HEADERS)
        repos.extend(res.json())

    # Let's filter by label if we're just looking to move things, we can parse
    # everything for statistics in another script

    try:
        for pr in repos:
            if "labels" in pr:
                for label in pr["labels"]:
                    if label["name"] == "approval: done":
                        prs.append(pr["number"])
    except Exception:
        print("failed", repos["message"])
    return prs


def movelabeldonetoready(issue):
    """
    Change the labels on an issue from approval: done to approval: ready to merge
    """
    url = f"{API_URL}/issues/{issue}/labels/approval:%20done"
    res = requests.delete(url, headers=HEADERS)
    if not res.ok:
        print("Error removing label", res.status_code, res.content)
        return
    url = f"{API_URL}/issues/{issue}/labels"
    newlabel = {"labels": ["approval: ready to merge"]}
    res = requests.post(url, data=json.dumps(newlabel), headers=HEADERS)
    if not res.ok:
        print("Error adding label", res.status_code, res.content)
        return
    newcomment = {"body": "This pull request is ready to merge"}
    url = f"{API_URL}/issues/{issue}/comments"
    res = requests.post(url, data=json.dumps(newcomment), headers=HEADERS)
    if res.status_code != 201:
        print("Error adding comment", res.status_code, res.content)
        return


def addcomment(issue, text):
    """
    Add a comment to PR
    """
    newcomment = {"body": text}
    url = f"{API_URL}/issues/{issue}/comments"
    res = requests.post(url, data=json.dumps(newcomment), headers=HEADERS)
    if res.status_code != 201:
        print("Error adding comment", res.status_code, res.content)


def checkpr(pr):
    """
    Check through an issue and see if it's a candidate for moving
    """
    url = f"{API_URL}/issues/{pr}/timeline?per_page=100&page=1"
    res = requests.get(url, headers=HEADERS)
    repos = res.json()
    while "next" in res.links.keys():
        res = requests.get(res.links["next"]["url"], headers=HEADERS)
        repos.extend(res.json())

    comments = []
    opensslmachinecomments = []
    approvallabel = {}
    sha = ""

    for event in repos:
        try:
            if event["event"] == "commented":
                if "openssl-machine" in event["actor"]["login"]:
                    opensslmachinecomments.append(convertdate(event["updated_at"]))
                else:
                    comments.append(convertdate(event["updated_at"]))
                if DEBUG:
                    print("DEBUG: commented at ", convertdate(event["updated_at"]))
            if event["event"] == "committed":
                sha = event["sha"]
                comments.append(convertdate(event["author"]["date"]))
                if DEBUG:
                    print("DEBUG: created at ", convertdate(event["author"]["date"]))
            elif event["event"] == "labeled":
                if DEBUG:
                    print("DEBUG: labelled with ", event["label"]["name"], "at", convertdate(event["created_at"]))
                approvallabel[event["label"]["name"]] = convertdate(event["created_at"])
            elif event["event"] == "unlabeled":
                if DEBUG:
                    print("DEBUG: unlabelled with ", event["label"]["name"], "at", convertdate(event["created_at"]))
                # have to do this for if labels got renamed in the middle
                if event["label"]["name"] in approvallabel:
                    del approvallabel[event["label"]["name"]]
            elif event["event"] == "reviewed" and event["state"] == "approved":
                if DEBUG:
                    print("DEBUG: approved at", convertdate(event["submitted_at"]))
        except Exception:
            return repos["message"]

    if "approval: ready to merge" in approvallabel:
        return "issue already has label approval: ready to merge"
    if "approval: done" not in approvallabel:
        return "issue did not get label approval: done"
    if "urgent" in approvallabel:
        labelurgent = approvallabel["urgent"]
        if labelurgent and max(comments) <= labelurgent:
            print("issue is urgent and has had no comments so needs a comment")
            if COMMIT:
                addcomment(pr, "@openssl/committers note this pull request has had the urgent label applied")

    approvedone = approvallabel["approval: done"]

    now = datetime.now(timezone.utc)
    hourssinceapproval = (now - approvedone).total_seconds() / 3600
    if DEBUG:
        print("Now: ", now)
        print("Last comment: ", max(comments))
        print("Approved since: ", approvedone)
        print("hours since approval", hourssinceapproval)

    if hourssinceapproval < 24:
        return f"not yet 24 hours since labelled approval:done hours: {hourssinceapproval}"

    if max(comments) > approvedone:
        if len(opensslmachinecomments) and (max(opensslmachinecomments) > approvedone):
            return "issue had comments after approval but we have already added a comment about this"
        if COMMIT:
            comment = (
                "24 hours has passed since 'approval: done' was set, but as this PR has been "
                " updated in that time the label 'approval: ready to merge' is not being "
                "automatically set.  Please review the updates and set the label manually."
            )
            addcomment(pr, comment)
        return "issue had comments after approval: done label was given, made a comment"

    # Final check before changing the label, did CI pass?

    url = f"{API_URL}/commits/{sha}/status"
    res = requests.get(url, headers=HEADERS)
    if not res.ok:
        return "PR has unknown CI status"
    ci = res.json()
    if ci["state"] != "success":
        if len(opensslmachinecomments) and (max(opensslmachinecomments) > approvedone):
            return "issue has CI failure but we have already added a comment about this"
        if COMMIT:
            comment = (
                "24 hours has passed since 'approval: done' was set, but this PR has failing CI tests. "
                "Once the tests pass it will get moved to 'approval: ready to merge' automatically,"
                "alternatively please review and set the label manually."
            )
            addcomment(pr, comment)
        return "PR has CI failure, made a comment"
    if COMMIT:
        print("Moving issue ", pr, " to approval: ready to merge")
        movelabeldonetoready(pr)
    else:
        print("set COMMIT env var to actually change the labels")
    return f"this issue was candidate to move to approval: ready to merge hours: {hourssinceapproval}"


def main():
    if DEBUG:
        print("Getting list of PRs")
    prs = getpullrequests()
    print(f"There were {len(prs)} open PRs with approval:done")
    for pr in prs:
        print(pr, checkpr(pr))


if __name__ == "__main__":
    main()
