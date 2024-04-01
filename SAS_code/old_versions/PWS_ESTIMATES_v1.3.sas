****************************************************************************************;
*     There are 3 programs to analyze the salmon and shellfish permit databases:       *;
*         1. permits.sas                                                               *;
*         2. harvest.sas                                                               *;
*         3. estimates.sas                                                             *;
*     This program estimates the harvest by species and fishery                        *;
*     This program is stored as O:\DSF\RTS\PAT\PERMITS\SHRIMP\2013\ESTIMATES.SAS       *;
****************************************************************************************;
dm editor "output;clear;log;clear" wedit;
proc datasets library = work kill; run;

%LET PROGRAM = ESTIMATES;
%LET PROJECT = SHRIMP;
%LET YEAR = 2023;
%LET SPECIES = SHRIMP;
%LET SPECIES_COMMA = SHRIMP,POT_DAYS; 
%LET SPECIES_LIST = SHRIMP POT_DAYS; 
%LET NUMBER_FISHERIES = 1;
%LET MATRIX = 2;   *NUMBER OF FISHERIES + 1;
%LET TOTAL = _2;   *NUMBER OF FISHERIES + 1;
%LET F1 = PWS;

OPTIONS PAGENO=1 NODATE SYMBOLGEN LINESIZE=119 PAGESIZE=67 ;
LIBNAME SASDATA BASE "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR";

options symbolgen mprint;
options mprint sortsize=max ;
options nocenter;

TITLE1 "&PROJECT - &YEAR";

**************************************************************************;
*                              ESTIMATES                                 *;
**************************************************************************;
proc freq data = sasdata.issued; tables status; run;

PROC FREQ DATA = sasdata.ISSUED;
     TABLES MAILING / NOPRINT OUT = BN;
run;

PROC TRANSPOSE DATA = BN OUT = BN_1;
      VAR COUNT;
run;

DATA BN_2; 
	SET BN_1 (RENAME=(COL1 = BN_0 COL2 = BN_1 COL3 = BN_2));
     KEEP BN_0 BN_1 BN_2;
run;

PROC PRINT DATA = BN_2;
     TITLE2 'RETURNED PERMITS BY MAILING';
     TITLE3 'DATA = BN';
RUN;

PROC SORT DATA=sasdata.SHRIMP_HARVEST out = shrimp; BY PERMIT; RUN;  
PROC SORT DATA=sasdata.ISSUED; BY PERMIT; RUN;

* check totals;
proc sql;
	select sum(shrimp) as total_shrimp, 
		sum(pot_days) as total_pot_days
	from shrimp;
quit;

proc export data = sasdata.shrimp_harvest
	outfile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&year.\shrimp_harvest.csv"
	dbms = csv
	replace;
run;

proc export data = sasdata.issued
	outfile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&year.\issued.csv"
	dbms = csv
	replace;
run;

proc export data = sasdata.total_issued
	outfile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&year.\total_issued.csv"
	dbms = csv
	replace;
run;

* Martz: Since all harvest records are now mailing = 4, to determine compliant
	or non compliant permits, we should take mailing from the permits file
	sasdata.issued;
data shrimp_1;
	set shrimp;
	drop mailing;
run;

DATA ALLPERMITS; 
	MERGE shrimp_1 (IN=INH) sasdata.ISSUED (IN=INP); 
	BY PERMIT;  
     IF INH THEN HARVFILE=1;
     IF INP THEN PERMFILE=1;
     PROJECT = 'SHRIMP';
     FISHERY = 'PWS';
RUN;

proc freq data = allpermits; tables mailing * responded; run;

PROC PRINT DATA=ALLPERMITS;
     WHERE HARVFILE=1 AND PERMFILE=.;
     TITLE2 'PERMITS THAT ARE IN HARVEST FILE BUT NOT IN PERMIT FILE';
     TITLE3 'NEED TO ADD THESE TO PERMIT FILE';
RUN;

