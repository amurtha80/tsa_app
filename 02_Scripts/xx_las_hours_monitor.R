# LAS Checkpoint Hours Monitor (TEMPORARY)
#
# Polls the Zensors API's live `open` flag for each LAS checkpoint/lane and
# appends to the `las_hours_monitor` DuckDB table (created 2026-07-22 via a
# direct Quack CREATE TABLE -- Quack's remote ATTACH connection supports
# CREATE TABLE/INSERT, it just doesn't show up in duckdb_tables()
# introspection). Purpose: derive real open/close hours per LAS checkpoint
# from ~2-4 weeks of live data, same pattern as BOS's hours-monitor.
#
# This is NOT a permanent part of the schema -- once LAS's
# airport_checkpoint_hours rows are set from this data, DROP TABLE
# las_hours_monitor, delete this script, and remove the
# tsa_app_las_hours_monitor scheduled task. See todo_list.txt.
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

sink("C:/Users/james/Documents/R/tsa_app/runlog_las_hours_monitor.txt", append = TRUE, type = "output")

print(glue::glue("kickoff LAS hours monitor ", format(Sys.time(), "%a %b %d %X %Y")))

# Checkpoint -> journey ID mapping ----
# Source: Zensors waitTimeExplorer.init response, confirmed live 2026-07-22
# (see 02_Scripts/LAS_scraper_PLAN.md). Hardcoded here since this is a
# temporary research script, not the production scraper.
las_journeys <- tibble::tribble(
  ~checkpoint,           ~journey,
  "T1 - A/B Gates",      "t2K25H6KA",
  "T1 - C Gates",        "tN8G8AV9D",
  "T1 - C/D Gates",      "tGMD2ET8Y",
  "T3 - D/E Gates",      "t0CSXP4SK"
)

zensors_slug <- "t1LQGTAPA"
zensors_domain_slug <- "LAS"
zensors_token <- "3Ll9yq2riLZctX1CZ94FRgLcScJimgXx"

## Naive local-clock timestamp -- construct with tz = "UTC" so the DBI/duckdb
## write path does not silently shift it (see project_windows_task_scheduler_gotchas
## item 10; airport_checkpoint_hours-style columns store literal local-clock
## strings, not real UTC instants).
poll_time <- Sys.time() |>
  lubridate::with_tz(tzone = "America/Los_Angeles") |>
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

  # Read the `open` flag directly per lane -- defensive against a lane key
  # (precheck/standard) being absent entirely, same convention as the
  # production scraper's lane_wait() helper. Do NOT infer open/closed from
  # wait_time value (e.g. 0 minutes does not mean closed).
  purrr::imap_dfr(paths, function(lane_data, lane_name) {
    tibble::tibble(
      checkpoint = checkpoint,
      lane = lane_name,
      is_open = isTRUE(lane_data$open)
    )
  })
}

las_hours_data <- purrr::map2_dfr(las_journeys$checkpoint, las_journeys$journey, get_checkpoint_status) |>
  dplyr::mutate(poll_time = poll_time)

if (nrow(las_hours_data) > 0) {

  con_write <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(con_write, "INSTALL quack; LOAD quack;")
  DBI::dbExecute(con_write, glue::glue(
    "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
  ))
  DBI::dbExecute(con_write, "USE remote_db;")

  DBI::dbAppendTable(con_write, name = "las_hours_monitor", value = las_hours_data)

  print(glue::glue("{nrow(las_hours_data)} appended to las_hours_monitor at ",
                    format(Sys.time(), "%a %b %d %X %Y")))

  DBI::dbDisconnect(con_write, shutdown = TRUE)

} else {
  print(glue::glue("WARNING: no rows collected this cycle at ", format(Sys.time(), "%a %b %d %X %Y")))
}

rm(list = ls())
sink()
gc()
