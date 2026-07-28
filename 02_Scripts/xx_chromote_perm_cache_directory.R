# If you ever have to fall back on chromote, the reason it is eating your disk space is because every time you call ChromoteSession$new(), it spawns a fresh profile directory in your tempdir() and often fails to kill the background executable process on exit.To stop the hard drive leak completely, you must force chromote to reuse a single, permanent cache directory instead of spawning new ones, and force a hard garbage collection clean-up:

# Fix the Chromote disk leak by forcing a single, static profile path
static_profile <- file.path(Sys.getenv("USERPROFILE"), "chromote_cache") # Windows
# static_profile <- "~/chromote_cache" # Mac/Linux

# Create it if it doesn't exist
if (!dir.exists(static_profile)) dir.create(static_profile)

# Start chromote using that exact single folder so it never fills your temp space
b <- ChromoteSession$new(
  browser = Chromote$new(
    args = c("--headless", paste0("--user-data-dir=", static_profile))
  )
)

# ... Do your scraping work here ...

# BRUTAL CLOSURE PROTOCOL (Ensures background processes actually die)
b$close()
gc() # Forces R to release the background pointer locks immediately