DATA ALLPERMITS_1; 
	SET ALLPERMITS;
    IF RESPONDED EQ '' THEN RESPONDED = 'N';
     FISHERY = 'PWS';
    DROP HARVFILE PERMFILE;
RUN;

PROC PRINT DATA = ALLPERMITS_1 (OBS = 15);
     TITLE2 'ALLPERMITS DATASET';
     TITLE3 'FIRST 15 OBSERVATIONS';
RUN;

* check totals;
proc sql;
	select sum(shrimp) as total_shrimp, 
		sum(pot_days) as total_pot_days
	from allpermits_1
	group by fishery;
quit;

* export to double check sums;
proc export data = allpermits_1
	outfile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&year.\test.csv"
	dbms = csv
	replace;
run;

proc freq data = allpermits_1; tables responded * status; run;

proc freq data = allpermits_1; tables status; run;

* There is no 'blank report' but there is 'non respondent' so the fishing
	status was elevated.  The previous code had:
	IF STATUS = 'DID NOT FISH' OR STATUS = 'BLANK REPORT' THEN FISHED = 'N' 
        ELSE FISHED = 'Y'.  
	If 'BLANK REPORT' comes back, add back in;
* Total = shrimp + pot_days.  Note mailing 9 is responded = 'N';
DATA RETURNED; 
	SET ALLPERMITS_1 (RENAME=(FISHERY = OLDFSHRY));
     IF RESPONDED = 'N' THEN DELETE;
     TOTAL = SUM(&SPECIES_COMMA,0);
     IF MAILING LE 1 THEN COMPLIANT = 'Y';
        ELSE COMPLIANT = 'N';
     IF STATUS = 'DID NOT FISH' OR STATUS = 'NON RESPONDENT' THEN FISHED = 'N';
        ELSE FISHED = 'Y';
run;

* make sure status = nonrespondent and responded = N;
* compare this proc freq with the one run on allpermits_1;
proc freq data = returned; tables mailing; run;
	
proc freq data = returned; tables oldfshry; run;

* COUNT THE NUMBER OF PERMITS THAT DID NOT FISH;
DATA NOFISH; 
	SET RETURNED; 
	BY PERMIT;
     IF FIRST.PERMIT;
run;

PROC FREQ DATA=NOFISH; 
     TABLES COMPLIANT;
     TITLE2 'COMPLIANCE - RETURNED PERMITS ONLY';
RUN;

PROC FREQ DATA=NOFISH; 
     TABLES FISHED*MAILING/ OUT=NOFISHING;
     TITLE2 'NUMBER OF RESPONDING PERMITS CLASSIFIED BY FISHED / DID NOT FISH';
RUN;

* w_hat = n_df / n_d. n_df = Y in freq below and n/d is sum of Y & N;
PROC FREQ DATA = NOFISH; 
     WHERE MAILING = 2;
     TABLES FISHED/ NOPRINT OUT=NOFISHING2;
RUN;

DATA FISHED_MAILING2; 
	SET NOFISHING2;
     IF FISHED = 'Y';
     P = PERCENT / 100;
     Q = 1 - P;
     N = COUNT / P;
     VAR_P = ((P * Q)/(N-1))*((N - COUNT) / (N-1));
     SE_P = SQRT(VAR_P);
     _TYPE_ = 1;
run;

PROC PRINT data = fished_mailing2;
     TITLE2 'MAILING 2 PERMITS THAT FISH';
RUN;

DATA sasdata.FISHED_MAILING2; 
	SET FISHED_MAILING2;
run;

* Martz: w_hat is 'P' in fished_mailing_1;
DATA FISHED_MAILING_1; 
	SET FISHED_MAILING2 (KEEP = P VAR_P SE_P);
run;

* Only those that reported fishing;
DATA HARVESTED; 
	SET RETURNED;
     IF FISHED = 'N' THEN DELETE;
     IF OLDFSHRY EQ 'PWS'    THEN FISHERY = 1;
     FORMAT FISHERY 1.0;
     KEEP PERMIT HARVDATE &SPECIES_LIST TOTAL FISHERY COMPLIANT 
		MAILING OLDFSHRY;
