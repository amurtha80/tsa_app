# Shutdown connection from background jobs (if possible???)
# dbDisconnect(con_write, shutdown = TRUE)

# Alternative implementation to chromote package (prior to next chromote update
# as of March 2025)
# as per https://github.com/JayeshSChauhan, I should not be using read_live_html()
# from the rvest package.


# library(polite)
# library(glue)
# library(rvest)
# library(chromote)
# 
# print(glue("kickoff DCA scrape ", format(Sys.time(), "%a %b %d %X %Y")))
# 
# url <- 'https://www.flyreagan.com/travel-information/security-information' # Update with the actual URL
# 
# session <- polite::bow(url)
# 
# b <- ChromoteSession$new()
# b$Page$navigate(url)
# Sys.sleep(5) # Allow time for the page to load
# 
# html_content <- b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
# page <- read_html(html_content)
# 
# b$close()