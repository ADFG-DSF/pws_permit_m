#  rm(list = ls())

###############################################################################
# II.  Estimates
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

file_2 <- "shrimp_harvest"
file_3 <- "total_issued.csv"
file_4 <- "harvested.csv"
file_5 <- "final_estimates.csv"
file_6 <- str_c("shrimp_permits_", year, ".xlsx")


# Guessing BN = big N - consider a more informative naming structure
# get count of permits by mailing number
issued <- read_csv(str_c("issued_", year, ".csv")) %>%
  mutate(permfile = 1) %>%
  clean_names()

bn <- issued %>%
  count(mailing, name = "count") %>%
  mutate(percent = count * 100 / sum(count))

# the data set is transposed in SAS
# drop percent freq and mailing 9 for some reason
bn_1 <- bn %>%
  pivot_wider(
    names_from = "mailing",
    values_from = "count",
    id_cols = -"percent"
  ) %>%
  rename(
    bn_0 = "0",
    bn_1 = "1",
    bn_2 = "2"
  ) %>%
  select(-"9")

# shrimp_harvest is a dataset provided by Kirk so import as a .csv here
shrimp <- read_csv(str_c(file_2, "_", year, ".csv")) %>%
  clean_names() %>% 
  mutate(harvfile = 1) %>%
  rename(permit = permitno) %>%
  select(-"mailing")

# join files and replace nas with N - fishery might not be needed here
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

#check totals
all_permits %>%
  group_by(fishery) %>%
  summarise(tot_shrimp = sum(shrimp, na.rm = TRUE),
            tot_potdays = sum(pot_days, na.rm = TRUE))

#note, R handles NA values differently so coalesce() can be used to 
# replace NA with 0.
returned <- all_permits %>%
  filter(responded == "Y") %>%
  rename(oldfshry = fishery) %>%
  mutate(
    total = coalesce(shrimp, 0) + coalesce(pot_days, 0),
    compliant = ifelse(mailing <= 1, "Y", "N"),
    fished = ifelse(status == "DID NOT FISH" | status == "NON RESPONDENT",
                    "N", "Y")
  )

returned %>% 
  count(mailing) %>%
  mutate(percent = n * 100 / sum(n))

# number of permits that did not fish by getting data of unique permits using
# slice function
nofish <- returned %>%
  group_by(permit) %>%
  slice(1)

table(nofish$compliant)

nofish %>%
  group_by(fished, mailing) %>%
  count() 

# summarize total number by mailing and fished/nofish
nofishing <- nofish %>%
  group_by(fished, mailing) %>%
  summarise(count = n()) %>%
  mutate(percent = count / sum(count))

# get number of noncompliant permits that fished and didn't fished, i.e. 
# where mailing > 1.
nofishing2 <- nofish %>%
  filter(mailing > 1) %>%
  group_by(fished) %>%
  summarise(count = n()) %>%
  mutate(w_hat = count / sum(count))

# parameters needed for estimating nonresponse fishing in SAS from 
# noncompliant permits that fished - w_hat is p here (in SAS), i.e. n_df / n_d
fished_mailing <- nofishing2 %>% 
  filter(fished == "Y") %>%
  mutate(
    q = 1 - w_hat,
    n = count / w_hat,
    var_w_hat = ((w_hat * q) / (n - 1)) * ((n - count) / (n - 1)),
    se_w_hat = sqrt(var_w_hat)
  )

write_csv(fished_mailing, str_c(year, "_", file_3))

# this step might be needed later or may not
fished_mailing_1 <- fished_mailing %>%
  select(w_hat, var_w_hat, se_w_hat)

# returned permits that reported fishing
table(returned$fished)
table(returned$oldfshry)

harvested <- returned %>%
  filter(fished == "Y") %>%
  mutate(fishery = ifelse(oldfshry == "PWS", 1, NA)) %>%
  select(compliant, fishery, harvdate, mailing, oldfshry,
         permit, pot_days, shrimp, total)

# summarize harvests by permit number, fishery: shrimp, 
#  pot_days, & total.
# harvdate might cause problems if na so remove, all other variables should 
# be filled in as calculated previously
#  Added mailing in group_by as it might be needed later & doesn't change
# the results.  Add in na.rm = TRUE since some are NA values.
# shouldn't group_by columns that might have NA values
# use n_distinct() in dplyr to count distinct harvdate days
colSums(is.na(harvested))