RUN;

* SOME PERMITS MAY HAVE MORE THAN ONE RECORD FOR THE SAME FISHERY AND DATE.
  WE DON'T WANT TO COUNT THOSE AS TWO DAYS FISHED, SO NEED TO SUM THOSE RECORDS.;

PROC SORT DATA=HARVESTED; BY PERMIT FISHERY HARVDATE; run;

* Sum shrimp & pot_days & total by permit, fishery, harvest date;
PROC SUMMARY DATA=HARVESTED; 
	BY PERMIT FISHERY HARVDATE;
     VAR &SPECIES_LIST TOTAL;
     ID MAILING COMPLIANT;
     OUTPUT OUT=HARVESTED_1 SUM=;
RUN;

data x_harvdate;
	set harvested_1;
	if harvdate = .;
run;

PROC SORT DATA=HARVESTED_1; BY PERMIT FISHERY; run;

DATA sasdata.HARVESTED; 
	SET HARVESTED_1 (DROP = _TYPE_ _FREQ_);
RUN;

* Check number of missing data;
proc means data = harvested_1 nmiss; run;

data miss;
	set harvested_1;
	if pot_days = ".";
run; 

data x_harvested;
	set harvested_1;
	if pot_days = "." then pot_days = 0;
run;

PROC SUMMARY DATA=HARVESTED_1 NWAY; 
	BY PERMIT;
     VAR HARVDATE &SPECIES_LIST TOTAL;
     ID COMPLIANT MAILING; 
     OUTPUT OUT=TOTALHARV N(HARVDATE)=DAYS SUM=;
RUN;

* DO THIS SUMMARY & PRINT JUST TO CHECK THE SUM OF HARVEST FOR RETURNED PERMITS 
	TO SEE IF I'M ON TRACK;
PROC SORT DATA = HARVESTED_1; BY FISHERY; run;

PROC MEANS SUM NOPRINT DATA = HARVESTED_1; 
	BY FISHERY;
     VAR &SPECIES_LIST TOTAL;
     OUTPUT OUT = CHECK SUM=;
run;

PROC PRINT data = check LABEL;
     LABEL _FREQ_ = 'RECORDS';
     TITLE2 'REPORTED HARVEST BY FISHERY - NOT EXPANDED OR CORRECTED';
RUN;

* check imputed 0;
PROC MEANS SUM NOPRINT DATA = x_HARVESTED; 
	BY FISHERY;
     VAR &SPECIES_LIST TOTAL;
     OUTPUT OUT = x_CHECK SUM=;
run;

PROC PRINT data = x_check LABEL;
     LABEL _FREQ_ = 'RECORDS';
     TITLE2 'REPORTED HARVEST BY FISHERY - NOT EXPANDED OR CORRECTED';
RUN;

* The sum isn't matching with R so try a different method than proc means;
proc print data = harvested_1;
	sum shrimp pot_days total; 
	by fishery;
run;

* Export to double check sums, as there is a slight difference to R.;
proc export data = harvested_1
	outfile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\2021\test.csv"
	dbms = csv
	replace;
run;

* NOW GET FILE FISHERYHARVEST WITH ONE LINE PER PERMIT IN EACH FISHERY 
	(SUM ACROSS DATES)REMEMBER SOME PERMITS FISHED IN MORE THAN ONE FISHERY, 
	SO STILL HAVE MORE THAN ONE LINE PER PERMIT;
* Martz: for these data - there is only one fishery but it is treated as two
	through out the rest of the code;

PROC SORT DATA = HARVESTED_1; BY PERMIT; run;

* sum shrimp, pot_days, & total by permit with fishery sub-groups. N = 
	number of observations for 'days';
PROC SUMMARY DATA=HARVESTED_1 NWAY; 
	BY PERMIT;
     CLASS FISHERY;
     VAR &SPECIES_LIST TOTAL;
     ID MAILING COMPLIANT; 
     OUTPUT OUT=FISHERYHARVEST N=DAYS SUM=;
