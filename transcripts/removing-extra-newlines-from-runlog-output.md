silly request how can I get the spacing out of the runlog. After all the script updates I now have a lot of newline whitespace in my log, and this didn't use to be the case. Is there something happening when the log messages print that cause the newline whitespace to print between the kickoff of each script and the confirmation of each script (2 newlines between kickoff and confimation)

Let me look at the relevant files first.


Check scrape_data_automate.R for sink and print setup
Check scrape_data_automate.R for sink and print setup
The culprit is print() vs cat() + glue(). Here's what's happening:

print() in R always appends a trailing newline, and glue() itself also produces a string that ends with a newline when used inside print(). So each print(glue(...)) call is emitting two newlines — one from glue's default behavior (it collapses with \n) and one from print(). That doubles up in the sink log.

The fix is simple: replace print(glue(...)) with cat(glue(...), "\n") in the scraping functions. cat() writes exactly what you give it, no extra newline added.

Two options depending on how much you want to touch:

Option A — Minimal: change only the orchestrator's Start/Completed prints (the two bookend lines in run_all_functions()):

r
cat(glue("******-- Start Run ", format(Sys.time()), " --******"), "\n")
# ...
cat(glue("******-- Completed Run ", format(Sys.time()), " --******"), "\n")
Option B — Full fix: also change the kickoff and confirmation prints in each airport script

Replace every instance of:

r
print(glue("kickoff XXX scrape ", format(Sys.time(), "%a %b %d %X %Y")))
print(glue("{nrow(XXX_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
with:

r
cat(glue("kickoff XXX scrape ", format(Sys.time(), "%a %b %d %X %Y")), "\n")
cat(glue("{nrow(XXX_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")
Option B gets you clean single-line-per-message output. Option A stops the double-spacing between runs but still leaves one blank line per script pair.

Worth knowing: message() (used in safe_read_html_live) writes to stderr, which sink(type = "output") doesn't capture anyway — so those calls aren't contributing to the log noise.







Claude is AI and can make mistakes. Please double-check responses.







