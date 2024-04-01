*************************************************************************************;
*     There are 3 programs to analyze the salmon and shellfish permit databases:    *;
*         1. permits_v1.1.sas                                                       *;
*         2. harvest_v1.1.sas                                                       *;
*         3. estimates_v1.1.sas                                                     *;
*     This program reads and modifies data for harvest                              *;
*     This program is stored as h:\common\pat\permits\SHRIMP\2013\harvest.sas       *;
*	Each year the dataset: "LOCATION STATAREA.csv" should be copied ino the current	*;
*		year directory.																*;
*																					*;
*		In 2022, data import was changed to an .xlsx file rather than the original	*;
*	sas7bdat file.  Newyear added for dataset comparison purposes with 2021, can 	*;
*	be remobed in the future.														*;
*************************************************************************************;
dm editor "output;clear;log;clear" wedit;
proc datasets library = work kill; run;

%LET PROJECT = SHRIMP;
%LET DATA = pwshvc2021;
%LET YEAR = 2021;
%let newyear = 2022;
%LET PROGRAM = HARVEST;
*%LET SP = SHRIMP;

OPTIONS PAGENO=1 NODATE SYMBOLGEN LINESIZE=119 PAGESIZE=67 ;
OPTION VALIDVARNAME=UPCASE;
LIBNAME SASDATA BASE "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR";
LIBNAME SASDATA2 BASE "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR";

options symbolgen mprint;
options mprint sortsize=max ;
options nocenter;
**************************************************************************;
*                              HARVEST DATA                              *;
**************************************************************************;
/* in 2022 harvest data is imported from a .xlsx file rather than from the sasdata.data,
this is the original file, updated data is imported later. Note(1/23): you may have to 
go into the excel file and custom format the dates columns (harvdate, keydate)
as m/d/yyyy because SAS is having trouble recognizing it's text */

proc import
	datafile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear.\pwshvc_&newyear..xlsx"
	out = new_data
	dbms = xlsx
	replace;
run;

* harvdate was in an odd format so datepart() extracts mmddyy.  Use harvedate1
in subsequent code below;
proc freq data = new_data; tables harvdate; run;

/* For some reason there are a lot of empty cells being brought in, we want to check
them before deleting them so output to potential_empty.  Revise the harvdate to
a useable format in new_date.

Update: during the import of the revised data, the dates were converted to mmddyy10
so part of the next data step code won't be necessary (i.e. converting to datetime. */

data new_date potential_empty;
	set new_data;
	if hvrecid = '' then do; 
		output potential_empty;
		delete;
	end;
	if hvrecid ne '' then do; 
		harvdate1 = datepart(harvdate);
		format harvdate1 mmddyy10.;
		output new_date;
		drop harvdate;
	end;
run;

/*
data new_date potential_empty;
	set new_data;
	if hvrecid = '' then do; 
		output potential_empty;
		delete;
	end;
	if hvrecid ne '' then do; 
		harvdate1 = harvdate;
		format harvdate1 mmddyy10.;
		output new_date;
	end;
run;
*/

proc freq data = new_date; tables harvdate1; run;

* proc means can look for missing values by column;
* all values should be missing in this dataset;
proc means data = potential_empty nmiss n; run;
 
PROC PRINT DATA = SASDATA.&DATA (OBS=10);
     TITLE2 'HARVEST DATABASE';
     TITLE3 'FIRST 10 RECORDS';
RUN; 

PROC CONTENTS DATA = SASDATA.&DATA;
     TITLE3;
RUN;

proc freq data = sasdata.&data; tables nocatch; run;

* compare with previous year;
proc compare base = sasdata.&data (obs = 0) 
	compare = new_data (obs = 0);
run;

* harvdate1 as per comment above;
DATA HARVEST; 
	SET new_date (DROP =  YEAR KEYDATE MAILING KEYID);
     LOCATION = UPCASE(LOCATION);
     IF SOAKTIME = 0 THEN SOAKTIME = .;
     IF POTS = 0 THEN POTS = .;
	 IF SHRIMP GT 0 THEN NOCATCH = 0;
     IF NOCATCH = 1 THEN CATCH = 'N'; IF NOCATCH NE 1 THEN CATCH = 'Y';
     IF NOHRVRPT = 1 THEN HRVRPT = 'N'; IF NOHRVRPT NE 1 THEN HRVRPT = 'Y';
	 IF LOCATION = '' THEN LOCATION = "UNKNOWN";
     RENAME PERMITNO = PERMIT;
	 MONTH = MONTH(HARVDATE1);
	 DAY = DAY(HARVDATE1);
     DROP NOCATCH NOHRVRPT COMMENTS STAT_AREA;
