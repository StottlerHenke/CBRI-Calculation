# Software-Architecture-Evaluation
This project contains scripts that use the Understand static analysis tool to calculate key metrics associated with technical debt for a list of GitHub repositories and compiles the results into a single file.

## Installation

1.	Download the repository. The location of the script files is referred to as `<current directory>`.
1.	Install Understand. Download Understand (https://scitools.com) and install to `<current directory>/scitools`.
  *	Alternately, install to a different location and change cloneAndAnalyze.sh to point to the correct locations of und and uperl (default relative path: scitools/bin/linux64/und, same for uperl).
1.	Run Understand. Run the Understand application and ensure licensing is working correctly. Drag and drop the file CoreMetrics_v1.10.upl into the main window of understand to install the core metrics plugin.

## To run the analysis script and compile the output
* `bash cloneAndAnalyze.sh <input file>` 
  * `<input file>` is a text file containing a list of projects in username/projectname form (matching https://github.com/username/projectname), one project per line.
    * E.g. example_projects.txt.
  * The script will:
    * Clone repositories into cloned_projects/. 
    * Analyze the code with Understand and put the results into created_dbs/.
    * Run the core metrics plugin on each cloned project and put those results (classMetrics.csv, fileMetrics.csv, index.html) into repository-specific folder in data/
      * E.g. data/WorldWindJava/
    * Collect repository details queried using the GitHub API.
      * E.g. data/WorldWindJava/fromGitHub.json
* `python csvConverter.py <input file>`
  * `<input file>` is the same form as used in cloneAndAnalyze.sh. It can be identical but it doesn't have to be (e.g. if you want to show only a subset of the cloned projects).
  * Results are compiled to the file output.csv.
