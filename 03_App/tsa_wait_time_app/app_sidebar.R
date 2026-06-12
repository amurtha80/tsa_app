# app_sidebar.R ----
# ASAP — Airport Security Advance Planning
# Shiny app wired to tsa_app_summ.duckdb (read-only).
# Layout: page_navbar() + responsive layout_columns() (stacks on mobile)
# Mobile-first: inputs stack above charts on small screens, side-by-side on desktop
# Hamburger menu (top right): dark/light toggle + color picker
# Pinned footer: donate link placeholder
#
# UI: bslib + Bootstrap 5
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

airport_choices <- sort(unique(summ_data$airport))
weekday_choices <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

time_slots <- format(
  seq(as.POSIXct("2000-01-01 00:00:00"),
      as.POSIXct("2000-01-01 23:45:00"),
      by = "15 min"),
  "%H:%M"
)


# Color palette ----
# Three accent options: teal (default), navy, goldenrod
# Each entry: display label → list(primary, navbar_bg)

color_choices <- list(
  "Teal"      = list(primary = "#18BC9C", bg = "#18BC9C"),
  "Navy"      = list(primary = "#2C3E7F", bg = "#2C3E7F"),
  "Goldenrod" = list(primary = "#DAA520", bg = "#DAA520")
)

default_color <- "Teal"


# Theme builder ----
# Rebuilds full bs_theme on color or dark mode change so both navbar bg
# and primary accent update together.

build_theme <- function(color_name = default_color, mode = "light") {
  pal     <- color_choices[[color_name]]
  bg_col  <- if (mode == "dark") "#222222" else "#FFFFFF"
  fg_col  <- if (mode == "dark") "#FFFFFF" else "#2C3E50"
  
  bs_theme(
    version   = 5,
    bg        = bg_col,
    fg        = fg_col,
    primary   = pal$primary,
    "navbar-bg" = pal$bg
  )
}


# Color utility functions ----

# Darken a hex color by reducing RGB values by a given proportion (0-1)
darken_hex <- function(hex, amount = 0.35) {
  rgb_vals <- col2rgb(hex) / 255
  rgb_vals <- rgb_vals * (1 - amount)
  rgb(rgb_vals[1], rgb_vals[2], rgb_vals[3])
}

# Return "white" or "black" depending on luminance of hex color
# Uses WCAG relative luminance formula
label_color_for <- function(hex) {
  rgb_vals <- col2rgb(hex) / 255
  # Linearize sRGB channels
  rgb_lin <- ifelse(rgb_vals <= 0.03928,
                    rgb_vals / 12.92,
                    ((rgb_vals + 0.055) / 1.055) ^ 2.4)
  luminance <- 0.2126 * rgb_lin[1] + 0.7152 * rgb_lin[2] + 0.0722 * rgb_lin[3]
  if (luminance > 0.179) "black" else "white"
}

footer_css <- "
  /* Pinned footer */
  .asap-footer {
    position: fixed;
    bottom: 0;
    left: 0;
    width: 100%;
    background-color: rgba(0, 0, 0, 0.75);
    color: #fff;
    text-align: center;
    padding: 6px 0;
    font-size: 0.82rem;
    z-index: 1050;
  }
  .asap-footer a {
    color: #FFD700;
    text-decoration: none;
    font-weight: 600;
  }
  .asap-footer a:hover {
    text-decoration: underline;
  }

  /* Add bottom padding to main content so footer never covers charts */
  .bslib-page-navbar > .container-fluid {
    padding-bottom: 48px;
  }
"


# UI ----