RUN;

PROC PRINT DATA = HARVEST (OBS = 20); RUN;

* Try to clean up the location by removing leading and trailing spaces;
data cln_har;
	set harvest;
	location_1 = strip(location);
run;

data cln_har2;
	set cln_har;
	location = location_1;
	drop location_1;
run;

* Import Location statarea.csv to check against harvest locations;
* since this is a .csv, it only looks at the first 20 rows for getting the length
formats for location so include 'guessingrows = max' - guessingrows only works
for delimited files;
proc import 
 datafile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear.\xlocation_statarea_updated_&newyear..csv"
 out = loc_stat
 dbms = csv
 replace;
 guessingrows = max;
run;

proc print data = loc_stat (obs = 10); run;

proc sort data = cln_har2; by hvrecid; run;

* check harvest file for duplicate hvrecid;
data single dup;
	set cln_har2;
	by hvrecid;
	if first.hvrecid and last.hvrecid 
		then output single;
			else output dup;
run;

proc sort data = cln_har2 out = m_har; by location; run;
proc sort data = loc_stat; by location; run;

* are there duplicated rows?;
proc sort data = loc_stat 
	nodupkey out = loc_stat1; 
	by location statarea; 
run;

proc sort data = loc_stat1; by location; run;

/* 1/23 - Export cleaned and nonduplicated location file for next year. 

PROC EXPORT DATA = loc_stat1
    OUTFILE = 
	"O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\location_statarea_updated_&newyear..xlsx" 
	DBMS = XLSX REPLACE;
    SHEET = "location_statarea_updated_&newyear"; 
RUN;

*/

* Check for bad locations not in the master loc_stat file;
* try merge with loc_stat and locat_stat1 to see difference in 'both';
data both onlyloc onlyhar;
	merge m_har (in = m) loc_stat1 (in = s);
	by location;
	if m = 1 and s = 0 then output onlyhar;
	if m = 0 and s = 1 then output onlyloc;
	if m = 1 and s = 1 then output both;
run;

* if loc_stat1 works better change it to loc_stat for later use;
data loc_stat;
	set loc_stat1;
run;

data check_merge; 
	merge m_har loc_stat1;
	by location;
run;

proc freq data = onlyhar; 
	tables location / noprint out = check; 
run;

data check1;
	set check;
	if count gt 1;
run;

proc print data = check1; run;

/* This excel file should be sent to Jay Baumer/Brittany Blain after you have a 
	new harvest file at the beginning of the year.  The idea is for him to check
	these locations anc clean up the stat areas.  What he returns will be re-imported
	and used to modify the current year statareas. export to xlsx, bad location names,
	location with stat area, location errors where more than one obs occurred for 
	that type of location entered.  

This section can be skipped when the new 
	locations have been added and you are working on estimates. */

ods listing close;
ods excel file = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear\&newyear._locations.xlsx"
options (
	embed_titles_once = 'on'
	embedded_titles = 'on'
	flow = 'Tables'
	sheet_interval = 'proc'
	sheet_name = 'bad_loc');
proc print data = onlyhar noobs;
	title j = left 'Locations with no matchable statarea';
	var hvrecid permit harvdate location statarea;
run;

ods excel options (sheet_name = 'statarea');
proc print data = both noobs;
	title j = left 'Harvest records with locations that have a matchable statarea';
	var hvrecid permit harvdate location statarea;
run;

ods excel options (sheet_name = 'mult_err');
proc print data = check1 noobs;
	title j = left 'Locations with no statarea that occurred more than once';
	where count gt 1;
	var location count;
run;

ods excel close;
ods listing;

/* AMB EDITS - make sure sheet name matches below. This file is provided by AMB
  each year.  The following columns need to be renamed in this sheet to: "NEW_COMMENT",
	"NEW_POTS", "NEW_SHRIMP", "NEW_SOAKTIME". (i.e. from comment, pots, shrimp, soaktime.
	These are the new changed variables
	that have changes made and manipulated in the data step below. */

PROC IMPORT OUT = HARVEST_CHANGE 
 DATAFILE= "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear.\PWSHVC_&newyear._final.xlsx"  
	DBMS=xlsx REPLACE;
     *SHEET = "PWS";
RUN;

