data wk38;
	set harvest_4;
	if week = 38;
run;

proc sort data = wk38; by hvrecid; run;

data perm_ck; 
	set harvest_4;
	if hvrecid = 142890;
run;

data perm_ck; 
	set harvest_4;
	if hvrecid = 140493;
run;

data wk16;
	set harvest_4;
	if week = 16;
run;

proc freq data = wk16; tables harvdate; run;

proc freq data = harvest_4; tables week; run;

proc sort data = wk16; by hvrecid; run;

data x_harv_4;
	set harvest_4;
	if statarea = 456032;
run;

