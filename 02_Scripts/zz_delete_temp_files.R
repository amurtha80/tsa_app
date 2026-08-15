
# Delete orphaned chromote/renv temp dirs. Location and pattern differ by
# platform: Windows chromote writes separate HeadlessChrome*-prefixed dirs
# alongside Rtmp*; on the Pi, chromote nests its logs inside R's own Rtmp*
# session dir instead (confirmed 2026-08-14 investigation, no standalone
# HeadlessChrome* dirs found there), so only the Rtmp* pattern is needed.
on_windows <- Sys.info()[["sysname"]] == "Windows"
temp_dir   <- if (on_windows) "C:/Users/james/AppData/Local/Temp" else "/tmp"
pattern    <- if (on_windows) "^(HeadlessChrome|Rtmp)" else "^Rtmp"

files_to_delete <- list.files(path = temp_dir,
                              pattern = pattern,
                              full.names = TRUE)

# check to see whether there are any elements in the vector
# If so then delete them, otherwise print a message to the console
if (length(files_to_delete) == 0) {
  message("No matching files or folders found.")
} else {
  n_total <- length(files_to_delete)

  unlink(files_to_delete, recursive = TRUE, force = TRUE)

  # unlink() returns a single 0/1, not a per-file result, so check what's
  # actually still there to know how many failed (still locked, etc.)
  n_fail    <- sum(file.exists(files_to_delete))
  n_success <- n_total - n_fail

  message(glue::glue("{n_success} item(s) deleted, {n_fail} item(s) failed (likely locked by active process)."))
}

