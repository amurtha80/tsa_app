# app_sidebar.R ----
# ASAP — Airport Security Advance Planning
# Shiny app wired to tsa_app_summ.duckdb (read-only).
#
# UI/UX revision — MVP Design Pass (June 2026)
# Changes from prior version:
#   - Settings offcanvas (dark mode + color toggle) removed for MVP
#   - Navbar simplified: "ASAP" + plane icon only, no subtitle
#   - Fixed theme: Navy (#2C3E7F) primary, Teal (#18BC9C) accent
#   - Inter + DM Serif Display loaded via Google Fonts
#   - Hero band with muted airport background + headline + descriptor
#   - Smart defaults: day + time auto-set from Sys.time() on session start
#   - Day + Time selectors displayed side-by-side on mobile
#   - Pinned footer replaced with 30-second delayed donate toast
#
# Layout: page_fillable() + responsive layout_columns()
# Mobile-first: inputs stack above charts on small screens, side-by-side on desktop
#
# UI: bslib + Bootstrap 5
# Data: tsa_app_summ.parquet — written nightly by xx_build_summary_db.R, pushed to S3,
#       pulled to EC2 disk before app restarts


# Libraries ----

library(shiny,       verbose = FALSE, warn.conflicts = FALSE)
library(bslib,       verbose = FALSE, warn.conflicts = FALSE)
library(nanoparquet, verbose = FALSE, warn.conflicts = FALSE)
library(dplyr,       verbose = FALSE, warn.conflicts = FALSE)
library(ggplot2,     verbose = FALSE, warn.conflicts = FALSE)
library(ggrounded,   verbose = FALSE, warn.conflicts = FALSE)
library(hms,         verbose = FALSE, warn.conflicts = FALSE)
library(lubridate,   verbose = FALSE, warn.conflicts = FALSE)
library(glue,        verbose = FALSE, warn.conflicts = FALSE)
library(here,        verbose = FALSE, warn.conflicts = FALSE)


# Data ----
# Read once at startup — all users share this in-memory data frame.
# TODO (EC2 deployment): confirm path matches where cron job pulls from S3,
# e.g. here::here("01_Data", "tsa_app_summ.parquet")

summ_data <- nanoparquet::read_parquet(
  here::here("01_Data", "tsa_app_summ.parquet")
) |>
  mutate(bucket_time = hms::as_hms(bucket_time))


# Pre-computed lookups ----
# Built once at startup so observeEvent(select_airport) never filters summ_data
# at runtime — it just looks up a pre-built list.

checkpoints_by_airport <- summ_data |>
  group_by(airport) |>
  summarize(checkpoints = list(sort(unique(checkpoint))), .groups = "drop") |>
  tibble::deframe()


# Derived UI inputs ----

airport_choices <- sort(unique(summ_data$airport))
weekday_choices <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

time_slot_times <- seq(
  as.POSIXct("2000-01-01 00:00:00"),
  as.POSIXct("2000-01-01 23:45:00"),
  by = "15 min"
)

# Named vector: display label is 12-hour, underlying value stays "HH:MM" for filter
time_slots <- setNames(
  format(time_slot_times, "%H:%M"),
  format(time_slot_times, "%I:%M %p")
)

rm(time_slot_times)

# Smart defaults derived at app load time ----
# Day: current weekday label (matches weekday_choices abbreviations)
# Time: nearest 15-min slot to current system time, rounded up
default_day <- weekday_choices[lubridate::wday(Sys.time(), week_start = 7)]

default_time <- format(
  lubridate::ceiling_date(Sys.time(), "15 mins"),
  "%H:%M"
)
# Guard: if ceiling_date produces 24:00 (midnight rollover), fall back to 00:00
if (!(default_time %in% time_slots)) default_time <- "00:00"


# Fixed theme palette ----
# Navy primary for navbar/buttons; Teal accent for chart highlights and CTAs.
# Settings drawer removed for MVP — single fixed theme.

