# test out different ways of assigning week
# read in 2023 calendar
# 2023_calendar.csv is just an excel file of all 365 dates
yearly_cal <- read_csv("2023_calendar.csv")

str(yearly_cal)

yearly_cal_wk <- yearly_cal %>%
  mutate(
    date = mdy(date),
    day_ofmonth = day(date),
    julian_date = julian(date, 
                         origin = as.Date("2023-01-01")),
    week_day = wday(date, label = TRUE),
    week = week(date),
    iso_week = isoweek(date),
    epi_week = epiweek(date)
  )

# this portion was done in week_check.sas located at:
# O:\DSF\RTS\common\Pat\Permits\Shrimp\2023
sas_wk <- read_csv("sas_week.csv") %>%
  clean_names() %>%
  mutate(date = mdy(date)) 

str(sas_wk)

r_sas_cal <- left_join(yearly_cal_wk, sas_wk)

# sas is returning week starting at 0 so try to refine and see if there 
# is still a difference 
# week() = INTCK('WEEK',INTNX('YEAR', HARVDATE, 0), HARVDATE) + 1
# keep an eye out for whether the SAS program has + 1
r_sas_diff <- r_sas_cal %>%
  mutate(
    week2 = week,
    epiweek2 = epi_week,
    sas_wk_diff = sas_week - week2,
    sas_epi_diff = sas_week - epiweek2
  )

sum(r_sas_diff$sas_wk_diff)
sum(r_sas_diff$sas_epi_diff)

# it looks like when you subtract 1 from week and compare with 
# sas week, you match up the week designations.

# harvest_4.sas7bdat is where weeks are assigned in PWS, see if we can match
harv_4sas <- read_csv("harvest_4.csv") %>%
  clean_names() %>%
  mutate(
    date = mdy(harvdate),
    rweek = week(date)
  )

sas_effort_wk <- harv_4sas %>%
  group_by(week) %>%
  summarise(pot_days = sum(pot_days, na.rm = TRUE)) %>%
  mutate(percent = pot_days * 100 / sum(pot_days, na.rm = TRUE))

sas_shrimp_wk <- harv_4sas %>%
  group_by(week) %>%
  summarise(shrimp = sum(shrimp, na.rm = TRUE)) %>%
  mutate(percent = shrimp * 100 / sum(shrimp, na.rm = TRUE))

sas_r_shrimp <- harv_4sas %>%
  group_by(rweek) %>%
  summarise(shrimp = sum(shrimp, na.rm = TRUE)) %>%
  mutate(percent = shrimp * 100 / sum(shrimp, na.rm = TRUE))


# week is a problem, pull out all records where it is week 16
wk_16 <- harvested %>%
  filter(week == 16)

wk_16_ct <- wk_16 %>%
  group_by(harvdate) %>%
  summarise(
    freq = n()
  )

wk_16a <- shrimp %>%
  filter(week == 16)

wk_16_ct <- wk_16a %>%
  group_by(harvdate) %>%
  summarise(
    freq = n()
  )

wk_shrimp <- shrimp %>%
  mutate(wk_1 = week(harvdate))

wk_16a <- wk_shrimp %>%
  filter(wk_1 == 16)

wk_16_ct <- wk_16a %>%
  group_by(harvdate) %>%
  summarise(
    freq = n()
  )