RUN;

DATA FISHERYHARVEST_1; 
	SET FISHERYHARVEST (DROP = _TYPE_ _FREQ_);
run;

* TRANSPOSE SO SPECIES BECOME ROWS AND FISHERIES ARE COLUMNS;
PROC SORT DATA = FISHERYHARVEST_1; BY PERMIT MAILING COMPLIANT; run;

PROC TRANSPOSE DATA=FISHERYHARVEST_1 OUT=FISHERYWIDE; 
	BY PERMIT MAILING COMPLIANT;
     VAR DAYS &SPECIES_LIST TOTAL;
     ID FISHERY;
RUN;

DATA FISHERYWIDE_1;  
	SET FISHERYWIDE;
     RENAME _NAME_=VARIABLE;
     &TOTAL = SUM(OF _1-_&NUMBER_FISHERIES);
run;

proc freq data = fisherywide_1; tables mailing; run;

PROC SORT DATA=FISHERYWIDE_1; BY PERMIT VARIABLE; run;

data fisherywide1a; 
	set fisherywide_1;
	if _1 eq .;
run;

* SET MISSING HARVESTS TO ZERO;
DATA FISHERYWIDE_2; 
	SET FISHERYWIDE_1;
     ARRAY CATCH(&MATRIX) _1-&TOTAL;
     DO I=1 TO (&MATRIX);
          IF CATCH(I) EQ . THEN CATCH(I) = 0;
          END;
     DROP I;
RUN;

proc freq data = fisherywide_2; tables mailing; run;

data check_val;
	set fisherywide_2;
	if variable = 'DAYS';
run;

proc freq data = check_val; tables _1; run;

proc sort data = fisherywide_2; by permit; run;

* check duplicates;
data single dup;
	set fisherywide_2;
	by permit;
	if first.permit and last.permit 
		then output dup;
			else output single;
run;

PROC SORT DATA=FISHERYWIDE_2; BY VARIABLE &TOTAL; run;

* COUNT THE NUMBER OF RECORDS THAT FISHED WITH NO HARVEST;
PROC FREQ DATA=FISHERYWIDE_2; 
     WHERE VARIABLE EQ 'TOTAL' AND (&TOTAL = . OR &TOTAL = 0);
     TABLES &TOTAL / MISSING OUT=NOHARVEST NOPRINT;
run;

DATA NOHARVEST_1; 
	SET NOHARVEST;
     RENAME COUNT = RECORDS &TOTAL = TOTAL_HARVEST;
     DROP PERCENT;
run;

PROC PRINT data = noharvest_1;
     TITLE2 'NUMBER OF RESPONDING PERMITS THAT FISHED, BUT DID NOT CATCH ANYTHING';
     TITLE3;
RUN;

* GET THE TOTAL REPORTED HARVEST FROM EACH FISHERY.
     THIS ISN'T USED IN THE FOLLOWING CALCULATIONS, JUST A HANDY SUMMARY.
     DO IT FIRST FOR ALL PERMITS, THEN FOR VOLUNTARY, MAIL1, MAIL2
     BN_V = THE NUMBER OF VOLUNTARY PERMITS;
PROC SUMMARY DATA=FISHERYWIDE_2 NWAY;
     CLASS VARIABLE;
     VAR _1-&TOTAL;
     OUTPUT OUT=BH_ SUM= N=BN_;
run;

* Export to double check sums, as there is a slight difference to R.;
proc export data = fisherywide_2
	outfile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\2021\test.csv"
	dbms = csv
	replace;
run;

DATA BH_1; 
	SET BH_ (DROP = _TYPE_ _FREQ_);
     IF VARIABLE = 'TOTAL' THEN DELETE;
run;

PROC PRINT data = bh_1 LABEL;
     LABEL _1="REPORTED HARVEST &F1" 
         BN_ = 'NUMBER RETURNED PERMITS' VARIABLE = 'VARIABLE';
     TITLE2 'TOTAL REPORTED HARVEST';
     TITLE3 'ALL RETURNED PERMITS';
