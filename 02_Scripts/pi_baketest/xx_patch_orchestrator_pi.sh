#!/bin/bash
# Run this ON THE PI (not the dev machine) from inside ~/pi_baketest.
# Adds JFK/ATL sourcing + scraper registration to the flat-layout orchestrator copy.
set -e
cd ~/pi_baketest

sed -i 's|source(here::here("LGA_wait_times_pi.R"))|source(here::here("LGA_wait_times_pi.R"))\nsource(here::here("JFK_wait_times_pi.R"))\nsource(here::here("ATL_wait_times_pi.R"))|' xx_baketest_orchestrator.R

sed -i '/^scrapers <- list(/,/^)/{s|EWR = scrape_tsa_data_ewr$|EWR = scrape_tsa_data_ewr,\n  JFK = scrape_tsa_data_jfk,\n  ATL = scrape_tsa_data_atl|}' xx_baketest_orchestrator.R

echo "--- patched file (relevant lines) ---"
grep -n 'source(here::here("...*_wait_times_pi.R"))\|^scrapers\|scrape_tsa_data' xx_baketest_orchestrator.R
