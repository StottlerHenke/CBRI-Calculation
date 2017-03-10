#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo $0 usage: script.sh projectfile
    exit 1
fi

input=$1

while IFS= read -r proj
do
    projName=${proj##*/}  #remove username

    # clone project to cloned_projects
    rm -rf "cloned_projects/"$projName
    git clone "git://github.com/"$proj".git" "cloned_projects/"$projName

    # get data from Github API
    mkdir -p "data/"$projName
    python dataFetcher.py $proj

    # get languages
    langs=$(curl -s https://api.github.com/repos/$proj/languages | python langExtractor.py)
    # if you want to use personal access tokens, do so like:
    # langs=$(curl -s -u "Authorization:<insert token here>" https://api.github.com/repos/$proj/languages | python langExtractor.py)


    if [ $langs != "" ]
    then
        # analyze cloned project and create db in created_dbs
        scitools/bin/linux64/und -quiet create -languages $langs add "cloned_projects/"$projName analyze "created_dbs/"$projName".udb"

        # calculate metrics for created db and output in metrics_output
        scitools/bin/linux64/uperl CoreMetrics_v1.10.pl -db "created_dbs/"$projName".udb" -createMetrics -outputDir "data/"$projName 
    else
        echo $projName " has no supported language"
    fi
done < "$input"

