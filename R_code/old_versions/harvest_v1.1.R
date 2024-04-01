# clear up the global environment if needed by running line 2.
#  rm(list = ls())

###############################################################################
# II.  Harvest_v1.1
#  This program is for getting harvest, etc.
###############################################################################

library(tidyverse)
library(magrittr)
library(janitor)
library(lubridate)
library(stringi)
library(writexl)
library(readxl)

# edit each year as necessary if the year &/or file name changes
year <- "2023"

# check original column names of harvest file to see what they look like
# R packages have problems with special characters so convert the strings
# to windows-1252
# convert with stringi::stri_enc_toutf8() might help if not utf-8
harv_in <- read_csv(str_c("pwshvc_", year, ".csv"),
            locale = locale(encoding = "windows-1252")) %>%
  clean_names() %>%
  remove_empty()# %>%
  #mutate(location = stri_enc_toutf8(location))

names(harv_in)

# harvdate is often a problem, check to see if there are extraneous entries
table(harv_in$harvdate)

# for some reason switch zero to NA for pots & soaktime using dplyr::na_if()
# str_trim removes leading and tailing spaces on a string
# tried str_split(harvdate, " ", simplify = TRUE)[[1]] but it is only
# returning one value, corrected code works below
harvest <- harv_in %>%
  mutate(
    location = str_trim(toupper(stri_enc_toutf8(location))),
    harvdate = mdy(harvdate),
    keydate = mdy(keydate),
    soaktime = ifelse(soaktime == 0 | soaktime == "NULL", NA, soaktime),
    pots = na_if(pots, 0),
    # I'm not sure why this next step for nocatch is in here 
    nocatch = ifelse(shrimp > 0, 0, nocatch),
    catch = ifelse(nocatch == 1, "N", "Y"),
    hrvrpt = ifelse(nohrvrpt == 1, "N", "Y"),
    location = replace_na(location, "UNKNOWN"),
    month = month(harvdate),
    day = day(harvdate)
  ) %>%
  select(-c(nocatch, nohrvrpt, comments, stat_area))

# check max string length by row to see if that matches with SAS
max(nchar(harvest$location))

# which dates failed to parse?
check_date <- harvest %>%
  filter(is.na(harvdate)) 

# Import Location statarea.csv to check against harvest locations;
# similar to importing the harvest file, special characters are causing
# issues with invalid strings, include: locale = locale(encoding = "windows-1252")
loc_stat <- read_csv(str_c("location_statarea_updated_", year, ".csv"),
                     locale = locale(encoding = "windows-1252")) %>%
  clean_names() %>%
  mutate(location = str_trim(toupper(location)))

# check for duplicated harvest records
harvest %>%
  group_by(hvrecid) %>%
  filter(n() > 1)

# clean out duplicated and NA
harvest_1 <- harvest %>%
  filter(!is.na(hvrecid))

############################################################################
# check for mailing discrepancies - semi_join looks for exact matches in both
check_har <- semi_join(harvest_1, loc_stat, by = "location")

# anti_join looks for values in harvest but not in loc_stat
check_onlyhar <- anti_join(harvest_1, loc_stat, by = "location")
###########################################################################

# vice versa
onlyloc <- anti_join(loc_stat, harvest, by = "location")

#############################################################################
# summarise locations that are only in harvest
check_harloc <- check_onlyhar %>%
  group_by(location) %>%
  summarise(freq = n()) %>%
  filter(freq > 1)

# import revised (edited and checked) file back in
# ymd() from lubridate specifies the input character string is yyyy-mm-dd
#    2023 - harvest file was pretty clean so no back and forth needed
harvest_change <- read_csv(
  str_c("pwshvc_", year, "_final.csv")
) %>%
  clean_names() %>%
  mutate(
    harvdate = mdy(harvdate),
    keydate = mdy(keydate)
    )

compare_df_cols(harvest_1, harvest_change)
compare_df_cols_same(harvest_1, harvest_change)

# join in the original harvest file to the new harvest file
# replace na values if any
harvest_2 <- left_join(
  harvest_change, harvest_1, by = "hvrecid",
  suffix = c("", "_dup")
) %>%
  mutate(
    comments = ifelse(is.na(new_comments), NA, new_comments),
    pots = ifelse(is.na(new_pots), NA, new_pots),
    shrimp = ifelse(is.na(new_shrimp), NA, new_shrimp),
    soaktime = ifelse(is.na(new_soaktime), NA, new_soaktime),
    location = replace_na(location, "UNKNOWN")
  ) %>%
  select(-c(ends_with("_dup"), new_comments, new_pots, new_shrimp,
            new_soaktime, month, catch, hrvrpt, day))

# 2023 code
harvest_2 <- harvest_1 

##########################################################################
# read in corrected stat areas
# This is usually an updated version once AMB gets done with it and returns it
correct_statarea <- read_csv(
  str_c("location_statarea_updated_", year, ".csv"),
  locale = locale(encoding = "windows-1252")
) %>%
  clean_names() %>%
  mutate(
    location = str_trim(toupper(location)),
    statarea = str_trim(statarea)
  )

any(is.na(harvest_2$permitno))

# create dataset without duplicates
uniq_correct_stat <- unique(correct_statarea) %>%
  filter(
    !is.na(location)
  ) %>%
  arrange(location)

# get number of locations in unique data
n_loc_stat <- uniq_correct_stat %>%
  group_by(location) %>%
  summarise(count = n()) %>%
  arrange(desc(count))

# get locations that appear more than once
mult_stat <- n_loc_stat %>% 
  filter(count > 1)

# Look for locations that have more than one statarea from original data
mult_loc <- correct_statarea %>% 
  filter(
    location %in% unlist(select(mult_stat, location))
  ) %>%
  arrange(location)

