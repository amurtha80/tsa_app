
# Delete orphaned chromote/renv temp dirs. Location and pattern differ by
# platform: Windows chromote writes separate HeadlessChrome*-prefixed dirs
# alongside Rtmp*. On the Pi, R's own Rtmp* dirs land in /tmp, but chromote
# runs through the snap-confined chromium binary (arm64 has no CfT builds,
# see 2026-08-12 fix), which sandboxes its per-session profile dirs to
# ~/snap/chromium/common/chromium-headless/scoped_dir* instead of /tmp -
# confirmed 2026-08-24 after 775 orphaned dirs (8.3GB) accumulated there
# uncleaned since this script only ever targeted /tmp/Rtmp*.
on_windows <- Sys.info()[["sysname"]] == "Windows"
if (on_windows) {
  targets <- list(list(dir = "C:/Users/james/AppData/Local/Temp",
                        pattern = "^(HeadlessChrome|Rtmp)"))
} else {
  targets <- list(list(dir = "/tmp", pattern = "^Rtmp"),
                   list(dir = "~/snap/chromium/common/chromium-headless",
                        pattern = "^scoped_dir"))
}

files_to_delete <- unlist(lapply(targets, function(t) {
  list.files(path = path.expand(t$dir), pattern = t$pattern, full.names = TRUE)
}))

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