RUN;

* compliant datacheck;
data x_comp;
	set fisherywide_2;
	where variable = 'POT_DAYS' and mailing = 0;
run; 

proc print data = x_comp;
	sum _1; 
run;

* check zero values and nonzero values from fisherywide_2;
data x_zero x_val;
	set x_comp;
	if _1 = 0 then output x_zero;
	if _1 ne 0 then output x_val;
run;

proc sort data = x_zero; by permit; run;
proc sort data = x_val; by permit; run;

PROC SUMMARY DATA=FISHERYWIDE_2 NWAY;
     WHERE MAILING EQ 0;
     CLASS VARIABLE;
     VAR _1-&TOTAL;
     OUTPUT OUT=BH_V N=BN_V SUM=  MEAN=MEAN1-MEAN&MATRIX;
run;

DATA BH_V_1; 
	SET BH_V (DROP = _TYPE_ _FREQ_);
     IF VARIABLE = 'TOTAL' THEN DELETE;
run;

PROC PRINT data = bh_v_1 LABEL;
     LABEL _1="REPORTED HARVEST &F1" 
         BN_V='NUMBER VOLUNTARY PERMITS THAT FISHED' VARIABLE = 'VARIABLE' 
        MEAN1="MEAN &F1";
     TITLE2 'TOTAL REPORTED HARVEST';
     TITLE3 'VOLUNTARY RETURNS';
RUN;

* GET THE TOTAL REPORTED MAILING 1 HARVEST FROM EACH FISHERY.
     THIS ISN'T USED IN THE FOLLOWING CALCULATIONS, JUST A HANDY SUMMARY.
     BN_1 = THE NUMBER OF MAILING 1 PERMITS;
PROC SUMMARY DATA=FISHERYWIDE_2 NWAY;
     WHERE MAILING = 1;
     CLASS VARIABLE;
     VAR _1-&TOTAL;
     OUTPUT OUT=BH_2 N=BN_1 SUM=  MEAN=MEAN1-MEAN&MATRIX;
run;

DATA BH_3; 
	SET BH_2 (DROP = _TYPE_ _FREQ_);
     IF VARIABLE = 'TOTAL' THEN DELETE;
run;

PROC PRINT data = bh_3 LABEL;
     LABEL _1="REPORTED HARVEST &F1" 
         BN_1 = 'NUMBER MAILING 1 PERMITS THAT FISHED' VARIABLE = 'VARIABLE' 
        MEAN1="MEAN &F1";
     TITLE3 'MAILING 1';
RUN;

* GET THE TOTAL REPORTED MAILING 2 HARVEST FROM EACH FISHERY.
     THIS ISN'T USED IN THE FOLLOWING CALCULATIONS, JUST A HANDY SUMMARY.
     BN_2 = THE NUMBER OF MAILING 2 PERMITS;
PROC SUMMARY DATA=FISHERYWIDE_2 NWAY;
     WHERE MAILING =2;
     CLASS VARIABLE;
     VAR _1-&TOTAL;
     OUTPUT OUT=BH_4 N=BN_2 SUM=  MEAN=MEAN1-MEAN&MATRIX;
run;

DATA BH_5; 
	SET BH_4 (DROP = _TYPE_ _FREQ_);
     IF VARIABLE = 'TOTAL' THEN DELETE;
run;

PROC PRINT data = bh_5 LABEL;
     LABEL _1="REPORTED HARVEST &F1" 
         BN_2 = 'NUMBER MAILING 2 PERMITS THAT FISHED' VARIABLE = 'VARIABLE' 
        MEAN1="MEAN &F1";
     TITLE3 'MAILING 2';
RUN;

* GET THE TOTAL REPORTED COMPLIANT HARVEST FROM EACH FISHERY.
     THIS IS USED IN THE FOLLOWING CALCULATIONS!
     BN_C = THE NUMBER OF COMPLIANT PERMITS;
