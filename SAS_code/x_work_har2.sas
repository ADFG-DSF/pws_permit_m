* here is some code that produces the harvest and effort by week 
for the PWS permit (and similar personal use permits);
dm editor "output;clear;log;clear" wedit;
proc datasets library = work kill; run;

options symbolgen mprint;
options mprint sortsize=max ;
options nocenter;

/* The data set that is used to calculate the harvest by week and statarea is harvest_4. 
You can revise the folder location to wherever you want it to be */
proc import
	datafile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\2023\harvest_4.csv"
	out = harvest_4
	dbms = csv
	replace;
	getnames = yes;
	guessingrows = max;
run;

* The following are the lines of code that generate the weekly tables 
given to Donnie and Brittany as part of the yearly excel file outputs. I have not 
altered this code and I believe it has been in tact since Pat wrote it.  The same
procedure is used for statarea.;

PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED HARVEST BY WEEK';
     TABLES WEEK / NOPRINT OUT = HARVEST_BY_WEEK;
     WEIGHT SHRIMP;
RUN;

proc print data = harvest_by_week; run;

* Here is a normal proc freq (without weight on shrimp);
PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED HARVEST BY WEEK';
     TABLES WEEK / OUT = HARVEST_WK_nowt;
RUN;

* compare with summary;
proc sort data = harvest_4; by week; run;

proc summary data = harvest_4;
	var shrimp;
	by week;
	output out = harv_wk_sum sum = ;
run;

PROC FREQ DATA = HARVEST_4;
     TITLE2 'REPORTED EFFORT BY WEEK';
     TABLES WEEK / NOPRINT OUT = EFFORT_BY_WEEK;
     WEIGHT POT_DAYS;
RUN;

