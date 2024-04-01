#  rm(list = ls())

###############################################################################
# II.  Estimates_v1.3
#  This program is for getting estimation of harvest, etc.
###############################################################################

library(tidyverse)
library(magrittr)
library(janitor)
library(writexl)

# set up a file directory name for repeat use
# edit each year as necessary if the year &/or file name changes
# These files are named in the order they are called, these are akin
# to the macro variables SAS uses
year <- "2023"

file_1 <- str_c("permit_file_", year, ".csv")
file_2 <- str_c("shrimp_harvest_", year, ".csv")
file_3 <- "shrimp_permits_"

# read in permits issued & add permfile identifier
issued <- read_csv(str_c(file_1, year, ".csv")) %>%
  mutate(permfile = 1) %>%
  clean_names()

# number of responses by mailing number
mailing <- issued %>%
  count(mailing) %>%
  mutate(percent = n * 100 / sum(n))

#summarize responses by fishing status
summary_response <- issued %>%
  count(status, responded) %>%
  mutate(percent = n * 100 / sum(n))

# shrimp_harvest is a dataset provided by Kirk so import as a .csv here
shrimp_harv <- read_csv(str_c(file_2, "_", year, ".csv")) %>%
  clean_names() 

# add identifier for harvest file 
shrimp <- shrimp_harv %>% 
  mutate(harvfile = 1) %>%
  rename(permit = permitno) %>%
  select(-"mailing")

# join files and replace NA with N - fishery might not be needed here
all_permits <- left_join(issued, shrimp, by = "permit") %>%
  mutate(
    responded = replace_na(responded, "N"),
    fishery = "PWS"
  )

# check for permits in harvest file but not permit file
filter(all_permits, harvfile == 1 & is.na(permfile))

# get responses, calculate total = shrimp + pot_days,
# add in compliant and fished/not
table(all_permits$status)

#note, R handles NA values differently so coalesce() can be used to 
# replace NA with 0. All permits that responded to any mailing.
returned <- all_permits %>%
  filter(responded == "Y") %>%
  rename(oldfshry = fishery) %>%
  mutate(
    shrimp = coalesce(shrimp, 0),
    pot_days = coalesce(pot_days, 0),
    total = shrimp + pot_days,
    compliant = ifelse(mailing <= 1, "Y", "N"),
    fished = ifelse(status == "DID NOT FISH" | status == "NON RESPONDENT",
                    "N", "Y")
  )

any(is.na(returned$shrimp))
any(is.na(returned$pot_days))

# returned permits that reported fishing
# assign week here since that might work better
harvested <- returned %>%
  filter(fished == "Y") %>%
  mutate(
    fishery = ifelse(oldfshry == "PWS", 1, NA),
    week = week(harvdate)
  ) %>%
  select(compliant, fishery, harvdate, mailing, oldfshry,
         permit, pot_days, shrimp, total, statarea, week)

# to get days we need to summarise by permit and harvest date
harvested_1 <- harvested %>%
  group_by(permit, harvdate) %>%
  summarise(
    num_trips = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  )

# get the number of days per permit
fisheryharvest <- harvested_1 %>%
  group_by(permit) %>%
  summarise(
    days = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  )

# summarize into reported harvest (includes compliant/noncompliant fished)
reported_har <- fisheryharvest %>%
  summarise(
    days = sum(days),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days),
    num_permits = n()
  )

# harvest and effort by statarea 
stat_har <- harvested %>%
  group_by(statarea) %>%
  summarise(
    n = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  ) %>%
  mutate(
    percent_har = shrimp * 100 / sum(shrimp),
    percent_effort = pot_days * 100 / sum(pot_days)
  ) %>%
  select(statarea, shrimp, percent_har, pot_days, percent_effort)

# harvest and effort by week
week_har <- harvested %>%
  group_by(week) %>%
  summarise(
    n = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  ) %>%
  mutate(
    percent_har = shrimp * 100 / sum(shrimp),
    percent_effort = pot_days * 100 / sum(pot_days)
  ) %>%
  select(week, n, shrimp, percent_har, pot_days, percent_effort)

#################################
## EFFORT & NUMBERS OF PERMITS ## 
#################################

# Tabulate N - total permits issued
permits <- issued

effort_har_numbers <- tibble(
  N = length(unique(permits$permit))
)

# Get N_cf - the number of compliant households reported fishing
# need unique permits from returned
ret_uniq <- distinct(returned, permit, .keep_all = TRUE)

permits_returned <- ret_uniq %>%
  group_by(compliant, fished) %>%
  summarise(n = n())

# count reported/not reported fishing by mailing
fished_mailing <- ret_uniq %>%
  group_by(fished, mailing) %>%
  summarise(n = n())

# compliant permit numbers - sum fished / nofished
comp_mail <- fished_mailing %>%
  filter(mailing == 0 | mailing == 1) %>%
  group_by(fished) %>%
  summarise(N_c = sum(n))