PROC SUMMARY DATA=FISHERYWIDE_2 NWAY;
     WHERE COMPLIANT EQ 'Y';
     CLASS VARIABLE;
     VAR _1-&TOTAL;
     OUTPUT OUT=BH_C N=BN_C SUM= MEAN=MEAN1-MEAN&MATRIX;
run;

DATA BH_C_1; 
	SET BH_C (DROP = _TYPE_ _FREQ_);
     IF VARIABLE = 'TOTAL' THEN DELETE;
run;

PROC PRINT data = bh_c_1 LABEL;
     LABEL _1="REPORTED HARVEST &F1" 
         BN_C = 'NUMBER COMPLIANT PERMITS THAT FISHED' VARIABLE = 'VARIABLE' 
        MEAN1="MEAN &F1";
     TITLE3 'COMPLIANT';
RUN;

* bn_c_1 isn't really used;
DATA BN_C_1; 
	SET BH_C; 
	WHERE VARIABLE='DAYS'; 
RUN;

data check_1 (rename = (mailing = mailing_no));
	set fisherywide_2;
	if compliant eq 'N';
run;

proc freq data = check_1; tables mailing_no; run;

proc sort data = sasdata.issued out = permits; by permit; run;
proc sort data = check_1; by permit; run;

* Check if there are mailing number discrepancies and if permits that 
	are really compliant are making it into the calculation;
data check_mail onlypermit onlycheck;
	merge check_1 (in = c) permits (in = p);
	by permit;
	if c = 1 and p = 0 then output onlycheck;
	if c = 0 and p = 1 then output onlypermit;
	if c = 1 and p = 1 then output check_mail;
run;

data check_mail_2;
	set check_mail;
	if mailing_no = mailing then match_val = 'Y';
		else match_val = 'N';
	keep permit mailing_no compliant mailing responded match_val;
run;

proc freq data = check_mail_2; tables match_val; run;

* NOW CALCULATE MEAN NON-COMPLIANT HARVEST (LHB_D), THE NUMBER OF
     NON-COMPLIANT PERMITS (LN_D_FISHED), AND THE VARIANCE OF THE MEAN (BS1-BS6);
* Martz 2/2022: 'VAR' in output is sample variance not variance of mean. The old 
	title of this was 'VAR_MEAN', should revise to SAMP_VAR;
* Martz: Mean1 = h_bar_df from op plan;
PROC SUMMARY DATA=FISHERYWIDE_2 NWAY;
     WHERE COMPLIANT EQ 'N';
     CLASS VARIABLE;
     VAR _1-&TOTAL;
     OUTPUT OUT=LHB_D N=LN_D_FISHED SUM=  MEAN=MEAN1-MEAN&MATRIX 
		VAR=VAR_MEAN1-VAR_MEAN&MATRIX STDERR = SE1-SE&MATRIX;
RUN;

DATA LHB_D_1; 
	SET LHB_D (DROP = _FREQ_);
     IF VARIABLE = 'TOTAL' THEN DELETE;
run;

PROC PRINT data = lhb_d_1 LABEL;
     LABEL _1="REPORTED HARVEST &F1" 
           LN_D_FISHED = 'NUMBER NON-COMPLIANT PERMITS THAT FISHED' 
           VARIABLE = 'VARIABLE' 
           MEAN1="MEAN &F1" 
           VAR_MEAN1="VAR_MEAN &F1" 
           SE1="SE &F1";
     TITLE3 'NON COMPLIANT RESPONDED';
RUN;

* USE FILE TOTISS FOR TOTAL NUMBER OF PERMITS ISSUED
     CALCULATE NUMBER OF NON-COMPLIANT PERMITS (BNH_D).
     ITS VARIANCE IS THE VARIANCE OF THE ESTIMATE OF THE NUMBER OF PERMITS ISSUED.;
* Martz: N (op plan) = NHAT;
DATA TOTAL_ISSUED; 
	SET sasdata.TOTAL_ISSUED;
     RENAME N =NHAT;
     VAR_NHAT = 0;
run;

