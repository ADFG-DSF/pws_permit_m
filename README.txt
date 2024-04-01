# READ ME #

This repository contains R and SAS code to generate estimates for the PWS Shrimp Personal Use
Permit fishery.  To get the R scripts to run smoothly, a project folder should be established 
and a new R project should be started in RStudio.  To do so, open RStudio, click 'file', 
'new project', 'new directory', 'new project', and name the project accordingly (e.g. for me
I named it 'pws_shrimp').  Save the project to the project folder you just created. 
The R code should be run sequentially in the following order: 

1. permits_v1.2.R - this script imports the permit file "pwspmc_2023.csv". The permit file should
be saved as a single sheet .csv file which can be done using 'save as' in excel, and it should be 
saved to the R project folder.  The permit file is cleaned and prepped for merging into the harvest 
file in subsequent programs.  The output of this script is "permit_file_2023.csv".  

2. harvest_v1.3.R - This script imports the harvest file "pwshvc_2023.csv" and the location/statarea
file "location_statarea_updated_2023.csv". It cleans, edits, and merges the harvest file with the 
location/statarea master sheet.  It also has code to run basic data checks to ensure consistency 
in the location/area list and check both the harvest file for discrepancies.  You can use these checks
to help clean the harvest file at the beginning of the process.  The output from this sheet is
"shrimp_harvest_2023.csv" and "check_records_2023.xlsx". 

3. estimates_v1.4.R - This script imports "permit_file_2023.csv" and "shrimp_harvest_2023.csv" that were
generated in the previous two scripts.  Estimates are generated following the data analysis section 
in the op-plan.  Permit summaries, mailing summaries, response summaries, effort summaries, reported
harvest, and estimated expanded harvest are output to "shrimp_permits_2023.xlsx".  

All that should be needed to run these programs is to adjust the "year" variable at the beginning of 
each script and all of the required input data sets that follow the naming convention outlined above.

Version control: to ensure changes are traceable, any adjustments made to the R scripts should be saved
as a new version.  