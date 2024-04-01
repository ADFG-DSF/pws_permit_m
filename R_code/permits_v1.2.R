#  rm(list = ls())

#############################################################################
# I. Permits_v1.2
#  This program is basically for cleaning the permits file pwspmc and 
# getting things ready for estimation.
#
#  6/23: Revise folder structure to pull from project folder with year rather 
# than from the network drive.  Also revised to remove 'macro' designations
# since things change year to year. In 2023, process for data import changed
# since new procedures were implemented by data entry.
#
# 3/5/24 - revise script to simplify and build data
##############################################################################

library(tidyverse)
library(magrittr)
library(janitor)
library(writexl)

#revise year to match correct year
year <- "2023"

# pwspmc is the main shrimp permit data provided by data entry
# also - in 2023 - response_method was titled reponse_method
pwspmc <- read_csv(str_c("pwspmc_", year, ".csv")) %>%
  clean_names() %>%
  rename(response_method = reponse_method)

# remove empty and rename status
issued <- pwspmc %>%
  remove_empty() %>% 
  mutate(permit = permitno) %>%
  rename(s = status)

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

# add in uses from checks added earlier
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

# remove vars prior to export
issued_3 <- issued_2 %>%
  select(-c(adlno, city, state, first_name, 
            last_name, hhmembers, use, resident, vendorcard)
  )

# export for harvest and estimation programs
write_csv(issued_3, str_c("permit_file_", year, ".csv"))