* Martz: BNH_D_FISHED = N_hat_df in op plan;
DATA BNH_D; 
	MERGE TOTAL_ISSUED (KEEP=NHAT VAR_NHAT) BN_2 FISHED_MAILING_1;
     BNH_D = NHAT - (BN_0 + BN_1);
     BNH_D_NR = BNH_D - BN_2;
     *BNH_D_NR_FISHED = BNH_D_NR * P;
     *VAR_BNH_D_NR_FISHED = BNH_D_NR**2 * VAR_P   +   P**2 * VAR_NHAT   -   VAR_NHAT * VAR_P;
     BNH_D_FISHED = ROUND(BNH_D * P,1);
     VAR_BNH_D_FISHED = BNH_D**2 * VAR_P;
     *FORMAT BNH_D_NR_FISHED VAR_BNH_D_NR_FISHED 5.0;
     FORMAT BNH_D_FISHED VAR_BNH_D_FISHED 5.0;
     _TYPE_ = 1;
run;

PROC PRINT data = bnh_d; 
     TITLE2 'DATA BNH_D'; 
     TITLE3;
RUN;

* CALCULATE NON-COMPLIANT HARVEST, EFFORT, AND THEIR VARIANCES FOR EACH FISHERY;
DATA BHH_D; 
	MERGE LHB_D_1 BNH_D; 
	BY _TYPE_; 
     KEEP VARIABLE MEAN1-MEAN&MATRIX VAR_MEAN1-VAR_MEAN&MATRIX BNH_D_FISHED 
		VAR_BNH_D_FISHED LN_D_FISHED BNH_D;
RUN;

* Martz: BHH_D (or BHH1 in output) = H_hat_df from op plan;
DATA BHH_D_1; 
	SET BHH_D;
     ARRAY LHB_D (&MATRIX) MEAN1-MEAN&MATRIX;
     ARRAY BHH_D (&MATRIX) BHH1-BHH&MATRIX;
     ARRAY BS_D (&MATRIX) VAR_MEAN1-VAR_MEAN&MATRIX;
     ARRAY VLHB_D (&MATRIX) VLHB_D1-VLHB_D&MATRIX;
     ARRAY VHH (&MATRIX) VHH1-VHH&MATRIX;
     ARRAY SE (&MATRIX) SE1-SE&MATRIX;
     DO I = 1 TO (&MATRIX);
      BHH_D(I) = BNH_D_FISHED * LHB_D(I);
      VLHB_D(I) = ((BNH_D_FISHED - LN_D_FISHED) / (BNH_D_FISHED -1)) * (BS_D(I)/LN_D_FISHED);
      VHH(I) = BNH_D_FISHED**2 * VLHB_D(I) + LHB_D(I)**2 * VAR_BNH_D_FISHED - VLHB_D(I) * VAR_BNH_D_FISHED;
      SE(I) = SQRT(VHH(I));
          END;
RUN;

PROC PRINT DATA = BHH_D_1; TITLE2 "ARRAYS FROM DATA SET BHH_D"; RUN;

DATA BHH_D_2; 
	SET BHH_D_1; 
	DROP I BNH_D LN_D_FISHED VAR_BNH_D_FISHED VAR_MEAN1-VAR_MEAN&MATRIX 
	VLHB_D1-VLHB_D&MATRIX;
run;

PROC PRINT data = bhh_d_2 LABEL;
      TITLE2 "ESTIMATES FOR NON-COMPLIANT PERMITS";
	  VAR VARIABLE BNH_D_FISHED MEAN1 BHH1 VHH1 SE1;
      LABEL VARIABLE = 'VARIABLE' 
            BNH_D_FISHED = 'NUMBER OF NONCOMPLIANT PERMITS THAT FISHED'
            MEAN1="MEAN &F1" 
            BHH1="ESTIMATED &F1 HARVEST"     VHH1="&F1 VAR"     SE1="&F1 SE";
RUN; 