PROC SORT DATA = HARVEST_CHANGE; BY HVRECID; run;

PROC SORT DATA = HARVEST; BY HVRECID; run;

PROC CONTENTS data = harvest;
RUN;

proc compare base = harvest (obs = 0)
	compare = harvest_change (obs = 0);
run;

* This section of the code is to update the harvest file on record with Jay's
	changes that were imported previously;
DATA HARVEST_a onlyhar onlych; 
	MERGE HARVEST (in = h) HARVEST_CHANGE (in = c); 
	BY HVRECID;
	if h = 1 and c = 1 then output harvest_a;
	if h = 1 and c = 0 then output onlyhar;
	if h = 0 and c = 1 then output onlych;
RUN;

data harvest_1;
	set harvest_a;
	IF NEW_COMMENTs NE '' THEN DO; 
		COMMENTS = NEW_COMMENTs; END;
     IF NEW_POTS NE . THEN DO; 
		POTS = NEW_POTS; END;
     IF NEW_SHRIMP NE . THEN DO; 
		SHRIMP = NEW_SHRIMP; END;
     IF NEW_SOAKTIME NE . THEN DO; 
		SOAKTIME = NEW_SOAKTIME; END;
	 IF LOCATION = '' THEN LOCATION = "UNKNOWN";
	 LOCATION = UPCASE(LOCATION);
	 DROP COMMENTS NEW_COMMENTs NEW_POTS NEW_SHRIMP NEW_SOAKTIME MONTH 
		CATCH HRVRPT DAY;
RUN;

PROC PRINT DATA = HARVEST_1 (OBS = 20);
RUN;

* since this is a .csv, it only looks at the first 20 rows for getting the length
formats for location so include 'guessingrows = max' - guessingrows only works
for delimited files - This is imported above btw;
PROC IMPORT 
 OUT = CORRECT_STATAREA 
 DATAFILE= "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear.\xlocation_statarea_updated_&newyear..csv"  
 DBMS=csv REPLACE;
 guessingrows = max;
RUN;

* since we imported this and made adjustments to it previously, we just set it here;
DATA CORRECT_STATAREA_1;
	SET loc_stat1;
	LOCATION = UPCASE(LOCATION);
RUN;

* Save to the network for future imports;
data sasdata2.correct_statarea;
	set correct_statarea_1;
run;

* check stat area and location for errors (mult loc/stat);
proc sort data = correct_statarea_1
	nodupkey out = ck_loc;
	by location statarea;
run;

* check duplicated locations;
data single_loc dup_loc;
	set ck_loc;
	by location;
	if first.location and last.location
		then output single_loc;
			else output dup_loc;
run;

proc sort data = loc_stat; by location; run;
proc sort data = dup_loc; by location; run;

*Export duplicates to excel so amb can check them;
* These export steps can be skipped if already done or no dups found;
PROC EXPORT DATA = loc_stat
    OUTFILE = 
	"O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\check_loc_statarea.xlsx" 
	DBMS = XLSX REPLACE;
    SHEET = "location_statarea_updated_&newyear"; 
RUN;

PROC EXPORT DATA = dup_loc
    OUTFILE = 
	"O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\check_loc_statarea.xlsx" 
	DBMS = XLSX REPLACE;
    SHEET = "mult_stat"; 
RUN;
	
*Problem Merging these two datasets *;
PROC SORT DATA = CORRECT_STATAREA_1; BY LOCATION; run;

PROC PRINT DATA = CORRECT_STATAREA_1 (OBS = 10);
RUN;

PROC SORT DATA = HARVEST_1; BY LOCATION; run;

PROC PRINT DATA = HARVEST_1 (OBS = 10); run;

* something is going on here making harvest go from 10320 rows to 10965;
DATA HARVEST_2 onlyhv onlystat; 
	MERGE HARVEST_1 (in = h) CORRECT_STATAREA_1 (in = c);
	BY LOCATION;
	if h = 1 and c = 1 then output harvest_2;
	if h = 1 and c = 0 then output onlyhv;
	if h = 0 and c = 1 then output onlystat;
    IF PERMIT = . THEN DELETE;
RUN;

* some of onlyhv have harvest, get correct statarea from amb;
data ck_only;
	set onlyhv;
	keep location statarea;
run;

proc sort data = ck_only nodupkey out = ck_location; by location; run;

