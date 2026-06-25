# app.R ----
# ASAP — Airport Security Advance Planning
# Shiny app wired to tsa_app_summ.duckdb (read-only).
# UI layout mirrors app3shinyassistant.R, rebuilt in bslib + Bootstrap 5.
# Chart logic ported from xx_chart_times.R.
#
# UI: bslib + Bootstrap 5 (mobile-responsive via Bootstrap grid)
# DB: tsa_app_summ.duckdb — written nightly by xx_build_summary_db.R


# Libraries ----

library(shiny,      verbose = FALSE, warn.conflicts = FALSE)
library(bslib,      verbose = FALSE, warn.conflicts = FALSE)
library(duckdb,     verbose = FALSE, warn.conflicts = FALSE)
library(DBI,        verbose = FALSE, warn.conflicts = FALSE)
library(dplyr,      verbose = FALSE, warn.conflicts = FALSE)
library(ggplot2,    verbose = FALSE, warn.conflicts = FALSE)
library(ggrounded,  verbose = FALSE, warn.conflicts = FALSE)
library(hms,        verbose = FALSE, warn.conflicts = FALSE)
library(lubridate,  verbose = FALSE, warn.conflicts = FALSE)
library(glue,       verbose = FALSE, warn.conflicts = FALSE)
library(here,       verbose = FALSE, warn.conflicts = FALSE)


# Database ----
# TODO (shinyapps.io deployment): replace here::here() path with a path
# relative to the app bundle, e.g. file.path("01_Data", "tsa_app_summ.duckdb")

db_path  <- here::here("01_Data", "tsa_app_summ.duckdb")
con_summ <- dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

summ_data <- tbl(con_summ, "tsa_wait_time_summ") |>
  collect() |>
  mutate(bucket_time = hms::as_hms(bucket_time))

dbDisconnect(con_summ, shutdown = TRUE)
rm(con_summ, db_path)


# Derived UI inputs ----
# Choices built from summary data so dropdowns always reflect what is in the DB.

airport_choices <- sort(unique(summ_data$airport))
weekday_choices <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

# 15-minute time slots across the full day (96 slots)
time_slots <- format(
  seq(as.POSIXct("2000-01-01 00:00:00"),
      as.POSIXct("2000-01-01 23:45:00"),
      by = "15 min"),
  "%H:%M"
)


# Theme ----

app_theme <- bs_theme(
  version    = 5,
  bootswatch = "flatly",
  primary    = "#007aff"
)


# UI ----

ui <- page_navbar(
  title        = "ASAP - Airport Security Advance Planning",
  theme        = app_theme,
  window_title = "ASAP",
  bg           = "#007aff",
  
  # Right-side options nav item — mirrors f7Panel side="right"
  nav_spacer(),
  nav_panel(
    title = "Options",
    icon  = icon("gear"),
    
    br(),
    fluidRow(
      column(
        width = 6, offset = 3,
        card(
          card_header("App Options"),
          radioButtons(
            inputId  = "dark_mode",
            label    = "App Mode",
            choices  = c("Light" = "light", "Dark" = "dark"),
            selected = "light",
            inline   = TRUE
          )
        )
      )
    )
  ),
  
  # Main search + chart panel ----
  nav_panel(
    title = "Search",
    
    br(),
    
    # Page title — mirrors f7Align + f7BlockTitle
    fluidRow(
      column(
        width = 12,
        h3(
          "Saving Some Time on Your Travel Day",
          style = "text-align: center; font-weight: 600;"
        )
      )
    ),
    
    br(),
    
    # Description block — mirrors f7Block inset outline
    fluidRow(
      column(
        width = 10, offset = 1,
        card(
          class = "border",
          p(
            "Something about the purpose of the app. Continue by telling
            the user how to navigate the app and what you will get after
            choosing the search criteria.",
            style = "margin: 0;"
          )
        )
      )
    ),
    
    br(),
    
    # Airport + checkpoint search — mirrors f7Block with f7AutoComplete
    fluidRow(
      column(
        width = 10, offset = 1,
        card(
          class = "border",
          card_header(
            h5("Airport Search", style = "text-align: center; margin: 0;")
          ),
          selectizeInput(
            inputId  = "select_airport",
            label    = "Type or select an Airport Code:",
            choices  = airport_choices,
            selected = airport_choices[1],
            options  = list(placeholder = "e.g. ATL"),
            width    = "100%"
          ),
          selectInput(
            inputId = "select_checkpoint",
            label   = "Checkpoint:",
            choices = NULL,       # populated server-side on airport selection
            width   = "100%"
          )
        )
      )
    ),
    
    br(),
    
    # Day + time selectors — mirrors f7Grid(cols = 2) with two f7Cards
    fluidRow(
      column(
        width = 5, offset = 1,
        card(
          class = "border",
          card_header("Day of Week Selection"),
          selectInput(
            inputId  = "select_day",
            label    = "Choose a Day of the Week:",
            choices  = weekday_choices,
            selected = "Mon",
            width    = "100%"
          )
        )
      ),
      column(
        width = 5,
        card(
          class = "border",
          card_header("Time Slot Selection"),
          selectInput(
            inputId  = "select_time",
            label    = "Choose a Time (15-min slot):",
            choices  = time_slots,
            selected = "08:00",
            width    = "100%"
          )
        )
      )
    ),
    
    fluidRow(
      column(
        width = 10, offset = 1,
        helpText(
          style = "text-align: center;",
          "Chart shows \u00b11 hour around selected time (9 bars \u00d7 15 min)."
        )
      )
    ),
    
    br(),
    
    # Standard lane chart
    fluidRow(
      column(
        width = 10, offset = 1,
        card(
          card_header("Standard Lane \u2014 Average Wait Time (min)"),
          plotOutput("chart_std", height = "380px")
        )
      )
    ),
    
    br(),
    
    # TSA Pre-check lane chart
    fluidRow(
      column(
        width = 10, offset = 1,
        card(
          card_header("TSA Pre\u2713 Lane \u2014 Average Wait Time (min)"),
          plotOutput("chart_pre", height = "380px")
        )
      )
    ),
    
    br()
  )
)


