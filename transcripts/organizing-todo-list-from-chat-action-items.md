todo_list.txt cleanup

For the high priority mvp section, all items have been completed. 

Pull action items from the end of the following chats and put into high priority section:

Scaling Shiny apps for concurrent users
AWS vs shinyapps.io hosting comparison

Let me search those conversations first.


Searched memory
Searched memory
Good, I have a clear picture. Let me now look at the current TODO to make the right edits.


Reading current todo_list.txt
Reading current todo_list.txt
Here's what I found and what I'm doing:

High Priority — MVP App: All 5 existing items are done per your instruction. Replacing them entirely.

From the scaling chat: bindCache() + cache_mem() on both renderPlot() calls; 12-hour time format for bucket_label; parquet output + S3 push via paws in xx_build_summary_db.R; parquet read via nanoparquet replacing DuckDB in app_sidebar.R.

From the AWS chat: EC2 provisioning + Ubuntu setup; R + Shiny Server OSS install; nginx reverse proxy; Let's Encrypt SSL; Route 53 DNS for flyasap.app; IAM scoping EC2 read-only to S3 bucket; EC2 cron to pull nightly parquet + restart Shiny; check business AWS account free-tier eligibility before provisioning; verify format(as.POSIXct("2000-01-01 00:00:00"), "%I:%M %p") produces "12:00 AM" not "00:00 AM" on Windows locale before deploying.


Edited a file, viewed a file
Edited a file, viewed a file
Looks clean. Here's what changed and why:

The old High Priority section was wiped since all 5 items were done. The new section has three subsections pulled from those two chats:

App Performance — the two bindCache() / cache_mem() items from the scaling chat, plus the Windows locale verification that was flagged as a pre-deploy check before any of this ships.

Data Pipeline — the parquet-via-S3 workflow that replaces DuckDB on EC2, spanning both xx_build_summary_db.R (write + push) and app_sidebar.R (read). These were decided in the scaling chat and confirmed as complete architecture in the AWS chat — but the code changes haven't been made yet per the AWS chat's closing summary.

AWS Infrastructure — the full ordered list of provisioning steps from the AWS chat's end, including the business account free-tier check as the first item since it affects the instance choice.

Everything else — Active Script Bugs, New Airports, Housekeeping — was untouched.

show me the current todo_list.txt you created


Reading current todo_list.txt to display to user
Reading current todo_list.txt to display to user
Here it is. To be clear — this is the read-only copy in the Claude project. The edits I made in the previous turn exist in this session's working copy only. You'll need to paste the content above into tsa_app/TODO.md in your local repo to make it permanent.








Claude is AI and can make mistakes. Please double-check responses.