nav_color   <- "#2C3E7F"   # Navy — navbar bg, primary buttons
accent_teal <- "#18BC9C"   # Teal — chart highlight bar, CTA links
text_dark   <- "#2C3E50"   # Charcoal — body text
text_light  <- "#FFFFFF"   # White — text on dark backgrounds


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


# App theme ----

app_theme <- bs_theme(
  version = 5,
  bg      = "#FFFFFF",
  fg      = text_dark,
  primary = nav_color,
  base_font = font_google("Inter"),
  heading_font = font_google("DM Serif Display")
)


# Navbar ----
# Simplified from prior version: no subtitle, no hamburger/offcanvas.
# Just plane icon left, "ASAP" centered, empty right slot for visual balance.

asap_navbar <- tags$nav(
  id    = "asap-navbar",
  class = "navbar",
  style = glue("background-color:{nav_color}; padding:10px 16px; position:sticky; top:0; z-index:1030;"),
  
  tags$div(
    style = "display:flex; align-items:center; width:100%;",
    
    # Left — plane icon
    tags$div(
      style = "flex:0 0 36px; display:flex; align-items:center;",
      icon("plane-departure", style = glue("color:{text_light}; font-size:1.2rem;"))
    ),
    
    # Center — title only
    tags$div(
      style = "flex:1 1 auto; text-align:center;",
      tags$span(
        "ASAP",
        style = glue(
          "font-family:'DM Serif Display', serif; font-size:1.25rem; ",
          "font-weight:400; color:{text_light}; letter-spacing:0.05em;"
        )
      )
    ),
    
    # Right — balanced empty slot (same width as left icon)
    tags$div(style = "flex:0 0 36px;")
  )
)


# Hero band ----
# Narrow strip below navbar with headline + one-sentence descriptor.
# Background: dark navy overlay on a subtle airport texture.
# Kept intentionally short (~90px on mobile) — enough to orient, not enough to scroll past.

hero_band <- tags$div(
  id    = "asap-hero",
  style = paste0(
    "background: linear-gradient(135deg, #1a2a5e 0%, #2C3E7F 60%, #18587a 100%);",
    "padding: 20px 24px 18px 24px;",
    "text-align: center;",
    "position: relative;",
    "overflow: hidden;"
  ),
  
  # Subtle decorative rings — pure CSS, no image dependency
  tags$div(
    style = paste0(
      "position:absolute; top:-40px; right:-40px; width:180px; height:180px;",
      "border-radius:50%; border:1px solid rgba(255,255,255,0.08); pointer-events:none;"
    )
  ),
  tags$div(
    style = paste0(
      "position:absolute; top:-20px; right:-20px; width:120px; height:120px;",
      "border-radius:50%; border:1px solid rgba(255,255,255,0.06); pointer-events:none;"
    )
  ),
  
  # Hero headline
  tags$h1(
    "Know before you go.",
    style = paste0(
      "font-family:'DM Serif Display', serif;",
      "font-size: clamp(1.35rem, 4vw, 1.75rem);",
      "font-weight: 400;",
      "color: #FFFFFF;",
      "margin: 0 0 6px 0;",
      "line-height: 1.2;"
    )
  ),
  
  # One-line descriptor
  tags$p(
    "Pick your airport, day, and time \u2014 see how long security usually takes.",
    style = paste0(
      "font-family:'Inter', sans-serif;",
      "font-size: 0.82rem;",
      "color: rgba(255,255,255,0.8);",
      "margin: 0;",
      "font-weight: 400;"
    )
  )
)


# Donate toast (delayed 30 seconds) ----
# Bootstrap 5 toast component, shown via JS after 30s.
# Positioned bottom-right on desktop, bottom-center on mobile.
# Dismissed state held in session only (no cookie) — reappears on fresh load.