# noncompliant mailing = 2 - 
noncomp_mail <- ret_uniq %>%
  filter(mailing == 2) %>%
  group_by(fished) %>%
  summarise(n = n()) %>%
  mutate(percent = n / sum(n))

# add into dataset effort_har_numbers
# variable names are directly from the op-plan
# variance calculation includes FPC
effort_har_numbers_1 <- effort_har_numbers %>%
  mutate(
    N_cf = unlist(filter(comp_mail, fished == "Y") 
                  %>% select(N_c)),
    N_cz = unlist(filter(comp_mail, fished == "N") 
                  %>% select(N_c)),
    n_df = unlist(filter(noncomp_mail, fished == "Y")
                  %>% select(n)),
    n_d = sum(noncomp_mail$n),
    w_hat = unlist(filter(noncomp_mail, fished == "Y")
                   %>% select(percent)),
    var_w_hat = ((w_hat * (1 - w_hat)) / (n_d - 1)) *
      ((n_d - n_df) / (n_d - 1)),
    se_w_hat = sqrt(var_w_hat),
    N_hat_df = round((N - (N_cf + N_cz)) * w_hat, 0),
    var_N_hat_df = (N - (N_cf + N_cz))^2 *
      var_w_hat,
    N_hat_dz = round(N - (N_cf + N_cz + N_hat_df), 0)
  ) %>%
  select(N, N_cf, N_cz, N_hat_dz, N_hat_df, var_N_hat_df, 
         n_df, n_d, w_hat, var_w_hat, se_w_hat)

###########################
#   HARVEST ESTIMATION    #
###########################

# First step is to get mean harvest per HH for non compliant permits
# that reported fishing, h_bar_df
noncomp_har <- harvested %>%
  filter(compliant == "N")

# to get number of days we need to summarise by permit and harvest date
noncomp_har_1 <- noncomp_har %>%
  group_by(permit, harvdate) %>%
  summarise(
    num_trips = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  )

# get the number of days per permit
noncomp_fisheryhar <- noncomp_har_1 %>%
  group_by(permit) %>%
  summarise(
    days = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  )

# we want to group by variable so pivot_longer
noncomp_fisheryhar_1 <- noncomp_fisheryhar %>%
  pivot_longer(cols = c(days, shrimp, pot_days),
               names_to = "variable")

# summarize into noncompliant reported harvest
# and add in estimates of noncompliant not reported
noncomp_h_df <- noncomp_fisheryhar_1 %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(value),
    s2_df = var(value),
    h_bar_df = mean(value),
    n_df = n()
  ) %>%
  # this is estimation of noncompliant not-reported
  mutate(
    var_hbar_df = (1 - (n_df / effort_har_numbers_1$N_hat_df)) *
      (s2_df / n_df),
    H_hat_df = effort_har_numbers_1$N_hat_df * h_bar_df,
    var_hhat_df = effort_har_numbers_1$N_hat_df^2 *
      var_hbar_df + h_bar_df^2 * effort_har_numbers_1$var_N_hat_df -
      var_hbar_df * effort_har_numbers_1$var_N_hat_df,
    se_hhat_df = sqrt(var_hhat_df)
  )

# Now calculate the compliant component of harvest
compliant_har <- harvested %>%
  filter(compliant == "Y")

# to get days we need to summarise by permit and harvest date
compliant_har_1 <- compliant_har %>%
  group_by(permit, harvdate) %>%
  summarise(
    num_trips = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  )

# get the number of days per permit
compliant_fisheryhar <- compliant_har_1 %>%
  group_by(permit) %>%
  summarise(
    days = n(),
    shrimp = sum(shrimp),
    pot_days = sum(pot_days)
  )

# we want to group by variable so pivot_longer
compliant_fisheryhar_1 <- compliant_fisheryhar %>%
  pivot_longer(cols = c(days, shrimp, pot_days),
               names_to = "variable")

# summarize into noncompliant reported harvest
# and add in estimates of noncompliant not reported
# H_cf in the op-plan
compliant_h_cf <- compliant_fisheryhar_1 %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(value)
  ) 

# Combine noncompliant & compliant to get expanded results
comp_noncomp <- bind_rows(compliant_h_cf, 
                          select(noncomp_h_df, c(variable,
                                 H_hat_df, se_hhat_df)) %>%
                            rename(harvest = H_hat_df))

expanded_harvest <- comp_noncomp %>%
  group_by(variable) %>%
  summarise(
    across(harvest:se_hhat_df, \(x) sum(x, na.rm = TRUE))
  )

# export to xlsx using a list of data sets and names
ds_list <- list(
  "total_issued" = effort_har_numbers,
  "mailing_summary" = mailing,
  "summary_response" = summary_response,
  "effort_har_statarea" = stat_har,
  "effort_har_week" = week_har,
  "reported_harvest" = reported_har,
  "expanded_harvest" = expanded_harvest
)

write_xlsx(
  ds_list,
  path = str_c(file_3, year, ".xlsx")
)
