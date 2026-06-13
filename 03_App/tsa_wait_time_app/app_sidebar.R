# app_sidebar.R ----
# ASAP — Airport Security Advance Planning
# Shiny app wired to tsa_app_summ.duckdb (read-only).
#
# Navbar: custom HTML tags$nav — plane icon left, title+subtitle center,
#         hamburger right. Bootstrap offcanvas for settings drawer.
#         No page_navbar() — avoids all bslib navbar nesting issues.
#
# Layout: page_fillable() outer wrapper + responsive layout_columns()
# Mobile-first: inputs stack above charts on small screens, side-by-side on desktop
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

color_choices <- list(
  "Teal"      = list(primary = "#18BC9C", bg = "#18BC9C"),
  "Navy"      = list(primary = "#2C3E7F", bg = "#2C3E7F"),
  "Goldenrod" = list(primary = "#DAA520", bg = "#DAA520")
)

default_color <- "Teal"


# Theme builder ----

build_theme <- function(color_name = default_color, mode = "light") {
  pal    <- color_choices[[color_name]]
  bg_col <- if (mode == "dark") "#222222" else "#FFFFFF"
  fg_col <- if (mode == "dark") "#FFFFFF" else "#2C3E50"
  
  bs_theme(
    version  = 5,
    bg       = bg_col,
    fg       = fg_col,
    primary  = pal$primary
  )
}


# Color utility functions ----

darken_hex <- function(hex, amount = 0.35) {
  rgb_vals <- col2rgb(hex) / 255
  rgb_vals <- rgb_vals * (1 - amount)
  rgb(rgb_vals[1], rgb_vals[2], rgb_vals[3])
}

label_color_for <- function(hex) {
  rgb_vals <- col2rgb(hex) / 255
  rgb_lin  <- ifelse(rgb_vals <= 0.03928,
                     rgb_vals / 12.92,
                     ((rgb_vals + 0.055) / 1.055) ^ 2.4)
  luminance <- 0.2126 * rgb_lin[1] + 0.7152 * rgb_lin[2] + 0.0722 * rgb_lin[3]
  if (luminance > 0.179) "black" else "white"
}


# Navbar builder ----
# Returns a custom tags$nav with three equal-width slots:
#   left  — plane icon
#   center — ASAP title + subtitle
#   right — hamburger button (triggers offcanvas)
# Accent color passed as argument so navbar bg updates with theme changes.

build_navbar <- function(accent = color_choices[[default_color]]$bg) {
  tags$nav(
    id    = "asap-navbar",
    class = "navbar",
    style = glue("background-color:{accent}; padding:8px 16px;"),
    
    # Three-slot flex container
    tags$div(
      style = "display:flex; align-items:center; width:100%;",
      
      # Left — plane icon
      tags$div(
        style = "flex:0 0 40px; display:flex; align-items:center;",
        icon("plane", style = "color:#fff; font-size:1.3rem;")
      ),
      
      # Center — title + subtitle
      tags$div(
        style = "flex:1 1 auto; text-align:center; line-height:1.25;",
        tags$span(
          "ASAP",
          style = "font-size:1.05rem; font-weight:700; color:#fff; display:block;"
        ),
        tags$span(
          "Airport Security Advance Planning",
          style = "font-size:0.65rem; font-weight:400; color:#fff; opacity:0.85; display:block;"
        )
      ),
      
      # Right — hamburger button triggers offcanvas
      tags$div(
        style = "flex:0 0 40px; display:flex; align-items:center; justify-content:flex-end;",
        tags$button(
          type              = "button",
          style             = "background:none; border:none; padding:4px; cursor:pointer; line-height:1;",
          `data-bs-toggle`  = "offcanvas",
          `data-bs-target`  = "#asap-settings",
          `aria-controls`   = "asap-settings",
          icon("bars", style = "color:#fff; font-size:1.3rem;")
        )
      )
    )
  )
}


# Settings offcanvas panel ----
# Pure Bootstrap 5 offcanvas — slides in from right.
# Contains radioButtons for dark/light mode and accent color.
# Shiny reads these inputs normally via input$dark_mode and input$accent_color.

