import sys
import json
import csv
from lxml import html


# read in project names
projects = []
with open(sys.argv[1]) as projectfile:
    projects = projectfile.read().splitlines() 


with open("csv.csv", "w") as csvfile:
    fieldnames = ["name", "owner", "url", "version", "creation date", "stars", "watches", "forks", \
    "contributors", "languages", "open issues", "closed issues", "last year commit #", "description", "readme", \
    "Propagation Cost", "Architecture Type", "Core Size", "Central Size", "Lines of Code (LOC)", "Comment/Code Ratio", \
    "Classes", "Files", "Median LOC per File", "Files > 200 LOC", "Functions > 200 LOC", "Median CBO", \
    "CBO > 8", "Median WMC", "WMC > 12", "Median WMC-McCabe", "WMC-McCabe > 100", "Median RFC", "RFC > 30"]
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    
    for proj in projects:
        p = proj.split('/')[1]
        data = {}
        try:
            with open("data/" + p + "/fromGithub.json") as jsonfile:
                data = json.load(jsonfile)
            output = {}
            output["name"] = data["repo"]["name"]
            output["owner"] = data["repo"]["owner"]["login"]
            output["version"] = data["repo"]["pushed_at"]
            output["stars"] = data["repo"]["stargazers_count"]
            output["watches"] = data["repo"]["subscribers_count"]
            output["forks"] = data["repo"]["forks_count"]
            output["contributors"] = data["contributors_count"]
            output["open issues"] = data["repo"]["open_issues_count"]
            output["closed issues"] = data["closed_issues_count"]
            output["creation date"] = data["repo"]["created_at"]
            output["description"] = data["repo"]["description"] 
            # get the most-used language
            output["languages"] = sorted(data["languages"].items(), key=lambda x: x[1], reverse=True)[0][0]
            output["last year commit #"] = sum([x["total"] for x in data["commit_activity"]])
            output["url"] = "https://github.com/" + output["owner"] + "/" + output["name"]

            paragraphs = data["readme"].split("\n\n")
            for para in paragraphs:
                par = para.strip()
                if par[0] not in "|<>" and par[-1] == '.':
                    output["readme"] = par
                    break
        except IOError as e:
            print "no JSON file for: " + p
            continue

        # Understand metrics
        try:
            with open("data/" + p + "/index.html") as htmlfile:
                # grab <head><script>
                block = html.tostring(html.parse(htmlfile).getroot()[0][0])
                metrics = json.loads(block.split("metrics=")[1].split(';')[0])
                for m in metrics:
                    if m['name'] != "Project Name":
                        output[m['name']] = m['value']
        except IOError as e:
            print "no metrics file for: " + p
            continue

        try:
            writer.writerow(output)
        except UnicodeEncodeError as e:
            print p, e