ui <- page_navbar(
  title        = "ASAP",
  window_title = "ASAP - Airport Security Advance Planning",
  theme        = build_theme(default_color, "light"),
  id           = "main_navbar",
  
  # Inject footer CSS
  header = tags$head(tags$style(HTML(footer_css))),
  
  # Pinned footer
  footer = tags$div(
    class = "asap-footer",
    HTML(paste0(
      "\u2615 Find this useful? ",
      "<a href='https://www.buymeacoffee.com/' target='_blank'>",
      "Buy me a coffee</a>",
      " &nbsp;|&nbsp; ASAP \u2014 Airport Security Advance Planning"
    ))
  ),
  
  # Hamburger menu — top right ----
  nav_spacer(),
  nav_menu(
    title = NULL,
    icon  = icon("bars"),
    align = "right",
    
    # Dark / light mode
    nav_item(
      radioButtons(
        inputId  = "dark_mode",
        label    = tags$span(icon("circle-half-stroke"), " App Mode"),
        choices  = c("Light" = "light", "Dark" = "dark"),
        selected = "light",
        inline   = TRUE
      )
    ),
    
    nav_item(tags$hr(style = "margin: 4px 12px;")),
    
    # Color picker
    nav_item(
      radioButtons(
        inputId  = "accent_color",
        label    = tags$span(icon("palette"), " Accent Color"),
        choices  = names(color_choices),
        selected = default_color,
        inline   = TRUE
      )
    )
  ),
  
  # Main panel ----
  nav_panel(
    title = "Search",
    
    # Responsive layout: stacks on mobile (inputs then charts),
    # side-by-side on desktop (inputs left, charts right)
    layout_columns(
      col_widths = breakpoints(sm = 12, lg = c(3, 9)),
      
      # Inputs column ----
      # Plain div — no card() wrapper so dropdowns expand freely without clipping
      div(
        h5("Search", style = "font-weight: 600; margin-bottom: 16px;"),
        
        selectizeInput(
          inputId  = "select_airport",
          label    = "Airport",
          choices  = airport_choices,
          selected = airport_choices[1],
          options  = list(placeholder = "e.g. ATL"),
          width    = "100%"
        ),
        
        selectInput(
          inputId = "select_checkpoint",
          label   = "Checkpoint",
          choices = NULL,         # populated server-side
          width   = "100%"
        ),
        
        selectInput(
          inputId  = "select_day",
          label    = "Day of Week",
          choices  = weekday_choices,
          selected = "Mon",
          width    = "100%"
        ),
        
        selectInput(
          inputId  = "select_time",
          label    = "Time of Day (15-min slot)",
          choices  = time_slots,
          selected = "08:00",
          width    = "100%"
        ),
        
        helpText(
          "\u00b11 hour around selected time (9 bars \u00d7 15 min)."
        )
      ),
      
      # Charts column ----
      div(
        h5("Wait Time Estimates",
           style = "text-align: center; font-weight: 600; margin-bottom: 16px;"),
        
        card(
          card_header("Standard Lane \u2014 Average Wait Time (min)"),
          plotOutput("chart_std", height = "360px")
        ),
        
        br(),
        
        card(
          card_header("TSA Pre\u2713 Lane \u2014 Average Wait Time (min)"),
          plotOutput("chart_pre", height = "360px")
        )
      )
    )
  )
)


# Server ----

server <- function(input, output, session) {
  
  
  # Theme reactivity — rebuilds on color or mode change ----
  
  observeEvent(list(input$accent_color, input$dark_mode), ignoreInit = TRUE, {
    session$setCurrentTheme(
      build_theme(
        color_name = input$accent_color,
        mode       = input$dark_mode
      )
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
    
    # Central bar — bucket containing the selected time (ceiling snaps forward)
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
        # label color computed at render time via accent — placeholder here
        label_color  = if_else(highlight == "Central", "white", "black")
      )
  })
  
  
  # Helper: build chart ----
  
  build_chart <- function(data, avg_col, max_col, subtitle, accent) {
    
    # Derive chart colors from accent
    accent_dark  <- darken_hex(accent, amount = 0.35)
    lbl_color    <- label_color_for(accent)
    
    # Update label_color column now that we know the accent
    data <- data |>
      mutate(label_color = if_else(highlight == "Central", lbl_color, "black"))
    
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
        fill  = accent_dark, color = accent_dark,
        na.rm = TRUE
      ) +
      geom_text(
        aes(y = .data[[max_col]], label = round(.data[[max_col]], 0)),
        color    = accent_dark,
        vjust    = -0.8,
        size     = 3.2,
        fontface = "bold",
        na.rm    = TRUE
      ) +
      scale_color_identity() +
      scale_fill_manual(values = c("Central" = accent, "Other" = "#AAAAAA")) +
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
        color = accent_dark, size = 3.5, hjust = 0
      )
  }
  
  
  # Render standard lane chart ----
  
  output$chart_std <- renderPlot({
    data <- filtered_data()
    accent <- color_choices[[input$accent_color]]$primary
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_std", "max_time_std", subtitle, accent)
  })
  
  
  # Render TSA Pre-check lane chart ----
  
  output$chart_pre <- renderPlot({
    data <- filtered_data()
    accent <- color_choices[[input$accent_color]]$primary
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_tsa_precheck", "max_time_tsa_precheck", subtitle, accent)
  })
  
}


# Run ----

shinyApp(ui = ui, server = server)