# Server ----

server <- function(input, output, session) {
  
  
  # Dark mode toggle ----
  
  observeEvent(input$dark_mode, ignoreInit = TRUE, {
    session$setCurrentTheme(
      if (input$dark_mode == "dark") {
        bs_theme_update(app_theme, bg = "#222", fg = "#fff")
      } else {
        app_theme
      }
    )
  })
  
  
  # Update checkpoint choices when airport changes ----
  
  observeEvent(input$select_airport, {
    checkpoints_for_airport <- summ_data |>
      filter(airport == input$select_airport) |>
      pull(checkpoint) |>
      unique() |>
      sort()
    
    updateSelectInput(session,
                      inputId  = "select_checkpoint",
                      choices  = checkpoints_for_airport,
                      selected = checkpoints_for_airport[1])
  })
  
  
  # Reactive: filtered ±1-hour window ----
  
  filtered_data <- reactive({
    
    req(input$select_airport,
        input$select_checkpoint,
        input$select_day,
        input$select_time)
    
    selected_hms <- hms::as_hms(paste0(input$select_time, ":00"))
    start_hms    <- hms::as_hms(as.numeric(selected_hms) - 3600)  # -1 hour
    end_hms      <- hms::as_hms(as.numeric(selected_hms) + 3600)  # +1 hour
    
    # Central bar — bucket that contains the selected time (ceiling snaps forward)
    central_bucket <- hms::as_hms(
      lubridate::ceiling_date(
        as.POSIXct(paste0("2000-01-01 ", input$select_time, ":00")),
        "15 mins"
      )
    )
    
    summ_data |>
      filter(
        airport     == input$select_airport,
        checkpoint  == input$select_checkpoint,
        weekday     == input$select_day,
        bucket_time >= start_hms,
        bucket_time <= end_hms
      ) |>
      mutate(
        highlight    = if_else(bucket_time == central_bucket, "Central", "Other"),
        bucket_label = format(as.POSIXlt(bucket_time), "%H:%M") |>
          factor(levels = unique(format(as.POSIXlt(bucket_time), "%H:%M"))),
        label_color  = if_else(highlight == "Central", "white", "black")
      )
  })
  
  
  # Helper: build chart ----
  
  build_chart <- function(data, avg_col, max_col, subtitle) {
    
    if (nrow(data) == 0) {
      return(
        ggplot() +
          annotate("text", x = 0.5, y = 0.5,
                   label = "No data for this selection.",
                   size = 5, color = "gray50") +
          theme_void()
      )
    }
    
    avg_vals <- data[[avg_col]]
    max_vals <- data[[max_col]]
    
    if (all(is.na(avg_vals))) {
      return(
        ggplot() +
          annotate("text", x = 0.5, y = 0.5,
                   label = "No wait time data for this selection.",
                   size = 5, color = "gray50") +
          theme_void()
      )
    }
    
    y_max <- max(c(avg_vals, max_vals), na.rm = TRUE) + 3
    
    ggplot(data, aes(x = bucket_label, y = .data[[avg_col]], fill = highlight)) +
      geom_col_rounded(
        width       = 0.9,
        show.legend = FALSE,
        aes(fill = highlight)
      ) +
      geom_text(
        aes(label = round(.data[[avg_col]], 0), color = label_color),
        vjust    = 1.4,
        size     = 3.5,
        fontface = "bold",
        na.rm    = TRUE
      ) +
      geom_point(
        aes(y = .data[[max_col]]),
        shape = 21, size = 3,
        fill  = "skyblue3", color = "skyblue3",
        na.rm = TRUE
      ) +
      geom_text(
        aes(y = .data[[max_col]], label = round(.data[[max_col]], 0)),
        color    = "skyblue3",
        vjust    = -0.8,
        size     = 3.2,
        fontface = "bold",
        na.rm    = TRUE
      ) +
      scale_color_identity() +
      scale_fill_manual(values = c("Central" = "skyblue3", "Other" = "darkgray")) +
      scale_y_continuous(limits = c(0, y_max)) +
      labs(subtitle = subtitle, x = NULL, y = "Minutes") +
      theme_minimal() +
      theme(
        plot.subtitle      = element_text(hjust = 0.5, size = 11),
        axis.text.x        = element_text(angle = 0, hjust = 0.5, face = "bold"),
        panel.grid.major.x = element_blank(),
        panel.grid.minor   = element_blank()
      ) +
      annotate(
        "text",
        x = 1, y = y_max,
        label = "\u25cf = Max Wait",
        color = "skyblue3", size = 3.5, hjust = 0
      )
  }
  
  
  # Render standard lane chart ----
  
  output$chart_std <- renderPlot({
    data <- filtered_data()
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_std", "max_time_std", subtitle)
  })
  
  
  # Render TSA Pre-check lane chart ----
  
  output$chart_pre <- renderPlot({
    data <- filtered_data()
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_tsa_precheck", "max_time_tsa_precheck", subtitle)
  })
  
}


# Run ----

shinyApp(ui = ui, server = server)
