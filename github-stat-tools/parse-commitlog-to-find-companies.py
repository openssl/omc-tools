import sys
import re

# Script created for OpenSSL commit parsing so we can get an
# idea how many commits come from paid OpenSSL resources,
# companies paying people to work on OpenSSL (which we know
# because they have a CCLA) and other/individuals.

# git log --since="6 Jul, 2022" --before="7 Jul, 2023" > log.txt

# Committers who are not OSS
committers = {"david.von.oheimb@siemens.com",
              "matthias.st.pierre@ncp-e.com",
              "shane.lontis@oracle.com",
              "bernd.edlinger@hotmail.de",
              "tshort@akamai.com",
              "beldmit@gmail.com",
              "kurt@roeckx.be",
              "nic.tuv@gmail.com",
              "kaishen.yy@antfin.com",
              "openssl-users@dukhovni.org",
              "tom.cosgrove@arm.com"}
# We know who is in OSS because they commmit with openssl.org
# email address, and no one not paid by OSS does that in the data
# sample.

cla= {}
with open("../data/cladb.txt") as clafile:
    for line in clafile:
        if not line.startswith('#'):
            m = re.findall(r'^([^\s]+)\s+(\S)',line.strip())
            if (len(m) >0):
                cla[m[0][0].lower()] = m[0][1]

commitsfound = 0
commitsccla = 0
commitscommitters = 0
commitscommittersccla = 0
commitsnotfound = 0
commitsoss = 0
committrivial = 0

with open('log.txt', 'r') as file:
    text = file.read()

pattern = r"commit ([\w]+)\nAuthor: (.*?)\n([\s\S]*?)(?=^commit|\Z)"
#pattern = r"commit ([\w]+)\nAuthor: (.*?)\n((?:(?!commit).)*)"
matches = re.findall(pattern, text, flags=re.MULTILINE)

for match in matches:
    cid = match[0]
    author = match[1].strip()
    rest_of_block = match[2].strip()
    cla_trivial = re.search(r"cla:\s*trivial", rest_of_block.casefold())

    if "dependabot" in author:
        continue
    m = re.findall(r'<([^>]+)>',author)
    if (len(m)>0):
        if "openssl.org" in m[0].lower():
            commitsoss += 1
            commitscommitters+= 1
            commitsfound += 1
#            print ("OSS", fields[1])
        elif not m[0].lower() in cla:
            if cla_trivial:
                committrivial += 1
            else:
                commitsnotfound += 1
                print ("Not Found", cid, author,rest_of_block)
        else:
            commitsfound += 1
            if m[0].lower() in committers:
                commitscommitters+= 1
            if ("C" in cla[m[0].lower()]):
                if m[0].lower() in committers:
                    commitscommittersccla += 1
                else:
                    commitsccla += 1

print (f"Found {commitsfound+commitsnotfound} commits")
print ("Paste below into https://sankeymatic.com/build/\n")
print (f"Commits by Committers [{commitscommitters}] All Commits")
print (f"Commits by Non-Committers [{commitsfound-commitscommitters+commitsnotfound}] All Commits")
print (f"OSS Paid Commits [{commitsoss}] Commits by Committers")
print (f"Company Paid Commits [{commitscommittersccla}] Commits by Committers")
print (f"Individuals Commits [{commitscommitters-commitsoss-commitscommittersccla}] Commits by Committers")
print (f"Company Paid Commits [{commitsccla}] Commits by Non-Committers")
print (f"Individuals Commits [{commitsfound-commitscommitters-commitsccla}] Commits by Non-Committers")
if (commitsnotfound > 0):
    print (f"Unknown [{commitsnotfound}] Non-Committers")
print (f"Trivial Commits [{committrivial}] All Commits")

# Use sankeyMATIC
#
# Committers [1477] Commits
# Non-Committers [443] Commits
# OSS Paid [1168] Committers
# Companies [263] Committers
# Individual [46] Committers
# Companies [154] Non-Committers
# Individual [190] Non-Committers
# Unknown/Trivial [99] Non-Committers