*Export duplicates to excel so amb can check them;
PROC EXPORT DATA = ck_location
    OUTFILE = 
	"O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\check_loc_statarea.xlsx" 
	DBMS = XLSX REPLACE;
    SHEET = "harv_loc_check"; 
RUN;

PROC PRINT DATA = HARVEST_2 (OBS = 50);
RUN;

* check harvest2 for duplicate records after merge;
proc sort data = harvest_2; by hvrecid; run;

data single dup;
	set harvest_2;
	by hvrecid;
	if first.hvrecid and last.hvrecid 
		then output single;
			else output dup;
run;

* look for distinct combinations of location and statarea to find errors;
proc sort data = dup nodupkey 
	out = dist_loc_stat;  
	by location statarea;
run;

DATA LOC_PROBLEMS; 
	SET HARVEST_2;
     IF STATAREA = .;
run;

PROC PRINT DATA = LOC_PROBLEMS;
RUN;

PROC FREQ DATA = LOC_PROBLEMS;
     TABLES LOCATION / OUT=CHECK NOPRINT;
run;

PROC PRINT DATA = CHECK;
RUN;

* check year designation here;
PROC EXPORT DATA= WORK.CHECK
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&new\SHRIMP PERMITS &newYEAR" 
  DBMS=XLSX REPLACE;
            SHEET="LOCATION PROBLEMS"; 
RUN;

* This could be cleaned up to avoid divide by zero, but it doesn't have an effect;
DATA HARVEST_3; 
	SET HARVEST_2;
     GALLONS_PER_POT = ROUND(SHRIMP/POTS,0.5);  
	FORMAT GALLONS_PER_POT 4.1;
     POT_DAYS = POTS * (SOAKTIME/24); 
	FORMAT POT_DAYS 8.1;
run;

PROC SORT DATA = HARVEST_3; BY PERMIT; run;

PROC PRINT DATA = HARVEST_3 (OBS = 40);
     TITLE2 'HARVEST FILE';
     TITLE3 ;
RUN;

* Looks like harvest_4 gets week added in and recalculates stuff for some reason;
 *Using the discrete method, WEEK intervals are determined by the number of 
	Sundays, the default first day of the week, that occur between the start-date 
	and the end-date, and not by how many seven-day periods fall between 
	those dates. To count the number of seven-day periods between start-date 
	and end-date, use the continuous method.;
DATA HARVEST_4; 
	SET HARVEST_3;
   * IF GALLONS_PER_POT GT 2.4 THEN SHRIMP = SHRIMP/120;
     GALLONS_PER_POT = ROUND(SHRIMP/POTS,0.5);  
	FORMAT GALLONS_PER_POT 4.1;
     WEEK = INTCK('WEEK',INTNX('YEAR', HARVDATE, 0), HARVDATE) + 1;
RUN;

proc print data = harvest_4 (obs = 20); title2 'harv file'; run;

PROC FREQ DATA = HARVEST_4;
     TABLES HARVDATE SHRIMP POTS SOAKTIME GALLONS_PER_POT LOCATION 
		STATAREA POT_DAYS WEEK;
     TITLE2 'SUMMARIES FROM HARVEST FILE';
run;

PROC FREQ DATA = HARVEST_4;
     WHERE STATAREA = .;
	 TABLES LOCATION;
     TITLE2 'THESE LOCATIONS DO NOT HAVE A STATAREA';
RUN;

PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED HARVEST';
     TABLES SHRIMP / NOPRINT OUT = FREQ_HARVEST;
RUN;

proc sort data = freq_harvest; by count; run;

proc print data = freq_harvest; sum count; run;

PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED HARVEST BY STATAREA';
     TABLES STATAREA / NOPRINT OUT = HARVEST_BY_AREA;
     WEIGHT SHRIMP;
RUN;

PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED HARVEST BY WEEK';
     TABLES WEEK / NOPRINT OUT = HARVEST_BY_WEEK;
     WEIGHT SHRIMP;
RUN;

PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED EFFORT BY STATAREA';
     TABLES STATAREA / NOPRINT OUT = EFFORT_BY_AREA;
     WEIGHT POT_DAYS;
RUN;

PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED EFFORT BY WEEK';
     TABLES WEEK / NOPRINT OUT = EFFORT_BY_WEEK;
     WEIGHT POT_DAYS;
RUN;

PROC PRINT DATA = HARVEST_4;
     WHERE GALLONS_PER_POT GT 2.4;
     TITLE2 'HARVEST FILE';
     TITLE3 'GALLONS PER POT GT 2.4';
