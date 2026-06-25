library(shiny)
library(shinyMobile)
library(dplyr)
library(ggplot2)
library(scales)


# Shiny App Options ----
app_opts <- list(
  theme = "auto",
  dark = FALSE,
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
    mdCenterTitle = TRUE,
    hideOnPageScroll = TRUE
  ),
  toolbar = list(
    hideOnPageScroll = FALSE
  ),
  pullToRefresh = FALSE
)


# Shiny App ----

shinyApp(
  
  ui = f7Page(
    
    # Add Shiny App Options
    options = app_opts,
    
    # App Title
    title = "ASAP",
    
    f7TabLayout(
      panels = tagList(
        
        f7Panel(
          id = "menuoptions",
          side = "right",
          effect = "push",
          title = "App Options",
          f7Block(""),
          f7PanelMenu(
            id = "menu",
            f7Radio(
              inputId = "dark",
              label = "App Mode",
              choices = c("dark", "light"),
              selected = ifelse(app_opts$dark, "dark", "light")
            ),
            f7Radio(
              inputId = "color",
              label = "App Color",
              choices = c(getF7Colors()[4], getF7Colors()[6], getF7Colors()[11]),
              selected = "blue"
            ),
            f7PanelItem(
              tabName = "Tab1",
              title = "Tab 1",
              icon = f7Icon("folder"),
              active = TRUE
            ),
            
            f7PanelItem(
              tabName = "Tab2",
              title = "Tab 2",
              icon = f7Icon("keyboard")
            ),
            
            f7PanelItem(
              tabName = "Tab3",
              title = "Tab 3",
              icon = f7Icon("layers_alt")
            )
          )
        )
      ),
      
      navbar = f7Navbar(
        title = "ASAP - Airport Security Advance Planning",
        hairline = TRUE,
        leftPanel = FALSE,
        rightPanel = TRUE
      ),
      
      br(),
      br(),
      
      f7Align(
        f7BlockTitle(title = "Saving Some Time on Your Travel Day", size = "medium"),
        side = "center"
      ),
      
      f7Align(
        f7Block(
          outline = TRUE,
          inset = TRUE,
          tablet = TRUE,
          strong = TRUE,
          "Something about the purpose of the ShinyMobile App. Continue by telling
          the user how to navigate the app and what you will get after choosing
          the search criteria."
        ),
        side = "center"  
      ),
      
      f7Block(
        inset = TRUE,
        strong = TRUE,
        f7Align(
          f7BlockTitle("Airport Search"),
          side = "center"
        ),
        f7AutoComplete(
          inputId = "myautocomplete",
          placeholder = "Some text here!",
          openIn = "dropdown",
          label = "Type in an Airport Code or Airport Name",
          choices = c(
            "Apple", "Apricot", "Avocado", "Banana", "Melon",
            "Orange", "Peach", "Pear", "Pineapple"
          ),
          style = list(
            outline = TRUE,
            media = f7Icon("airplane"),
            description = "airport input",
            floating = TRUE
          )
        )
      ),
      
      f7Grid(
        f7Card(
          title = "Day of Week Selection",
          f7Select(
            inputId = "select_day",
            label = "Choose a Day of the Week:",
            choices = c('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday',
                        'Friday', 'Saturday'),
            selected = "Sunday",
            style = list(
              description = "weekday selection",
              media = f7Icon("calendar"),
              outline = TRUE
            )
          ),
          verbatimTextOutput("day_output")
        ),
        f7Card(
          title = "Time Slot Selection",
          f7Select(
            inputId = "select_time",
            label = "Choose a Time Slot:",
            choices = c('12:00 AM - 3:00 AM', '3:00 AM - 6:00 AM', 
                        '6:00 AM - 9:00 AM', '9:00 AM - 12:00 PM',
                        '12:00 PM - 3:00 PM', '3:00 PM - 6:00 PM',
                        '6:00 PM - 9:00 PM', '9:00 PM - 12:00 AM'),
            selected = "6:00 AM - 9:00 AM",
            style = list(
              description = "time slot selection",
              media = f7Icon("clock"),
              outline = TRUE
            )
          ),
          verbatimTextOutput("time_output")
        ),
        cols = 2, 
        gap = TRUE
      )
    )
  ),
  
  server = function(input, output, session) {
    
    # update mode
    observeEvent(input$dark, ignoreInit = TRUE, {
      updateF7App(
        options = list(
          dark = ifelse(input$dark == "dark", TRUE, FALSE)
        )
      )
    })
    
    # update color
    observeEvent(input$color, ignoreInit = TRUE, {
      updateF7App(
        options = list(
          color = input$color
        )
      )
    })
    
    # update tabs depending on side panel
    observeEvent(input$menu, {
      updateF7Tabs(id = "tabs",
                   selected = input$menu,
                   session = session)
    })
    
    # Display selected day
    output$day_output <- renderText({
      paste("Selected day:", input$select_day)
    })
    
    # Display selected time
    output$time_output <- renderText({
      paste("Selected time:", input$select_time)
    })
  }
)