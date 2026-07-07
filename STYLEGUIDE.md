# FlyASAP Coding Style & Blueprints

## General Conventions
- Use `snake_case` for all variable and function names.
- Comment code layout sections with `# Section Name ----` (four dashes) to enable RStudio/Positron outline navigation.
- Always use `here::here()` for file paths. Never hardcode absolute paths.
- Suppress noisy package startup messages: `library(package, verbose = FALSE, warn.conflicts = FALSE)`.
- Use explicit `tryCatch()` loops for external actions. Add cleanup blocks at the end of scripts using `rm()` and database disconnections.

## R Style & Native Pipes
- **Existing Code:** Leave magrittr `%>%` as-is. Do not refactor it.
- **New Code:** Always use the native pipe `|>`.
  - The RHS must be an explicit function call: use `sqrt()` not `sqrt`.
  - No magrittr dot (`.`) syntax allowed. Use anonymous functions instead: `\(x)` or `\(.)`.
  - *Example:* `mtcars |> (\(x) plot(x$hp, x$mpg))()`
- Prefer `dplyr` verbs over base R for mutations. Use `glue()` for string interpolation.
- Use `readr::parse_number()` for parsing scraped numbers; explicitly record timezones in `lubridate` tibbles.

## Scraping Function Pattern
All airport scraping functions must follow this pattern and be named `scrape_tsa_data_{airport_code}`:

```r
scrape_tsa_data_lax <- function() {
  # 1. Kickoff print
  print(glue("kickoff lax scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # 2. Define URL / session / local chrome check
  # chromote::local_chrome_version() inside function
  
  # 3. Scrape page and extract elements
  
  # 4. Initialize or retrieve existing data tibble
  
  # 5. Append new rows to tibble (use rows_append())
  
  # 6. Assign back to global environment
  assign("lax_data", current_tibble, envir = .GlobalEnv)
  
  # 7. Write to database
  # dbAppendTable(con_write, ...)
  
  # 8. Print confirmation
  print(glue("{nrow(current_tibble)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # 9. Cleanup via tryCatch/finally teardown
  # page$session$close() -> page$session$parent$close(wait=3)
  # chromote::set_default_chromote_object(NULL)
  # rm() intermediate objects
}
```

## Shiny UI & Server Style
- Framework is **bslib with Bootstrap 5** (mobile-responsive by default). Do not use shinyMobile.
- Use `page_sidebar()`, `card()`, `value_box()`, `layout_columns()`, and `bs_theme(version = 5)`.
- Use `bslib` theming options directly over inline CSS blocks wherever possible.
- No business or data transformation logic inside UI definitions. Keep UI and server logic cleanly separated.
- Descriptive inputs: Use `input$select_airport`, `input$select_day`, not generic indices like `input$select1`.
- Keep reactives laser-focused: one single transformation unit per reactive function.
- Match `output$` naming syntax to mirror their input context (e.g., matching pairs of `renderText()` / `renderPlot()` / `renderTable()`).
- Default ggplot2 theme for visual components is always `theme_minimal()`.