* CONCATENATE THE COMPLIANT FILE (BH_C), THE NON-COMPLIANT-RESPONDED FILE (LHB_D) 
	AND THE NON-COMPLIANT-NON-RESPONDED FILE (BHH_D). RENAME THE VARIABLES IN 
	THE COMPLIANT FILE SO THEY MATCH THE NAMES OF THE EQUIVALENT NON-COMPLIANT 
	VARIABLES;
* Martz: BHH1 = H_cf from op plan;

DATA BH_X;
	length group $35; 
	SET BH_C_1(IN=C DROP=BN_C RENAME=(_1=BHH1))
        BHH_D_2(IN=Dnr DROP=BNH_D_FISHED);
     IF C THEN GROUP = 'COMPLIANT   ';
	 IF DNR THEN GROUP = 'NON-COMPLIANT';
     FORMAT _NUMERIC_ 9.0;
     DROP MEAN1-MEAN&MATRIX; 
RUN;

PROC PRINT data = bh_x; RUN;

/* ORIGINAL CODE - DON'T THINK THIS IS RIGHT
DATA LHB_D_2;
	SET LHB_D_1;
	DROP _TYPE_ LN_D_FISHED VAR_MEAN1 VAR_MEAN2 SE1 SE2;
	RENAME _1 = BHH1;
RUN;

DATA BH_X; SET BH_C(IN=C DROP=BN_C RENAME=(_1=BHH1)) 
                LHB_D_2(IN=DR DROP= _TYPE_ LN_D_FISHED VAR_MEAN1-VAR_MEAN&MATRIX SE1-SE&MATRIX RENAME=(_1=BHH1)) 
                BHH_D(IN=DNR DROP=BNH_D_FISHED);
     IF C THEN GROUP = 'COMPLIANT                    ';
     IF DR THEN GROUP = 'NON-COMPLIANT, RESPONDED';
     IF DNR THEN GROUP = 'NON-COMPLIANT, NON-RESPONDANT';
     FORMAT _NUMERIC_ 9.0;
     DROP MEAN1-MEAN&MATRIX; 
RUN;
PROC PRINT;
RUN;
*/

* SUM THE COMPLIANT AND NONCOMPLIANT HARVESTS AND EFFORTS TO GET TOTAL HARVEST YAHOO!;
PROC SUMMARY DATA=BH_X NWAY;
     CLASS VARIABLE;
     VAR BHH1-BHH&MATRIX SE1-SE&MATRIX;
     OUTPUT OUT=BHH SUM=;
RUN;

DATA BHH_1; 
	SET BHH (DROP = _TYPE_ _FREQ_ BHH2 SE2);
RUN;
 
PROC PRINT NOOBS LABEL DATA = BHH_1;
     ID VARIABLE;
     VAR BHH1 SE1;
     FORMAT _NUMERIC_ COMMA9.;
     TITLE2 'ESTIMATED HARVEST AND EFFORT';
             LABEL VARIABLE = 'VARIABLE'
                 BHH1="ESTIMATED &F1 HARVEST"      SE1="&F1 SE";
RUN;

DATA sasdata.FINAL_ESTIMATES; 
	SET BHH_1;
RUN;

DATA BH_OUT; 
	SET BH_;
     RENAME _1 = REPORTED_HARVEST_PWS
            BN_ = NUMBER_RETURNED_PERMITS_FISHED;
     DROP _2 _type_ _freq_;
	 if variable = 'TOTAL' then delete;
RUN;

PROC EXPORT DATA= WORK.BH_OUT
            OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" DBMS=XLSX REPLACE;
            SHEET="REPORTED HARVEST"; 
RUN;

DATA BHH_OUT; 
	SET BHH_1;
      RENAME BHH1 = ESTIMATED_HARVEST_PWS SE1 = PWS_HARVEST_SE;
RUN;

PROC EXPORT DATA= WORK.BHH_OUT
            OUTFILE= "O:\DSF\RTS\common\PAT\PERMITS\&PROJECT\&YEAR\SHRIMP PERMITS &YEAR" DBMS=XLSX REPLACE;
            SHEET="EXPANDED HARVEST"; 
RUN;

********************************************************;
*					THE END								;
********************************************************;
