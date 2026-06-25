library(shiny)
library(shinyMobile)
library(dplyr)
library(ggplot2)
library(scales)

# Sample data
airports <- data.frame(
  code = c("ATL", "LAX", "ORD", "DFW", "DEN"),
  city = c("Atlanta", "Los Angeles", "Chicago", "Dallas", "Denver"),
  name = c("Hartsfield-Jackson", "Los Angeles International", "O'Hare International", "Dallas/Fort Worth International", "Denver International")
)

# Create initial choices for autocomplete
airport_choices <- paste(airports$city, "-", airports$code)

# Sample checkpoint data
checkpoints <- list(
  "ATL" = c("Main Terminal", "North Terminal", "International Terminal"),
  "LAX" = c("Terminal 1", "Terminal 4", "Tom Bradley International"),
  "ORD" = c("Terminal 1", "Terminal 3", "Terminal 5"),
  "DFW" = c("Terminal A", "Terminal D", "Terminal E"),
  "DEN" = c("North Security", "South Security", "Bridge Security")
)

# Generate sample wait times
generate_wait_times <- function(checkpoint_id, date, time) {
  # Simulate average wait times between 5 and 45 minutes
  avg_time <- runif(1, 5, 45)
  max_time <- avg_time + runif(1, 5, 20)
  
  # Randomly determine if PreCheck and Clear are available
  has_precheck <- sample(c(TRUE, FALSE), 1)
  has_clear <- sample(c(TRUE, FALSE), 1)
  
  list(
    avg_time = avg_time,
    max_time = max_time,
    precheck = if(has_precheck) runif(1, 3, 15) else NULL,
    clear = if(has_clear) runif(1, 2, 10) else NULL
  )
}

# Shiny App Options ----
app_opts <-   list(
  theme = "ios",
  dark = "auto",
  skeletonsOnLoad = FALSE,
  preloader = FALSE,
  filled = FALSE,
  color = "#007aff",
  touch = list(
    touchClicksDistanceThreshold = 5,
    tapHold = TRUE,
    tapHoldDelay = 750,
    tapHoldPreventClicks = TRUE,
    iosTouchRipple = FALSE,
    mdTouchRipple = TRUE
  ),
  iosTranslucentBars = FALSE,
  navbar = list(
    iosCenterTitle = TRUE,
    hideOnPageScroll = TRUE
  ),
  toolbar = list(
    hideOnPageScroll = FALSE
  ),
  pullToRefresh = FALSE
)

# Shiny App ----
ui <- f7Page(
  options = app_opts,
  title = "Trekking through TSA",
  f7SingleLayout(
    navbar = f7Navbar(
      title = "Trekking through TSA",
      left_panel = TRUE,
      right_panel = TRUE,
      hairline = TRUE
      # shadow argument of f7Navbar() has been deprecated in shinyMobile 2.0.0
      # shadow = TRUE
    ),
    # Main content
    f7Card(
      "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
    ),
    
    # Search and filters
    f7Card(
      f7AutoComplete(
        inputId = "airport",
        label = "Search Airport",
        placeholder = "Enter city or airport code",
        choices = airport_choices
      ),
      f7Select(
        inputId = "checkpoint",
        label = "Security Checkpoint",
        choices = NULL
      )
    ),
    
    # Date and time selection
    f7Card(
      f7Grid(
        cols = 3,
        f7Col(
          f7Select(
            inputId = "day",
            label = "Day",
            choices = c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
          )
        ),
        f7Col(
          f7DatePicker(
            inputId = "date",
            label = "Date"
          )
        ),
        f7Col(
          f7Select(
            inputId = "time",
            label = "Time",
            choices = format(seq(from=as.POSIXct("2023-01-01 00:00"), 
                                 to=as.POSIXct("2023-01-01 23:45"), 
                                 by="15 min"), "%H:%M")
          )
        )
      )
    ),
    
    # KPI cards
    f7Card(
      id = "wait_times",
      f7Grid(
        cols = 1,
        f7Col(
          uiOutput("avg_wait_card")
        )
      ),
      f7Grid(
        cols = 2,
        f7Col(
          uiOutput("precheck_card")
        ),
        f7Col(
          uiOutput("clear_card")
        )
      )
    ),
    
    # Wait time chart
    f7Card(
      plotOutput("wait_time_chart")
    ),
    
    # Footer links
    f7Card(
      f7Grid(
        cols = 4,
        f7Col(
          f7Link(label = "Airport Website", href = "#")
        ),
        f7Col(
          f7Link(label = "About", href = "#")
        ),
        f7Col(
          f7Link(label = "TSA.gov", href = "https://www.tsa.gov/")
        ),
        f7Col(
          f7Link(label = "Buy Me a Coffee", href = "#")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Update checkpoint choices based on selected airport
  observe({
    req(input$airport)
    airport_code <- substr(input$airport, nchar(input$airport)-3, nchar(input$airport)-1)
    updateF7Select(
      session,
      inputId = "checkpoint",
      choices = checkpoints[[airport_code]]
    )
  })
  
  # Generate wait time data
  wait_time_data <- reactive({
    req(input$checkpoint, input$date, input$time)
    generate_wait_times(input$checkpoint, input$date, input$time)
  })
  
  # Render KPI cards
  output$avg_wait_card <- renderUI({
    data <- wait_time_data()
    avg_time <- round(data$avg_time)
    color <- case_when(
      avg_time <= 10 ~ "#99d8c9",
      avg_time <= 20 ~ "#66c2a4",
      avg_time <= 30 ~ "#2ca25f",
      TRUE ~ "#006d2c"
    )
    
    div(
      style = paste0("background-color: ", color, "; padding: 20px; border-radius: 10px;"),
      h2(style = "color: white; text-align: center;", paste0(avg_time, " min")),
      p(style = "color: white; text-align: center;", paste("Max:", round(data$max_time), "min"))
    )
  })
  
  output$precheck_card <- renderUI({
    data <- wait_time_data()
    if (!is.null(data$precheck)) {
      div(
        style = "background-color: #f8f9fa; padding: 20px; border-radius: 10px;",
        h3("TSA PreCheck"),
        h4(paste0(round(data$precheck), " min"))
      )
    }
  })
  
  output$clear_card <- renderUI({
    data <- wait_time_data()
    if (!is.null(data$clear)) {
      div(
        style = "background-color: #f8f9fa; padding: 20px; border-radius: 10px;",
        h3("CLEAR"),
        h4(paste0(round(data$clear), " min"))
      )
    }
  })
  
  # Render wait time chart
  output$wait_time_chart <- renderPlot({
    req(input$time)
    
    # Generate sample data for the chart
    times <- seq(-90, 90, by = 15)
    wait_times <- data.frame(
      time = times,
      avg_wait = runif(length(times), 5, 45),
      max_wait = NA
    )
    wait_times$max_wait <- wait_times$avg_wait + runif(length(times), 5, 20)
    
    ggplot(wait_times, aes(x = time, y = avg_wait)) +
      geom_col(fill = "#66c2a4", width = 10) +
      geom_point(aes(y = max_wait), color = "red", size = 2) +
      scale_y_continuous(limits = c(0, 75), breaks = seq(0, 75, 15)) +
      scale_x_continuous(breaks = seq(-90, 90, 15)) +
      labs(x = "Minutes from selected time", y = "Wait time (minutes)") +
      theme_minimal()
  })
}

shinyApp(ui, server)