harvested_1 <- harvested %>%
  group_by(permit, fishery, mailing, compliant) %>%
  summarise(
    days = n_distinct(harvdate),
    shrimp = sum(shrimp, na.rm = TRUE),
    pot_days = sum(pot_days, na.rm = TRUE),
    total = sum(total, na.rm = TRUE)
  )

table(harvested_1$mailing)

# check for missing values
table(is.na(harvested_1$pot_days))

harv_na <- harvested_1 %>%
  filter(is.na(pot_days))

table(is.na(harvested_1$shrimp))

table(is.na(harvested_1$total))

write_csv(harvested_1, str_c(year, "_", file_4))

# summarize numbers by permit now - keeping compliant & mailing as variables
# SAS data also has NA values but these appear to be ignored so ignore here
# as well
totalharv <- harvested_1 %>% 
  group_by(permit, compliant, mailing) %>%
  summarise(
    shrimp = sum(shrimp, na.rm = TRUE),
    pot_days = sum(pot_days, na.rm = TRUE),
    total = sum(total, na.rm = TRUE),
    harvdate = n()
  )
  
# SAS code has a summary check 
harvested_1 %>% group_by(fishery) %>%
  summarise(
    shrimp = sum(shrimp, na.rm = TRUE),
    pot_days = sum(pot_days, na.rm = TRUE),
    total = sum(total, na.rm = TRUE),
    harvdate = n()
  )

# summarise by permit number
fisheryharvest <- harvested_1 %>%
  group_by(permit, mailing, days, compliant) %>% 
  summarise(
    shrimp = sum(shrimp),
    pot_days = sum(pot_days),
    total = sum(total)
  ) 

# merge in the old variables - might not be needed yet
# fisheryharvest_1 <- left_join(fisheryharvest, harvested_1, by = "permit")
  
# transpose for some reason
fisherywide <- fisheryharvest %>%
  pivot_longer(
    c("days", "shrimp", "pot_days", "total"),
    names_to = "variable",
    values_to = "value"
  )

# check for missing values
fisherywide %>% filter(is.na(variable))

# SAS program looks for NA values and sets them to zero, if any do that here
fisherywide_1 <- fisherywide %>%
  mutate(
    value = replace_na(value, 0)
  )

fisherywide_1 %>%
  group_by(mailing) %>%
  count(mailing)

check_days <- fisherywide_1 %>% filter(variable == "days")

table(check_days$value)

# check for duplicates
dups <- duplicated(fisherywide_1$permit)

# count number of records fished without harvest
noharvest <- fisherywide_1 %>%
  filter(variable == "total", value == 0)

length(unique(noharvest$permit))

# summarize harvest by variable
bh <- fisherywide_1 %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(value, na.rm = TRUE),
    freq = n()
  )

# clean up
bh_1 <- bh %>%
  filter(variable != "total")

# summarise compliant harvest where mailing = 0
bh_v <- fisherywide_1 %>%
  filter(mailing == 0) %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(value, na.rm = TRUE),
    freq = n(),
    mean = mean(value)
  )

bh_v_1 <- bh_v %>%
  filter(variable != "total")

# mailing 1 harvest (first mailing)
bh_2 <- fisherywide_1 %>%
  filter(mailing == 1) %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(value, na.rm = TRUE),
    freq = n(),
    mean = mean(value)
  )

bh_3 <- bh_2 %>%
  filter(variable != "total")

# mailing = 2 harvest 
bh_4 <- fisherywide_1 %>%
  filter(mailing == 2) %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(value, na.rm = TRUE),
    freq = n(),
    mean = mean(value)
  )

bh_5 <- bh_4 %>%
  filter(variable != "total")

# compliant harvest 
bh_c <- fisherywide_1 %>%
  filter(compliant == "Y") %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(value, na.rm = TRUE),
    freq = n(),
    mean = mean(value)
  )

bh_c_1 <- bh_c %>%
  filter(variable != "total")

# check for permit discrepancies and compliant permits that are listed as
# noncompliant
check <- fisherywide_1 %>%
  filter(compliant == "N") %>%
  mutate(mailing_no = mailing)

# check for mailing discrepancies - semi_join looks for exact matches in both
check_mail <- semi_join(check, issued, by = "permit")

# anti_join looks for values in check but not in issued
onlypermit <- anti_join(check, issued, by = "permit")

# vice versa
onlycheck <- anti_join(issued, check, by = "permit")

# see if mailing numbers match
check_mail_1 <- check_mail %>%
  mutate(
    match_val = ifelse(mailing_no == mailing, "Y", "N")
  )

table(check_mail_1$match_val)

