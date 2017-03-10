import json
import sys

data = json.load(sys.stdin)

supported = ["Ada", "Assembly", "C#", "Cobol", "FORTRAN", "Java", "JOVIAL", "Delphi", "Pascal", "Python", "VHDL", "Visual"]
weblist = ["CSS", "HTML", "PHP", "JavaScript"]
out = []
hasWeb = False
hasC = False

lang = sorted(data.items(), key=lambda x: x[1], reverse=True)[0][0]

if lang in supported:
    print lang
elif lang == "C" or lang == "C++":
    print "C++"
elif lang in weblist:
    print "Web"
else:
    print ""