donate_toast <- tags$div(
  id         = "donate-toast",
  class      = "toast align-items-center border-0",
  role       = "alert",
  `aria-live`        = "assertive",
  `aria-atomic`      = "true",
  `data-bs-autohide` = "false",
  style = paste0(
    "position:fixed; bottom:20px; right:16px; z-index:1060;",
    "max-width:300px; width:calc(100% - 32px);",   # full-width on small screens
    "background-color:#1f2d3d; color:#fff;",
    "border-radius:12px; box-shadow:0 4px 20px rgba(0,0,0,0.35);"
  ),
  
  tags$div(
    class = "d-flex",
    
    # considder buying me a coffee
    tags$div(
      class = "toast-body",
      style = "font-family:'Inter',sans-serif; font-size:0.85rem; padding:14px 12px;",
      HTML(paste0(
        "<span style='font-size:1.1rem;'>\u2615</span> ",
        "<strong>If ASAP saved you time today</strong>, consider supporting the site.",
        "<br><br>",
        "<a href='https://www.buymeacoffee.com/andymurtha' target='_blank' ",
        "style='background:#18BC9C; color:#fff; text-decoration:none; ",
        "padding:6px 14px; border-radius:6px; font-weight:600; font-size:0.82rem; ",
        "display:inline-block;'>",
        "\u2615 Buy me a coffee</a>"
      ))
    ),
    
    tags$button(
      type              = "button",
      class             = "btn-close btn-close-white me-2 m-auto",
      `data-bs-dismiss` = "toast",
      `aria-label`      = "Close"
    )
  )
)