# Calculate noncompliant permits that fished - number, mean harvest, var, & se
lhb_d <- fisherywide_1 %>%
  filter(compliant == "N") %>%
  group_by(variable) %>%
  summarise(
    lhb_d_fished = n(),
    harv = sum(value, na.rm = TRUE),
    mean = mean(value, na.rm = TRUE), 
    var_mean = var(value, na.rm = TRUE),
    stdev = sd(value, na.rm = TRUE),
  ) %>%
  mutate(se = stdev / sqrt(lhb_d_fished))

# type will be used to merge in with another dataset
lhb_d_1 <- lhb_d %>%
  filter(variable != "total") %>%
  mutate(type = 1)

# USE FILE TOTISS FOR TOTAL NUMBER OF PERMITS ISSUED
# CALCULATE NUMBER OF NON-COMPLIANT PERMITS (BNH_D).
# ITS VARIANCE IS THE VARIANCE OF THE ESTIMATE OF THE NUMBER OF PERMITS ISSUED.;
# Martz: N (op plan) = NHAT;
total_issued <- read_csv(str_c(year, "_", file_3)) %>%
  clean_names() %>%
  rename(nhat = n) %>%
  mutate(
    var_nhat = 0
    )

# Martz: BNH_D_FISHED = N_hat_df in op plan
bnh_d <- cbind(
  select(total_issued, nhat,var_nhat),
  bn_1,
  fished_mailing_1
) %>%
  mutate(
    bnh_d = nhat - (bn_0 + bn_1),
    bnh_d_r = bnh_d - bn_2,
    bnh_d_fished = round(bnh_d * w_hat, 1),
    var_bnh_d_fished = (bnh_d ^ 2) * var_w_hat,
    type = 1
  )

# merge datasets together for estimating noncompliant nonrespondents
bhh_d <- full_join(lhb_d_1, bnh_d, by = "type") %>%
  select(
    variable, lhb_d_fished, mean, var_mean, bnh_d,
    bnh_d_fished, var_bnh_d_fished
  )

# Martz: BHH_D (or BHH1 in output) = H_hat_df from op plan;
# calculate variances etc.
bhh_d_1 <- bhh_d %>%
  mutate(
    #bhh_d is est. harvest from mean of noncompliant permits fished
    bhh_d = bnh_d_fished * mean,
    vlhb_d = ((bnh_d_fished - lhb_d_fished) / (bnh_d_fished - 1)) *
      (var_mean / lhb_d_fished),
    vhh = (bnh_d_fished ^ 2 * vlhb_d) + (mean ^ 2 * var_bnh_d_fished) -
      (vlhb_d * var_bnh_d_fished),
    se = sqrt(vhh)
  )

bhh_d_2 <- bhh_d_1 %>%
  select(variable, mean, bnh_d_fished, bhh_d, vhh, se)

# CONCATENATE THE COMPLIANT FILE (BH_C), THE NON-COMPLIANT-RESPONDED FILE (LHB_D) 
# AND THE NON-COMPLIANT-NON-RESPONDED FILE (BHH_D). RENAME THE VARIABLES IN 
# THE COMPLIANT FILE SO THEY MATCH THE NAMES OF THE EQUIVALENT NON-COMPLIANT 
# VARIABLES;
# Martz: BHH1 = H_cf from op plan;

bh_x <- bind_rows(
  bh_c_1 %>% select(-freq) %>% 
    rename(bhh_1 = harvest) %>%
    mutate(group = 'compliant'),
  bhh_d_2 %>% select(-bnh_d_fished) %>%
    rename(bhh_1 = bhh_d) %>% 
    mutate(group = 'noncompliant')
) %>%
  select(-mean)

# sum compliant & noncompliant harvest and SE to get rounded totals
bhh <- bh_x %>%
  group_by(variable) %>%
  summarise(
    harvest = sum(bhh_1, na.rm = TRUE),
    se = sum(se, na.rm = TRUE)
  ) %>%
  mutate(across(where(is.numeric), round, 0))

#export
write_csv(bh, str_c(year, "_", file_5))

bh_out <- bh %>%
  rename(
    reported_harvest_pws = harvest,
    number_returned_permits_fished = freq
  ) %>% 
  filter(variable != 'total')

bhh_out <- bhh %>%
  rename(
    estimated_harvest_pws = harvest,
    pws_harvest_se = se
  )

# export to xlsx
write_xlsx(
  list(
    reported_harvest = bh_out,
    expanded_harvest = bhh_out
  ), file_6
)


################################################################
#     THE END
#################################################################