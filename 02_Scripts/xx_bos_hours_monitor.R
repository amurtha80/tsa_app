# BOS Checkpoint Hours Monitor (TEMPORARY)
#
# Polls the Zensors API's live `open` flag for each BOS checkpoint/lane and
# appends to the `bos_hours_monitor` DuckDB table (created 2026-07-20 via a
# direct Quack CREATE TABLE -- Quack's remote ATTACH connection supports
# CREATE TABLE/INSERT, it just doesn't show up in duckdb_tables()
# introspection). Purpose: derive real open/close hours per BOS checkpoint
# from ~2-4 weeks of live data, same pattern as JFK/LGA/EWR hours work.
#
# This is NOT a permanent part of the schema -- once BOS's
# airport_checkpoint_hours rows are set from this data, DROP TABLE
# bos_hours_monitor, delete this script, and remove the
# tsa_app_bos_hours_monitor scheduled task. See todo_list.txt.
#
# Deliberately named without a "_wait_times.R" suffix so
# scrape_data_automate.R's auto-discovery glob does not pick this up.

foo <- function(x) {
  for (i in x) {
    suppressWarnings(suppressPackageStartupMessages(
      if (!require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
        install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE,
                          repos = "https://cloud.r-project.org/")
        require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)
      }
    ))
  }
}
foo(c('httr2', 'jsonlite', 'duckdb', 'DBI', 'glue', 'tibble', 'purrr', 'dplyr', 'lubridate'))
rm(foo)

sink("C:/Users/james/Documents/R/tsa_app/runlog_bos_hours_monitor.txt", append = TRUE, type = "output")

print(glue::glue("kickoff BOS hours monitor ", format(Sys.time(), "%a %b %d %X %Y")))

# Checkpoint -> journey ID mapping ----
# Source: Zensors waitTimeExplorer.init response, confirmed live 2026-07-20
# (see 02_Scripts/BOS_scraper_PLAN.md). Hardcoded here since this is a
# temporary research script, not the production scraper.
bos_journeys <- tibble::tribble(
  ~checkpoint,                            ~journey,
  "Checkpoint 1: A Gates",                "t6CQ1P0Y3",
  "Checkpoint 2: A Gates PreCheck Only",  "tKK3PDVP9",
  "Checkpoint 3: Gates B1 - B22",         "tXT4B8KMX",
  "Checkpoint 4: Gates B23 - 40",         "tF1JP9828",
  "Checkpoint 5: Terminal C",             "tSGV88H0D",
  "Checkpoint 6: All E Gates",            "tWEBCSW2Q",
  "Checkpoint 7: All E Gates",            "tCLRGFHM9"
)

zensors_slug <- "tSTQVPRW1"
zensors_domain_slug <- "BOS"
zensors_token <- "9uBjlxUu2dTQydGHYGtoDYxH5TE0vHOl"

## Naive local-clock timestamp -- construct with tz = "UTC" so the DBI/duckdb
## write path does not silently shift it (see project_windows_task_scheduler_gotchas
## item 10; airport_checkpoint_hours-style columns store literal local-clock
## strings, not real UTC instants).
poll_time <- Sys.time() |>
  lubridate::with_tz(tzone = "America/New_York") |>
  format("%Y-%m-%d %H:%M:%S") |>
  lubridate::ymd_hms(tz = "UTC") |>
  lubridate::floor_date(unit = "minute")

get_checkpoint_status <- function(checkpoint, journey) {
  input <- list(`0` = list(journey = journey, slug = zensors_slug,
                            domainSlug = zensors_domain_slug, token = zensors_token))
  input_json <- jsonlite::toJSON(input, auto_unbox = TRUE)

  req <- httr2::request("https://embed.zensors.live/api/embeddable-widget/trpc/waitTimeExplorer.update") |>
    httr2::req_url_query(batch = 1, input = as.character(input_json))

  resp <- tryCatch(
    httr2::req_perform(req) |> httr2::resp_body_json(),
    error = function(e) {
      print(glue::glue("ERROR fetching {checkpoint}: {conditionMessage(e)}"))
      NULL
    }
  )

  if (is.null(resp)) return(tibble::tibble())

  paths <- resp[[1]]$result$data$paths
  if (is.null(paths)) return(tibble::tibble())

  purrr::imap_dfr(paths, function(lane_data, lane_name) {
    tibble::tibble(
      checkpoint = checkpoint,
      lane = lane_name,
      is_open = isTRUE(lane_data$open)
    )
  })
}

bos_hours_data <- purrr::map2_dfr(bos_journeys$checkpoint, bos_journeys$journey, get_checkpoint_status) |>
  dplyr::mutate(poll_time = poll_time)

if (nrow(bos_hours_data) > 0) {

  con_write <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(con_write, "INSTALL quack; LOAD quack;")
  DBI::dbExecute(con_write, glue::glue(
    "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
  ))
  DBI::dbExecute(con_write, "USE remote_db;")

  DBI::dbAppendTable(con_write, name = "bos_hours_monitor", value = bos_hours_data)

  print(glue::glue("{nrow(bos_hours_data)} appended to bos_hours_monitor at ",
                    format(Sys.time(), "%a %b %d %X %Y")))

  DBI::dbDisconnect(con_write, shutdown = TRUE)

} else {
  print(glue::glue("WARNING: no rows collected this cycle at ", format(Sys.time(), "%a %b %d %X %Y")))
}

rm(list = ls())
sink()
gc()
