
# Navigate to the following directory and delete files that begin with the following prefixes:
# 'HeadlessChrome' and 'Rtmp'
# Folder location: "C:\Users\james\AppData\Local\Temp"
files_to_delete <- list.files(path = "C:/Users/james/AppData/Local/Temp", 
                              pattern = "^(HeadlessChrome|Rtmp)", 
                              full.names = TRUE)

# check to see whether there are any elements in the vector
# If so then delete them, otherwise print a message to the console
if (length(files_to_delete) == 0) {
  message("No matching files or folders found.")
} else {
  results <- unlink(files_to_delete, recursive = TRUE, force = TRUE)
  
  n_success <- sum(results == 0)
  n_fail    <- sum(results != 0)
  
  message(glue::glue("{n_success} item(s) deleted, {n_fail} item(s) failed (likely locked by active process)."))
}