# JS: show toast after 23-second delay
toast_js <- tags$script(HTML("
  $(document).ready(function() {
    setTimeout(function() {
      var toastEl = document.getElementById('donate-toast');
      if (toastEl) {
        var toast = new bootstrap.Toast(toastEl, { autohide: false });
        toast.show();
      }
    }, 23000);
  });
"))


# CSS ----

app_css <- glue("

  /* ── Reset & base ──────────────────────────────── */
  body {{
    margin-top: 0 !important;
    padding-top: 0 !important;
    font-family: 'Inter', sans-serif;
    background-color: #f8f9fa;
  }}

  /* ── Main content area ─────────────────────────── */
  #asap-main {{
    padding-top:    20px;
    padding-bottom: 32px;
    padding-left:   16px;
    padding-right:  16px;
  }}

  /* ── Input section header ──────────────────────── */
  .asap-section-label {{
    font-family: 'Inter', sans-serif;
    font-size:   0.72rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: {nav_color};
    margin-bottom: 10px;
    padding-bottom: 4px;
    border-bottom: 2px solid {accent_teal};
    display: inline-block;
  }}

  /* ── Input labels ──────────────────────────────── */
  .control-label {{
    font-size:   0.8rem;
    font-weight: 600;
    color:       {text_dark};
  }}

  /* ── Card headers ──────────────────────────────── */
  .card-header {{
    background-color: {nav_color} !important;
    color:            {text_light} !important;
    font-family:      'Inter', sans-serif;
    font-size:        0.82rem;
    font-weight:      600;
    letter-spacing:   0.04em;
    border-radius:    8px 8px 0 0 !important;
    padding:          10px 16px;
  }}

  /* ── Cards ─────────────────────────────────────── */
  .card {{
    border-radius: 10px !important;
    border:        1px solid #e2e8f0 !important;
    box-shadow:    0 1px 6px rgba(0,0,0,0.07);
  }}

  /* -- Select inputs (all native <select> elements) -- */
  /* selectize = FALSE means every dropdown is a native OS picker on mobile --
     no virtual keyboard, no text input, no keyboard trigger.               */
  select.form-select {{
    border-radius: 6px !important;
    font-size:     0.85rem !important;
    border-color:  #cbd5e1 !important;
    cursor:        pointer;
  }}
  select.form-select:focus {{
    border-color: {accent_teal} !important;
    box-shadow:   0 0 0 2px rgba(24,188,156,0.2) !important;
    outline:      none;
  }}

  /* ── Time window hint ──────────────────────────── */
  .asap-time-hint {{
    font-size:  0.72rem;
    color:      #64748b;
    margin-top: 6px;
    display:    flex;
    align-items: center;
    gap:        6px;
  }}
  .asap-time-hint .hint-line {{
    flex: 1;
    height: 2px;
    background: linear-gradient(to right, #e2e8f0, {accent_teal}, #e2e8f0);
    border-radius: 2px;
  }}

  /* ── Hero responsive sizing ────────────────────── */
  @media (min-width: 768px) {{
    #asap-hero {{ padding: 28px 40px 24px 40px; }}
  }}

  /* ── Ensure layout_columns inputs column doesn't
       get a card wrapper (it's just a plain div) ── */
  .bslib-gap-spacing {{ gap: 1rem !important; }}

")


# UI ----

ui <- page_fillable(
  title   = "ASAP - Airport Security Advance Planning",
  theme   = app_theme,
  padding = 0,
  
  # Head: CSS + Google Fonts loaded via bs_theme font_google() above,
  # but we add the toast JS trigger here
  tags$head(
    tags$style(HTML(app_css)),
    # FontAwesome (ensure available for plane-departure icon)
    tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"
    )
  ),
  
  # Sticky navbar
  asap_navbar,
  
  # Hero band
  hero_band,
  
  # Donate toast (hidden; shown by JS after 30s)
  donate_toast,
  toast_js,
  
  # Main content
  tags$div(
    id = "asap-main",
    
    layout_columns(
      col_widths = breakpoints(sm = 12, lg = c(3, 9)),
      gap        = "1.25rem",
      
      # ── Inputs column ────────────────────────────
      div(
        tags$span("Search", class = "asap-section-label"),
        
        # selectize = FALSE renders a native <select> element.
        # This prevents the virtual keyboard from appearing on mobile,
        # which selectizeInput triggers because it uses a text input internally.
        selectInput(
          inputId  = "select_airport",
          label    = "Airport",
          choices  = airport_choices,
          selected = airport_choices[1],
          selectize = FALSE,
          width    = "100%"
        ),
        
        selectInput(
          inputId = "select_checkpoint",
          label   = "Checkpoint",
          choices = NULL,
          selectize = FALSE,
          width   = "100%"
        ),
        
        # Day + Time side-by-side on mobile --------
        layout_columns(
          col_widths = c(6, 6),
          gap        = "0.75rem",
          
          selectInput(
            inputId  = "select_day",
            label    = "Day",
            choices  = weekday_choices,
            selected = default_day,
            selectize = FALSE,
            width    = "100%"
          ),
          
          selectInput(
            inputId  = "select_time",
            label    = "Time",
            choices  = time_slots,
            selected = default_time,
            selectize = FALSE,
            width    = "100%"
          )
        ),
        
        # Time window visual hint
        tags$div(
          class = "asap-time-hint",
          tags$span("\u2212 1 hr"),
          tags$div(class = "hint-line"),
          tags$span("\u25cf YOU"),
          tags$div(class = "hint-line"),
          tags$span("+ 1 hr")
        )
      ),
      
      # ── Charts column ────────────────────────────
      div(
        tags$span("Wait Time Estimates", class = "asap-section-label"),
        
        card(
          card_header(
            icon("person-walking-luggage", style = "margin-right:6px;"),
            "Standard Lane \u2014 Avg Wait (min)"
          ),
          card_body(padding = "12px",
                    plotOutput("chart_std", height = "320px")
          )
        ),
        
        br(),
        
        card(
          card_header(
            icon("plane-circle-check", style = "margin-right:6px;"),
            "TSA Pre\u2713 Lane \u2014 Avg Wait (min)"
          ),
          card_body(padding = "12px",
                    plotOutput("chart_pre", height = "320px")
          )
        )
      )
    )
  )
)


# Server ----

server <- function(input, output, session) {
  
  
  # Update checkpoint choices when airport changes ----
  # Uses pre-computed lookup — no runtime filtering of summ_data.
  
  observeEvent(input$select_airport, {
    checkpoints_for_airport <- checkpoints_by_airport[[input$select_airport]]
    
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
        bucket_label = format(as.POSIXlt(bucket_time), "%I:%M\n%p") |>
          factor(levels = unique(format(as.POSIXlt(bucket_time), "%I:%M\n%p"))),
        label_color  = if_else(highlight == "Central",
                               label_color_for(accent_teal),
                               "black")
      )
  })
  
  
  # Helper: build chart ----
  # Chart colors are now fixed (Navy/Teal) regardless of any theme toggle.
  
  build_chart <- function(data, avg_col, max_col, subtitle, lane_label = "standard") {
    
    teal_dark <- darken_hex(accent_teal, amount = 0.30)
    
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
      msg <- switch(lane_label,
                    "precheck" = "No TSA Pre\u2713 lane at this checkpoint.",
                    "clear"    = "No CLEAR lane at this checkpoint.",
                    "No wait time data for this selection."
      )
      return(
        ggplot() +
          annotate("text", x = 0.5, y = 0.5,
                   label = msg, size = 5, color = "gray50") +
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
        size     = 4.5,
        fontface = "bold",
        na.rm    = TRUE
      ) +
      geom_point(
        aes(y = .data[[max_col]]),
        shape = 21, size = 4.5,
        fill  = teal_dark, color = teal_dark,
        na.rm = TRUE
      ) +
      geom_text(
        aes(y = .data[[max_col]], label = round(.data[[max_col]], 0)),
        color    = teal_dark,
        vjust    = -0.8,
        size     = 4.0,
        fontface = "bold",
        na.rm    = TRUE
      ) +
      scale_color_identity() +
      scale_fill_manual(values = c("Central" = accent_teal, "Other" = "#AAAAAA")) +
      scale_y_continuous(limits = c(0, y_max)) +
      labs(subtitle = subtitle, x = NULL, y = "Minutes") +
      theme_minimal(base_family = "sans") +
      theme(
        plot.subtitle      = element_text(hjust = 0.5, size = 11, color = text_dark),
        axis.text.x        = element_text(angle = 0, hjust = 0.5, face = "bold",
                                          size = 9, color = text_dark),
        axis.text.y        = element_text(size = 9, color = "#64748b"),
        axis.title.y       = element_text(size = 9, color = "#64748b"),
        panel.grid.major.x = element_blank(),
        panel.grid.minor   = element_blank(),
        panel.grid.major.y = element_line(color = "#f1f5f9", linewidth = 0.5),
        plot.background    = element_rect(fill = "white", color = NA),
        panel.background   = element_rect(fill = "white", color = NA)
      ) +
      annotate(
        "text",
        x = 1, y = y_max,
        label  = "\u25cf = Max Wait",
        color  = teal_dark,
        size   = 3.8,
        hjust  = 0,
        fontface = "bold"
      )
  }
  
  
  # Render standard lane chart ----
  
  output$chart_std <- renderPlot({
    data     <- filtered_data()
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_std", "max_time_std", subtitle, lane_label = "standard")
  }) |>
    bindCache(
      input$select_airport,
      input$select_checkpoint,
      input$select_day,
      input$select_time
    )
  
  
  # Render TSA Pre-check lane chart ----
  
  output$chart_pre <- renderPlot({
    data     <- filtered_data()
    subtitle <- glue(
      "{input$select_checkpoint} \u2022 {input$select_airport} \u2022 ",
      "{input$select_day} around {input$select_time}"
    )
    build_chart(data, "avg_time_tsa_precheck", "max_time_tsa_precheck", subtitle, lane_label = "precheck")
  }) |>
    bindCache(
      input$select_airport,
      input$select_checkpoint,
      input$select_day,
      input$select_time
    )
  
}


# Run ----

shinyApp(ui = ui, server = server)
# Connect to local shiny app with host binding
# shiny::runApp(
#   shinyApp(ui = ui, server = server),
#   host = "0.0.0.0",
#   port = 3838
# )