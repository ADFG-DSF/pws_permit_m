
* test;
proc import
	datafile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear.\pwshvc_&newyear..xlsx"
	out = xnew_data1
	dbms = xlsx
	replace;
run;

proc import
	datafile = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear.\pwshvc_&newyear._final.xlsx"
	out = xnew_data2
	dbms = xlsx
	replace;
run;

proc compare base = xnew_data1 (obs = 0)
	compare = xnew_data2 (obs = 0);
run;

ods listing close;
ods excel file = "O:\DSF\RTS\common\Pat\Permits\Shrimp\&newyear\&newyear._newhar.xlsx"
options (
	embed_titles_once = 'on'
	embedded_titles = 'on'
	flow = 'Tables'
	sheet_interval = 'proc'
	sheet_name = 'bad_loc');
proc print data = onlych noobs;
	title j = left 'Records in the new file, not in previous one';
run;

ods excel options (sheet_name = 'statarea');

ods excel close;
ods listing;
