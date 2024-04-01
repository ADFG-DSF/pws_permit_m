# clear up the global environment if needed by running line 2.
#  rm(list = ls())

###############################################################################
# II.  Harvest_v1.2
#  This program is for getting harvest, etc.
###############################################################################

library(tidyverse)
library(magrittr)
library(janitor)
library(lubridate)
library(stringi)
library(writexl)

# edit each year as necessary if the year &/or file name changes
year <- "2023"

# check original column names of harvest file to see what they look like
# R packages have problems with special characters so convert the strings
# to windows-1252
# convert with stringi::stri_enc_toutf8() might help if not utf-8
pwshvc <- read_csv(str_c("pwshvc_", year, ".csv"),
                    locale = locale(encoding = "windows-1252")) %>%
  clean_names() 

names(pwshvc)

str(pwshvc)

# harvdate is often a problem, check to see if there are extraneous entries
table(pwshvc$harvdate)

# clean up empty columns and change harvedate to datetime
harv_in <- pwshvc %>%
  mutate(
    harvdate = mdy(harvdate),
    keydate = mdy(keydate)
  ) %>%
  remove_empty()

# zero to NA for pots & soaktime using dplyr::na_if()
# str_trim removes leading and tailing spaces on a string
harvest <- harv_in %>%
  mutate(
    location = str_trim(toupper(stri_enc_toutf8(location))),
    soaktime = ifelse(soaktime == 0 | soaktime == "NULL", NA, soaktime),
    pots = na_if(pots, 0),
    # correction to nocatch if shrimp > 0 
    nocatch = ifelse(shrimp > 0, 0, nocatch),
    catch = ifelse(nocatch == 1, "N", "Y"),
    hrvrpt = ifelse(nohrvrpt == 1, "N", "Y"),
    location = replace_na(location, "UNKNOWN"),
    month = month(harvdate),
    day = day(harvdate)
  ) %>%
  select(-c(nocatch, nohrvrpt, comments, stat_area))

# which dates failed to parse (if any)?
check_date <- harvest %>%
  filter(is.na(harvdate)) 

# in 2023 the harvest file was pretty clean, if not the case in the future,
# see harvest_v1.1 for procedures

# stat areas need to be merged in by location string, read in statarea file
statarea <- read_csv(
  str_c("location_statarea_updated_", year, ".csv"),
  locale = locale(encoding = "windows-1252")
  ) %>%
  clean_names()

str(statarea)

# make some small revisions - remove unnecessary spaces
correct_statarea <- statarea %>%
  mutate(
    location = str_trim(toupper(location)),
    statarea = str_trim(statarea)
  )

# create dataset without duplicates
uniq_correct_stat <- unique(correct_statarea) %>%
  filter(!is.na(location)) %>%
  arrange(location)

# try a merge 
harvest_1 <- left_join(harvest, uniq_correct_stat, by = "location")

# the SAS definition 
# which counts the number of Sundays
# see sas_r_week_check.R for weekly modification ID from SAS
# if the sas code has 
# WEEK = INTCK('WEEK',INTNX('YEAR', HARVDATE, 0), HARVDATE) + 1
# we need to use week = week(harvdate) - 1
harvest_2 <- harvest_1 %>%
  mutate(
    # try without round for now - gallons_per_pot = round(shrimp / pots),
    gallons_per_pot = shrimp / pots,
    pot_days = pots * (soaktime / 24),
    week = week(harvdate)
  ) %>%
  arrange(permitno, hvrecid)

# export for estimates program
write_csv(harvest_2, "shrimp_harvest.csv")

###################################################
#     DATA CHECKS 
###################################################
# get number of (count) locations in unique data 
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

# check for mailing discrepancies - semi_join looks for exact matches in both
check_har <- semi_join(harvest_2, statarea, by = "location")

# anti_join looks for values in harvest but not in statarea
check_onlyhar <- anti_join(harvest_2, statarea, by = "location")

# vice versa
onlyloc <- anti_join(statarea, harvest, by = "location")

# summarise locations that are only in harvest
check_harloc <- check_onlyhar %>%
  group_by(location) %>%
  summarise(freq = n()) %>%
  filter(freq > 1)

# get locations with multiple stat areas
check_mult_stat <- unique(mult_loc)

# check harvest dates to see if any need to be corrected
# in the harvest file
check_hardate <- harvest_2 %>%
  group_by(harvdate, week) %>%
  summarise(freq = n()) %>%
  arrange(harvdate)

# output checks to xlsx
# export to xlsx using a list of data sets and names
ck_list <- list(
  "check_hardate" = check_hardate,
  "only_harvest" = check_onlyhar,
  "multiple_stat" = mult_stat,
  "multiple_locations" = mult_loc
)

write_xlsx(
  ck_list,
  path = str_c("check_records_", year, ".xlsx")
)
