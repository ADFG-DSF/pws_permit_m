#  rm(list = ls())

#############################################################################
# I. Permits_v1.1
#  This program is basically for cleaning the permits file pwspmc and 
# getting things ready for estimation.
#
#  6/23: Revise folder structure to pull from project folder with year rather 
# than from the network drive.  Also revised to remove 'macro' designations
# since things change year to year. In 2023, process for data import changed
# since new procedures were implemented by data entry.
##############################################################################

library(tidyverse)
library(magrittr)
library(janitor)
library(writexl)

#revise year to match correct year
year <- "2023"

# pwspmc is the main shrimp permit data provided by data entry
# also - in 2023 - response_method was titled reponse_method
import <- read_csv(str_c("pwspmc_", year, ".csv")) %>%
  clean_names() %>%
  rename(response_method = reponse_method)

###############################################################################

# The next data is the revised version provided by AMB and the next 
# steps can be ignored
# until that file is provided

data_rev <- read_csv(str_c("pwspmc_", year, "_final.csv")) %>%
  clean_names() 

# check to see if the column names are the same, if so move to issued
compare_df_cols_same(import, data_rev)

# issued_a <- left_join(data_rev, import, by = "permitno")

# make sure the row numbers are the same

issued <- data_rev %>%
  mutate(permit = permitno) %>%
  rename(s = status)

###############################################################################

# if the revised version is used this step can be skipped - otherwise 1st run
# use this code

issued <- import %>%
  mutate(permit = permitno) %>%
  rename(s = status) %>%
  remove_empty()

###############################################################################

# Status, vendorcopy, responded, allowed are new variables
issued_1 <- issued %>%
  mutate(
    status = case_when(
      s == "U" ~ "BLANK REPORT",
      s == "N" ~ "DID NOT FISH",
      s == "H" ~ "HARVEST REPORTED",
      s == "Z" ~ "NON RESPONDENT"
    ),
    resident = case_when(
      ar == 1 ~ "Y",
      nr == 1 ~ "N"
    ),
    vendorcard = ifelse(novendcard == 0, "Y", "N"),
    office = replace_na(office, "NULL"),
    responded = ifelse(s == "Z", "N", "Y"),
    check = sport + peruse + subsistence
  )

issued_2 <- issued_1 %>%
  mutate(
    use = case_when(
      check == 1 & sport == 1 ~ "SPORT",
      check == 1 & peruse == 1 ~ "PERSONAL",
      check == 1 & subsistence == 1 ~ "SUBSISTENCE",
      check == 0 ~ "BLANK"
    )
  ) %>%
  select(last_name, first_name, city, state, adlno, hhmembers,
         mailing, lostpots, response_method:responded, use)

#summarize responses by fishing status
summary_response <- issued_2 %>%
  count(status, responded) %>%
  mutate(percent = n * 100 / sum(n))

# number of responses by mailing number
mailing <- issued_2 %>%
  count(mailing) %>%
  mutate(percent = n * 100 / sum(n))

# in the SAS code this dataset is saved to the folder on the anchorage drive
# the file name for this is 'personal' as in the SAS code - no need for this
# so we will not write to csv 6/23
personal <- issued_2 %>%
  select(permit, adlno, city, state, first_name, last_name, use, resident)

issued_3 <- issued_2 %>%
  select(-c(adlno, city, state, first_name, 
            last_name, hhmembers, use, resident)
            )

# Get total number of issued permits
total_issued <- tibble(
  N = length(unique(issued_3$permit))
)

# estimates pulls in the issued file, so export here
write_csv(issued_3, str_c("issued_", year, ".csv"))

# SAS program has this written as a file to the server folder
write_csv(total_issued, str_c("total_issued_", year, ".csv"))

comments <- import %>%
  filter(comments != 'NULL') %>%
  select(permitno, comments)

# export to xlsx using a list of data sets and names
ds_list <- list(
  "permit_comments" = comments,
  "mailing_summary" = mailing,
  "summary_response" = summary_response,
  "permit_records" = issued_3,
  "total_issued" = total_issued
)

write_xlsx(
  ds_list,
  path = str_c("shrimp_permits_", year, ".xlsx")
)
