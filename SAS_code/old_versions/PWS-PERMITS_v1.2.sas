****************************************************************************************;
*     There are 3 programs to analyze the salmon and shellfish permit databases:       *;
*         1. permits.sas                                                               *;
*         2. harvest.sas                                                               *;
*         3. estimates.sas                                                             *;
*     This program reads and modifies data for permits                                 *;
*     This program is stored as O:\DSF\RTS\PAT\PERMITS\&PROJECT\&YEAR\permit.sas       *;
****************************************************************************************;
dm 'keydef f12 "output ;clear ; log ; clear ;"';
dm "output;clear;log;clear";
proc datasets library = work kill; run;

%LET PROJECT = SHRIMP;
%LET DATA = pwspmc2021;
%LET YEAR = 2021;
%LET PROGRAM = PERMIT;
%let newyear = 2022; * only needed in 2022 for comparison, remove in future;

OPTIONS PAGENO=1 NODATE SYMBOLGEN LINESIZE=119 PAGESIZE=67 ;
options nocenter;
OPTION VALIDVARNAME=UPCASE;
LIBNAME SASDATA BASE "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR";
LIBNAME SASDATA2 BASE "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR";


TITLE1 "&PROJECT - &newYEAR";

* Import the original data - this is localized to 2022 so can be removed in future,
i.e. the next steps and the compare below;
DATA data_in; 
	SET SASDATA.&DATA;
     CITY = UPCASE(CITY);
run;

PROC PRINT DATA = data_in (OBS=10);
     TITLE2 'PERMIT DATABASE';
     TITLE3 'FIRST 10 RECORDS';
RUN; 

PROC CONTENTS DATA = data_in;
     TITLE3;
RUN;

/* IN 2022 we revised data to .xlsx rather than a sas7bdat file, the macro variables 
might not be needed anymore but test here 

- 12/22 update, importing as an .xlsx was creating issues, attempt with a .csv 
	- this didn't work, try to correct column 18 in excel. 

- 1/23 - several files were updated by AMB, including pwspmc, pwshvc, locations.
we use the most current ones. */

* make sure to revise the file name to match most recent version received;
proc import
	datafile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear.\pwspmc_&newyear..xlsx"
	out = new_data
	dbms = xlsx
	replace;
run;

* compare with previous year - this can be removed in 2023 as we move away from
sas7bdat files to import goes away;
proc compare base = data_in (obs = 0) 
	compare = new_data (obs = 0);
run;

****************************************************************************;
*                              PERMIT DATA                                	;
* Once AMB cleans the permit file, it needs to be reimported into SASDATA 	;
* That is done with the following code, importing the new file:				;
*																			;
* Keep track of the name of the permits file that is imported here as that 	;
* can change year to year.  												;
*===========================================================================;

/* 

proc import
	datafile = "O:\DSF\RTS\common\PAT\Permits\Shrimp\&newyear.\PWS_&newyear._Permits_final.xlsx"
	out = data_rev
	dbms = xlsx
	replace;
run;

data data_rev_1 xmiss;
	set data_rev;
	if permitno = "" then do;
		output xmiss; delete;
	end;
	output data_rev_1;
run;

proc compare base = data_in (obs = 0)
	compare = data_rev (obs = 0);
run;

* set lengths to match so merge doesn't truncate strings;
data data_rev_1;
	length last_name first_name city $30 license_no adlno $100
		address $50 keyid $25; 
	set data_rev;
	drop datehrvrpt;
run;

 * We need to merge in original data, for the missing variables;
proc sort data = data_rev_1; by permitno; run;
proc sort data = data_in; by permitno; run;

data issued_a onlyrev onlyin; 
	merge data_rev_1 (in = r) data_in (in = i);
	by permitno;
	if r = 1 and i = 0 then output onlyrev;
	if r = 0 and i = 1 then output onlyin;
	if r = 1 and i = 1 then output issued_a;
run;

proc sort data = onlyrev; by last_name; run;
proc sort data = onlyin; by last_name; run;

data issued;
	set issued_a;
	permit = permitno;
	rename status = s;
run;

*/

****************************************************************************;

* This dataset section is run on the original data, above is the revised set of;
*  code needed once you have a revised dataset from AMB so this can be skipped;
*  during revision;

* For this first run, updated 12/28/2022, we use the imported new_data.  Also for some
reason comments were all NULL so added code here;
DATA ISSUED; 
	SET new_data;
     PERMIT = PERMITNO;
     RENAME STATUS = S;
	 if comments = 'NULL' then comments = '';
run;

proc freq data = issued; tables office; run;

* since there are no 'null' office designations, I'll comment out the code below since
it is dealing with that assignment.  Problem with subsetting numeric variable as a 
character;

DATA ISSUED_1; 
	SET ISSUED;
     IF S = 'U' THEN STATUS = 'BLANK REPORT    ';
     IF S = 'N' THEN STATUS = 'DID NOT FISH';
     IF S = 'H' THEN STATUS = 'HARVEST REPORTED';
     IF S = 'Z' THEN STATUS = 'NON RESPONDENT';
	 IF AR = 1 THEN RESIDENT = 'Y';
	 IF NR = 1 THEN RESIDENT = 'N';
	 IF NOVENDCARD = 0 THEN VENDORCARD = 'Y';
	 IF NOVENDCARD = 1 THEN VENDORCARD = 'N';
     *IF OFFICE = "NULL" THEN OFFICE = "";
     IF S = 'Z' THEN RESPONDED = 'N'; 
        ELSE RESPONDED = 'Y';
     CHECK = SPORT + PERUSE + SUBSISTENCE;