RUN;
/*
PROC PRINT DATA = HARVEST;
     WHERE POTS GT 5;
     TITLE3 'MORE THAN 5 POTS';
*/
PROC PRINT DATA = HARVEST_4;
     WHERE SOAKTIME GT 400;
     TITLE3 'SOAK TIME GREATER THAN 400';
RUN;

DATA HARVEST_BY_AREA_1; 
	SET HARVEST_BY_AREA;
     RENAME COUNT = SHRIMP PERCENT = PERCENT_HARVEST;
run;

DATA EFFORT_BY_AREA_1; 
	SET EFFORT_BY_AREA;
     RENAME COUNT = POT_DAYS PERCENT = PERCENT_EFFORT;
run;

DATA HARVEST_BY_WEEK_1; 
	SET HARVEST_BY_WEEK;
     RENAME COUNT = SHRIMP PERCENT = PERCENT_HARVEST; 
run;
 
DATA EFFORT_BY_WEEK_1; 
	SET EFFORT_BY_WEEK;
     RENAME COUNT = POT_DAYS PERCENT = PERCENT_EFFORT;   
RUN;

DATA TABLE_STAT_AREA; 
	MERGE HARVEST_BY_AREA_1 EFFORT_BY_AREA_1; 
	BY STATAREA;
     IF SHRIMP = . THEN SHRIMP = 0;
	 IF STATAREA NE . AND PERCENT_HARVEST = . THEN PERCENT_HARVEST = 0;
run;

PROC PRINT data = table_stat_area;
     TITLE3 'EFFORT AND HARVEST BY STATAREA';
RUN;

DATA TABLE_WEEK; 
	MERGE HARVEST_BY_WEEK_1 EFFORT_BY_WEEK_1; 
	BY WEEK;
run;

PROC PRINT data = table_week;
     TITLE3 'EFFORT AND HARVEST BY WEEK';
RUN;

PROC MEANS NOPRINT DATA = HARVEST_4; 
     VAR GALLONS_PER_POT SHRIMP POT_DAYS;
     OUTPUT OUT = SUMMARY MEAN(GALLONS_PER_POT) = MEAN_GALLONS_PER_POT 
	SUM = JUNK TOTAL_SHRIMP TOTAL_POT_DAYS;
RUN;

DATA SUMMARY_1; 
	SET SUMMARY;
     RENAME _FREQ_ = RECORDS;
     DROP JUNK _TYPE_;
run;

PROC PRINT data = summary_1;
     TITLE2 'SUMMARY OF REPORTED INFORMATION';
RUN;

PROC SORT DATA = HARVEST_4; BY STATAREA; run;

PROC MEANS NOPRINT DATA = HARVEST_4; 
	BY STATAREA;
     VAR GALLONS_PER_POT SHRIMP POT_DAYS;
     OUTPUT OUT = SUMMARY_2 MEAN(GALLONS_PER_POT) = MEAN_GALLONS_PER_POT 
	SUM = JUNK TOTAL_SHRIMP TOTAL_POT_DAYS;
RUN;

DATA SUMMARY_3; 
	SET SUMMARY_2;
     RENAME _FREQ_ = RECORDS;
     DROP JUNK _TYPE_;
run;

PROC PRINT data = summary_3;
     TITLE2 'SUMMARY OF REPORTED INFORMATION';
RUN;

DATA SASDATA2.SHRIMP_HARVEST; 
	SET HARVEST_4; 
RUN;

proc freq data = new_date; tables comments; run;

DATA COMMENTS; 
	SET new_date;
     if COMMENTS = '' or comments = "NULL" then delete;
     KEEP PERMITNO HVRECID COMMENTS SHRIMP;
RUN;

PROC EXPORT DATA= WORK.COMMENTS
            OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" DBMS=XLSX REPLACE;
            SHEET="HARVEST COMMENTS"; 
RUN;


*PROC EXPORT DATA= WORK.HARVEST
            OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" DBMS=XLSX REPLACE;
 *           SHEET="HARVEST RECORDS"; 
*RUN;

PROC EXPORT DATA= WORK.TABLE_STAT_AREA
            OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" DBMS=XLSX REPLACE;
            SHEET="EFFORT AND HARVEST BY STATAREA"; 
RUN;

PROC EXPORT DATA= WORK.TABLE_WEEK
            OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" DBMS=XLSX REPLACE;
            SHEET="EFFORT AND HARVEST BY WEEK"; 
RUN;