#########################################################################
# get locations with multiple stat areas
check_mult_stat <- unique(mult_loc)
###########################################################################

# try a merge 
harvest_3 <- left_join(harvest_2, uniq_correct_stat, by = "location")

nrow(unique(harvest_3))

# check for missing statarea or NA statarea
# this is the same as check_only_har
loc_problems <- harvest_3 %>%
  filter(is.na(statarea) | statarea == "")

head(loc_problems)

# summarise location by number of statareas missing
miss_stat <- loc_problems %>%
  dplyr::count(location) %>%
  mutate(percent = n * 100 / sum(n)) %>%
  arrange(desc(n))

# SAS code adds one to week for some reason
# If you look @ lubridate::week() it already adds one so remove for now
# week() isn't really working so try isoweek().
harvest_4 <- harvest_3 %>%
  mutate(
    # try without round for now - gallons_per_pot = round(shrimp / pots),
    gallons_per_pot = shrimp / pots,
    pot_days = pots * (soaktime / 24),
    week = epiweek(harvdate) + 1
  ) %>%
  arrange(permitno, hvrecid)

harvest_5 <- harvest_4 %>%
  distinct(hvrecid, .keep_all = TRUE)

# shrimp frequency
freq_harvest <- harvest_5 %>%
  dplyr::count(shrimp) %>%
  mutate(percent = n * 100 / sum(n)) %>%
  arrange(desc(n)) %>%
  arrange(shrimp)

sum(freq_harvest$n)

# check harvest by statarea
harv_by_area <- harvest_5 %>%
  group_by(statarea) %>%
  summarise(
    count = sum(shrimp),
  ) %>% 
  ungroup() %>%
  mutate(
    tot_shrimp = sum(count, na.rm = TRUE),
    percent_harvest = (count / tot_shrimp) * 100
  ) %>%
  select(-tot_shrimp) %>%
  rename(shrimp = count) %>%
  arrange(statarea)

# check harvest by week
# week assignment is different from SAS
harv_by_week <- harvest_5 %>%
  group_by(week) %>%
  summarise(
    count = sum(shrimp, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  mutate(
    tot_shrimp = sum(count, na.rm = TRUE),
    percent_harvest = (count / tot_shrimp) * 100
  ) %>%
  select(-tot_shrimp) %>%
  rename(shrimp = count) %>%
  arrange(week)

# effort (pot_days) by area
effort_by_area <- harvest_5 %>%
  group_by(statarea) %>%
  summarise(
    count = sum(pot_days, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  mutate(
    tot_pot_days = sum(count, na.rm = TRUE),
    percent_effort = (count / tot_pot_days) * 100
  ) %>%
  select(-tot_pot_days) %>%
  rename(pot_days = count) %>%
  arrange(statarea)

# effort (pot_days) by WEEK
effort_by_week <- harvest_5 %>%
  group_by(week) %>%
  summarise(
    count = sum(pot_days, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  mutate(
    tot_pot_days = sum(count, na.rm = TRUE),
    percent_effort = (count / tot_pot_days) * 100
  ) %>%
  select(-tot_pot_days) %>%
  rename(pot_days = count) %>%
  arrange(week)

# combine harvest and effort by area into one table
# replace NA with 0
table_stat_area <- left_join(harv_by_area, effort_by_area, by = "statarea") %>%
  mutate(
    shrimp = replace_na(shrimp, 0),
    percent_harvest = ifelse(
      !is.na(statarea) & is.na(percent_harvest), 0, percent_harvest
    )
  )

# same with weekly numbers
table_week <- left_join(harv_by_week, effort_by_week, by = "week")

# summarise everything into one row
summary <- harvest_5 %>% summarise(
  mean_gal_per_pot = mean(gallons_per_pot, na.rm = TRUE),
  total_shrimp = sum(shrimp, na.rm = TRUE),
  total_pot_days = sum(pot_days, na.rm = TRUE)
)
  
# summarise by statarea
summary_stat <- harvest_5 %>%
  group_by(statarea) %>%
  summarise(
  mean_gal_per_pot = mean(gallons_per_pot, na.rm = TRUE),
  total_shrimp = sum(shrimp, na.rm = TRUE),
  total_pot_days = sum(pot_days, na.rm = TRUE)
)

comments <- harv_in %>%
  filter(comments != is.na) %>%
  select(permitno, hvrecid, comments, shrimp)

# Export harvest file for import into estimates
write_csv(harvest_5, str_c("shrimp_harvest_", year, ".csv"))

# if comments is empty, comment it out in the export to xlsx procedure
##########################################################################

tab_desc <- as.data.frame(t(tibble(
  bad_loc = "locations with no matchable statarea",
  statarea = "harvest locations with a matchable statarea",
  mult_err = "locations with no statarea that occur more than once",
  date_err = "errors with harvest date record",
  mult_stat_err = "locations with multiple statareas causing merge problems",
  correct_stat = "statarea file as read into R",
  # comments = "comments from the harvest file, if no tab than there weren't any comments",
  effort_har_area = "effort and harvest by statarea",
  effort_har_week = "effort and harvest by week"
)
)
) %>%
  rownames_to_column() %>%
  rename(tab = rowname, tab_description = V1)

# export onlyhar, check, and check_har to .xlsx for review by AMB
# Do this later with the other check datasets added
write_xlsx(
  list(
    bad_loc = check_onlyhar,
    statarea = check_har,
    mult_err = check_harloc,
    date_err = check_date,
    mult_stat_err = check_mult_stat,
    correct_stat = correct_statarea,
    #comments = comments,
    effort_har_area = table_stat_area,
    effort_har_week = table_week,
    description = tab_desc
  ), str_c(year, "_shrimppermits_locstat_harcheck", ".xlsx")
)

###############################################################################