settings_panel <- tags$div(
  id       = "asap-settings",
  class    = "offcanvas offcanvas-end",
  tabindex = "-1",
  `aria-labelledby` = "asap-settings-label",
  
  # Header
  tags$div(
    class = "offcanvas-header",
    style = "border-bottom: 1px solid #dee2e6;",
    tags$h5(
      id    = "asap-settings-label",
      class = "offcanvas-title fw-semibold",
      icon("gear"), " App Settings"
    ),
    tags$button(
      type              = "button",
      class             = "btn-close",
      `data-bs-dismiss` = "offcanvas",
      `aria-label`      = "Close"
    )
  ),
  
  # Body
  tags$div(
    class = "offcanvas-body",
    
    tags$p(class = "fw-semibold mb-1",
           icon("circle-half-stroke"), " App Mode"),
    radioButtons(
      inputId  = "dark_mode",
      label    = NULL,
      choices  = c("Light" = "light", "Dark" = "dark"),
      selected = "light",
      inline   = TRUE
    ),
    
    tags$hr(),
    
    tags$p(class = "fw-semibold mb-1",
           icon("palette"), " Theme Color"),
    radioButtons(
      inputId  = "accent_color",
      label    = NULL,
      choices  = names(color_choices),
      selected = default_color,
      inline   = TRUE
    )
  )
)


# CSS ----

app_css <- "

  /* Remove default body top margin so custom navbar sits flush */
  body { margin-top: 0 !important; padding-top: 0 !important; }

  /* Main content area — sits below fixed navbar */
  #asap-main {
    padding-top:    16px;
    padding-bottom: 56px;   /* clears pinned footer */
    padding-left:   16px;
    padding-right:  16px;
  }

  /* Pinned footer */
  .asap-footer {
    position:         fixed;
    bottom:           0;
    left:             0;
    width:            100%;
    background-color: rgba(0,0,0,0.75);
    color:            #fff;
    text-align:       center;
    padding:          6px 0;
    font-size:        0.82rem;
    z-index:          1050;
  }
  .asap-footer a {
    color:           #FFD700;
    text-decoration: none;
    font-weight:     600;
  }
  .asap-footer a:hover { text-decoration: underline; }

"


# UI ----

ui <- page_fillable(
  title  = "ASAP - Airport Security Advance Planning",
  theme  = build_theme(default_color, "light"),
  padding = 0,
  
  tags$head(tags$style(HTML(app_css))),
  
  # Settings offcanvas — in DOM but hidden until hamburger clicked
  settings_panel,
  
  # Custom navbar — built as plain HTML, no bslib nav system
  uiOutput("navbar_ui"),
  
  # Main content
  tags$div(
    id = "asap-main",
    
    layout_columns(
      col_widths = breakpoints(sm = 12, lg = c(3, 9)),
      
      # Inputs column — plain div, no card() so dropdowns expand freely
      div(
        h5("Search", style = "font-weight:600; margin-bottom:16px;"),
        
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
          choices = NULL,
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
        
        helpText("\u00b11 hour around selected time (9 bars \u00d7 15 min).")
      ),
      
      # Charts column
      div(
        h5("Wait Time Estimates",
           style = "text-align:center; font-weight:600; margin-bottom:16px;"),
        
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
  ),
  
  # Pinned footer
  tags$div(
    class = "asap-footer",
    HTML(paste0(
      "\u2615 Find this useful? ",
      "<a href='https://www.buymeacoffee.com/' target='_blank'>Buy me a coffee</a>",
      " &nbsp;|&nbsp; ASAP \u2014 Airport Security Advance Planning"
    ))
  )
)


# Server ----

server <- function(input, output, session) {
  
  
  # Reactive accent color ----
  # Drives both session theme and navbar background color
  
  accent_hex <- reactive({
    req(input$accent_color)
    color_choices[[input$accent_color]]$primary
  })
  
  
  # Render navbar with current accent color ----
  # Rebuilds the navbar HTML whenever accent changes so bg color updates
  
  output$navbar_ui <- renderUI({
    build_navbar(accent = accent_hex())
  })
  
  
  # Theme reactivity — mode + accent ----
  
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
    start_hms    <- hms::as_hms(as.numeric(selected_hms) - 3600)
    end_hms      <- hms::as_hms(as.numeric(selected_hms) + 3600)
    
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
  
  build_chart <- function(data, avg_col, max_col, subtitle, accent) {
    
    accent_dark <- darken_hex(accent, amount = 0.35)
    lbl_color   <- label_color_for(accent)
    
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
    data     <- filtered_data()
    accent   <- accent_hex()
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_std", "max_time_std", subtitle, accent)
  })
  
  
  # Render TSA Pre-check lane chart ----
  
  output$chart_pre <- renderPlot({
    data     <- filtered_data()
    accent   <- accent_hex()
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_tsa_precheck", "max_time_tsa_precheck", subtitle, accent)
  })
  
}


# Run ----


shinyApp(ui = ui, server = server)
# Connect to local shiny app app_sidebar.R with host
# shiny::runApp(
              # shinyApp(ui = ui, server = server),
              # host = "0.0.0.0",
              # port = 3838
              # )

