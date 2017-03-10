The dataFetcher.py and script.sh scripts use the GitHub API to access repository information. 

By default, there is no authentication used in the requests. If you should choose to use Basic Authentication (https://developer.github.com/v3/auth/#basic-authentication), there are some comments in the code to help guide you, specifically using personal access tokens (OAuth tokens are similar).
