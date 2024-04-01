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

OPTIONS PAGENO=1 NODATE SYMBOLGEN LINESIZE=119 PAGESIZE=67 ;
options nocenter;
OPTION VALIDVARNAME=UPCASE;
LIBNAME SASDATA BASE "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR";

TITLE1 "&PROJECT - &YEAR";

* Import the original data;
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

****************************************************************************;
*                              PERMIT DATA                                	;
* Once Jay cleans the permit file, it needs to be reimported into SASDATA 	;
* That is done with the following code, importing the new file:				;
*																			;
*===========================================================================;

/* 
proc import
	datafile = "I:\common\Pat\Permits\Shrimp\&year.\PWS_&year._Permits_jab.xlsx"
	out = data_rev
	dbms = xlsx
	replace;
run;

data data_rev_1;
	set data_rev;
	drop datehrvrpt;
run;

 - We need to merge in original data, for the missing variables;
proc sort data = data_rev_1; by permitno; run;
proc sort data = data_in; by permitno; run;

data issued_a onlyrev onlyin; 
	merge data_rev_1 (in = r) data_in (in = i);
	by permitno;
	if r = 1 and i = 0 then output onlyrev;
	if r = 0 and i = 1 then output onlyin;
	if r = 1 and i = 1 then output issued_a;
run;

data issued;
	set issued_a;
	permit = permitno;
	s = status;
run;
*/

****************************************************************************;

* This dataset section is run on the original data, above is the revised set of;
*  code needed once you have a revised dataset from Jay so this can be skipped;
*  during revision;
DATA ISSUED; 
	SET data_in;
     PERMIT = PERMITNO;
     RENAME STATUS = S;
run;

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
     IF OFFICE = 'NULL' THEN OFFICE = '';
     IF S = 'Z' THEN RESPONDED = 'N'; 
        ELSE RESPONDED = 'Y';
     CHECK = SPORT + PERUSE + SUBSISTENCE;
run;

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

DATA SASDATA.ISSUED; 
	SET ISSUED_3;
     DROP VENDORCARD;
run;

DATA SASDATA.PERSONAL; 
	SET PERSONAL;
RUN;

DATA TOTAL_ISSUED; 
	SET SASDATA.ISSUED NOBS = DUMMY;
     IF _N_ = 1;
     N = DUMMY*1;
     KEEP N;
run;

PROC PRINT DATA = TOTAL_ISSUED;
     TITLE2 'THE NUMBER OF PERMITS ISSUED';
     TITLE3;
RUN;

DATA SASDATA.TOTAL_ISSUED; 
	SET TOTAL_ISSUED;
RUN;

DATA COMMENTS; 
	SET SASDATA.&DATA;
     WHERE COMMENTS NE '';
     KEEP PERMITNO COMMENTS;
run;

PROC EXPORT DATA= WORK.COMMENTS 
 OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" 
		DBMS=XLSX REPLACE;
            SHEET="PERMIT COMMENTS"; 
RUN;

PROC EXPORT DATA= WORK.MAILING
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" 
		DBMS=XLSX REPLACE;
            SHEET="MAILING SUMMARY";
RUN;

PROC EXPORT DATA= WORK.SUMMARY_RESPONSE
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" 
		DBMS=XLSX REPLACE;
            SHEET="SUMMARY_RESPONSE"; 
RUN;

PROC EXPORT DATA= WORK.ISSUED_3
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" 
		DBMS=XLSX REPLACE;
            SHEET="PERMIT RECORDS"; 
RUN;

PROC EXPORT DATA= WORK.TOTAL_ISSUED 
  OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" 
		DBMS=XLSX REPLACE;
            SHEET="TOTAL ISSUED"; 
RUN;

****************************************************;
*				THE END								;
****************************************************;
