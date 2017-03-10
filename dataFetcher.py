import requests
import json
import sys
from datetime import datetime

path = sys.argv[1]
owner = path.split('/')[0]
project = path.split('/')[1]

data = {}
headers = {}
# if you want to use personal access tokens, do so like:
# headers = {'Authorization': "token <insert token here>"}

#data['cloned_date'] = datetime.now().strftime('%Y-%m-%dT%H:%M:%SZ')
x = requests.get("https://api.github.com/repos/" + path, headers=headers)
print x.headers


data['repo'] = requests.get("https://api.github.com/repos/" + path, headers=headers).json()
data['languages'] = requests.get("https://api.github.com/repos/" + path + "/languages", headers=headers).json()
data['commit_activity'] = requests.get("https://api.github.com/repos/" + path + "/stats/commit_activity", headers=headers).json()
headers['Accept'] = "application/vnd.github.v3.raw+json"
data['readme'] = requests.get("https://api.github.com/repos/" + path + "/readme", headers=headers).text
del headers['Accept']

# there can be a huge amount of closed issues
# so do some pre-processing here before saving to file 
issues = []
params = {'state': 'closed', 'per_page': '100'}     # to get all issues, change 'state' to 'all'
url = "https://api.github.com/repos/" + path + "/issues"
while True:
    r = requests.get(url, params=params, headers=headers)
    issues.extend(r.json())
    if r.links:                     # if there are pages
        if 'next' in r.links:       # we're not on the last page
            url = r.links['next']['url']
            continue
    break
count = 0
for i in issues:
    if i['state'] == 'closed':
        count += 1
data['closed_issues_count'] = count

# there can be a huge amount of contributors
# so do some pre-processing here before saving to file 
contributors = []
params = {'per_page': '100'}
url = "https://api.github.com/repos/" + path + "/stats/contributors"
while True:
    r = requests.get(url, params=params, headers=headers)
    contributors.extend(r.json())
    if r.links:                     # if there are pages
        if 'next' in r.links:       # we're not on the last page
            url = r.links['next']['url']
            continue
    break
data['contributors_count'] = len(contributors)


with open("data/" + project + "/fromGithub.json", 'w') as datafile:
    json.dump(data, datafile)