run;

proc freq data = issued_1; tables status; run;

PROC PRINT DATA = ISSUED_1;
     WHERE CHECK NE 1;
     VAR PERMIT STATUS SPORT PERUSE SUBSISTENCE CHECK;
     TITLE2 'CHECK THE USE OF THESE PERMITS';
RUN;

DATA ISSUED_2; 
	SET ISSUED_1;
     IF CHECK = 1 AND SPORT = 1 THEN USE = 'SPORT         ';
     IF CHECK = 1 AND PERUSE = 1 THEN USE = 'PERSONAL   ';
	 IF CHECK = 1 AND SUBSISTENCE = 1 THEN USE = 'SUBSISTENCE';
	 IF CHECK = 0 THEN USE = 'BLANK';
	 if check = '.' then delete;
     DROP PMRECID ADDRESS ZIPCODE KEYDATE COMMENTS YEAR DATEISS 
		PERMITNO S KEYID INITIAL LICENSE_NO ALLOWED OFFICE DUPREF FAMILYSI
          DATEHRVRPT CHECK SPORT PERUSE SUBSISTENCE AR NR NOVENDCARD;
RUN;

PROC SORT data = issued_2; 
	BY PERMIT;
     TITLE2 'SAS WORK ISSUED DATABASE';
     TITLE3 'CHECKS';
RUN;

PROC FREQ data = issued_2;
     TABLES MAILING STATUS VENDORCARD RESPONDED MAILING*STATUS 
		CITY STATE USE RESIDENT / NOPERCENT NOROW NOCOL;  *ALLOWED NOT POTS;
run;

PROC FREQ DATA = ISSUED_2;
     TABLES STATUS * RESPONDED / OUT = SUMMARY_RESPONSE;
run;

PROC FREQ DATA = ISSUED_2;
     TABLES MAILING / NOPRINT OUT = MAILING;
RUN;

DATA PERSONAL; 
	SET ISSUED_2;
     KEEP PERMIT ADLNO CITY STATE FIRST_NAME LAST_NAME USE RESIDENT;
run;

DATA ISSUED_3; 
	SET ISSUED_2;
     DROP ADLNO CITY STATE FIRST_NAME LAST_NAME HHMEMBERS USE RESIDENT;
run;

PROC PRINT DATA = ISSUED_3 (OBS = 10);
     TITLE2 'PERMANENT SAS ISSUED DATABASE';
     TITLE3 'FIRST 10 RECORDS';
RUN;

* SASDATA & SASDATA2 are unique to 2022 so revise to just one in the future;
DATA SASDATA2.ISSUED; 
	SET ISSUED_3;
     DROP VENDORCARD;
run;

DATA SASDATA2.PERSONAL; 
	SET PERSONAL;
RUN;

* change sasdata2 in the future here;
DATA TOTAL_ISSUED; 
	SET SASDATA2.ISSUED NOBS = DUMMY;
     IF _N_ = 1;
     N = DUMMY*1;
     KEEP N;
run;

PROC PRINT DATA = TOTAL_ISSUED;
     TITLE2 'THE NUMBER OF PERMITS ISSUED';
     TITLE3;
RUN;

DATA SASDATA2.TOTAL_ISSUED; 
	SET TOTAL_ISSUED;
RUN;

/* In 2022 we imported data from a .xlsx file (new_data) so use the imported data but preserve
the code if it comes back. Also in 2022, all empty comments were replaced by 'NULL'
we will use the dataset 'issued' to pull these out as some new code was written there.

DATA COMMENTS; 
	SET SASDATA.&DATA;
     WHERE COMMENTS NE '';
     KEEP PERMITNO COMMENTS;
run;
*/

data comments;
	set issued;
	where comments ne '';
	keep permitno comments;
run;

PROC EXPORT DATA= WORK.COMMENTS 
 OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" 
		DBMS=XLSX REPLACE;
            SHEET="PERMIT COMMENTS"; 
RUN;

PROC EXPORT DATA= WORK.MAILING
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" 
		DBMS=XLSX REPLACE;
            SHEET="MAILING SUMMARY";
RUN;

PROC EXPORT DATA= WORK.SUMMARY_RESPONSE
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" 
		DBMS=XLSX REPLACE;
            SHEET="SUMMARY_RESPONSE"; 
RUN;

PROC EXPORT DATA= WORK.ISSUED_3
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" 
		DBMS=XLSX REPLACE;
            SHEET="PERMIT RECORDS"; 
RUN;

PROC EXPORT DATA= WORK.TOTAL_ISSUED 
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&newYEAR\SHRIMP PERMITS &newYEAR" 
		DBMS=XLSX REPLACE;
            SHEET="TOTAL ISSUED"; 
RUN;

****************************************************;
*				THE END								;
****************************************************;
