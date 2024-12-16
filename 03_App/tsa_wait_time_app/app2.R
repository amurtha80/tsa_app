library(shiny)
library(shinyMobile)
library(dplyr)
library(ggplot2)
library(scales)


# Shiny App Options ----
app_opts <-   list(
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
  
  ui <- f7Page(
    
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
        title = "ASAP - Aiport Security Advance Planning",
        hairline = TRUE,
        leftPanel = FALSE,
        rightPanel = TRUE
      ),
      
      br(),
      br(),
      # f7Block(inset = FALSE, tablet = FALSE, strong = FALSE, "\n 1\n 2\n 3\n"),
      
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
          # f7BlockHeader(text = "Header"),
          "Something about the purpose of the ShinyMobile App. Continue by telling
          the user how to navigate the app and what you will get after choosing
          the search criteria."
          # ,f7BlockFooter(text = "Footer")
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
          # f7Button(inputId = "update", label = "Update select"),
          # br(),
          # f7List(
            title = "Day of Week Selection",
            f7Select(
              inputId = "select",
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
          # ),
          verbatimTextOutput("test")
        ),
        f7Card(
          # f7Button(inputId = "update", label = "Update select"),
          # br(),
          # f7List(
          title = "Time Slot Selection",
          f7Select(
            inputId = "select",
            label = "Choose a Time Slot:",
            choices = c('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday',
                        'Friday', 'Saturday'),
            selected = "Sunday",
            style = list(
              description = "time slot selection",
              media = f7Icon("clock"),
              outline = TRUE
            )
          ),
          # ),
          verbatimTextOutput("test")
        ),
        cols = 2, 
        gap = TRUE, 
        responsiveCl = "<medium-2>"
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
    
    # Grab Airport Input
    # output$autocompleteval <- renderText(input$myautocomplete)
    # 
    # observeEvent(input$update, {
    #   updateF7AutoComplete(
    #     inputId = "myautocomplete",
    #     value = "plip",
    #     choices = c("plip", "plap", "ploup")
    #   )
    # })
  }

)
