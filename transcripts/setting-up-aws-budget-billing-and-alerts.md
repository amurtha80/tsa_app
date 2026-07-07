Deployment todo list item:

Lets work on the following:
- Set up AWS Budget alert and AWS Billing alert

Please walk me through how to complete this task. Feel free to push all instructions at once, I have gotten a lot better in the AWS console, so if something goes wrong while following the instructions, I will reach out.

AWS Budget & Billing Alerts Setup
Two separate things to configure: a Budget alert (triggers when you're forecasted to exceed a spending threshold) and a Billing alert (CloudWatch alarm on actual charges). You want both — they catch different failure modes.

Part 1 — Enable Billing Alerts (one-time account setting)
Before CloudWatch billing alarms work, you have to opt in at the account level.

Sign into the AWS Console as your root account (not an IAM user — this setting requires root)
Click your account name (top right) → Account
Scroll down to Billing preferences
Check Receive Billing Alerts → Save preferences
This unlocks CloudWatch billing metrics. You only do this once.

Part 2 — AWS Budget Alert
Budgets let you set a monthly spending cap and get emailed before you hit it.

In the AWS Console, search for Budgets (it's under Billing & Cost Management)
Click Create budget
Choose Use a template (simplified) → select Monthly cost budget
Fill in:
Budget name: flyasap-monthly-budget
Budgeted amount: whatever your monthly ceiling is — I'd suggest $25 to start given you're on a t3.medium with light traffic; adjust once you have a few weeks of actual spend data
Email recipients: your email address
Click Create budget
This sends you an alert at 85% of budget (forecasted) and 100% (actual) by default. You can customize thresholds after creation.

Part 3 — CloudWatch Billing Alarm
This is a harder stop — it fires on actual charges, not forecasts. Think of it as a backstop.

Search for CloudWatch in the console
Important: Switch your region to US East (N. Virginia) — us-east-1 using the region dropdown (top right). Billing metrics only exist in us-east-1 regardless of where your EC2 lives.
In the left sidebar: Alarms → All alarms → Create alarm
Click Select metric → Billing → Total Estimated Charge → check the box next to EstimatedCharges (currency: USD) → Select metric
Configure the alarm:
Statistic: Maximum
Period: 6 hours
Threshold type: Static
Condition: Greater than
Value: 20 (set this a few dollars below your budget ceiling so it fires before your Budget alert would)
Click Next → Create new topic
Topic name: flyasap-billing-alarm
Email: your address
Click Create topic
Check your email — AWS will send a subscription confirmation; you must click the link or the alarm will never notify you
Click Next → name the alarm flyasap-billing-alarm → Create alarm
After You're Done
Once both are set up, remove the TODO item and I'll update the changelog and todo list.

One thing to check: the Budget alert email and the CloudWatch SNS subscription confirmation both need to be clicked/confirmed in your inbox before they're active. Easy to miss.

Self-critique: I didn't ask what your actual monthly spend looks like before suggesting $25 and $20 as thresholds — those are reasonable guesses for a t3.medium + S3 + data transfer but could be wrong for your situation. If you've already got a month of AWS bills, set the budget to 20–30% above your highest month rather than a round number. Also, the root account requirement for Part 1 is worth flagging more prominently — if you normally work as an IAM user and don't have root credentials handy, that's a blocker for step 1 specifically.

Before taking any action, please head to the files section and review the updated todo_list.txt and changelog.md files. 

Once you have done that, please update the todo_list.txt and also provide the snippet that needs to be added to the changelog.md file.

Thank you for your help on this overall task of setting up the budget and billing alerts


Viewed 2 files
Viewed 2 files
Both files are current — no surprises. Here's what you need.

Updated todo_list.txt
Remove the entire #### AWS Infrastructure subsection (the item is done, and the subsection header goes away with it since it's now empty):

# tsa_app
RShiny Mobile App TSA Historical Wait Times

---

## TODO

### High Priority — Post-Launch Fixes

#### Deployment
- Add third chart for CLEAR lane wait times for airports that have CLEAR data (MIA; others TBD) — chart should only render when data exists for the selected airport/checkpoint combination
- For any charts that are blank, place a textholder stating that there isn't a (precheck/clear) gate for this checkpoint

### Active Script Bugs
- **DEN Pre-Check** — missing early morning data (4 AM - 10 AM) despite checkpoint opening at 4 AM; investigate whether scraper was running during those hours or whether data was lost during aggregation
- **CLT** — Checkpoint names from API no longer fully align with page display names; wait times don't align between API and page (page shows ranges, API shows point values)
- **WebSocket warning** — suppress `"got non-close frame while closing"` warning during chromote teardown across all chromote scripts

### New Airports (Lower Priority — Post MVP)
- **DFW** - `DFW_in_progress.R` drafted; needs to be updated to run off of API or JSON data within Fetch/XHR from site load
- **BOS** — `BOS_wait_times.R` drafted; needs test run to confirm Zensors API Origin allowlist check passes from R; fallback is chromote approach if 403 persists
- **PHL** - `phl.org`; should need no chromote, has a metric json file and there is a js script matching wait-api.js?th8s81 to map zone ID to checkpoint and pull wait times
- **LAX** — `flylax.com/wait-times`; static HTML, no chromote needed; straightforward `read_html()` scrape
- **SEA** — `portseattle.org/page/live-estimated-checkpoint-wait-times`; JS-rendered table, chromote approach
- **SLC** — `slcairport.com`; JS-rendered widget, investigate for API endpoint before falling back to chromote
- **DTW** — `metroairport.com`; Angular/Vue app, likely REST API behind it; inspect via DevTools before building script

### Housekeeping
- Update and format README for GitHub
- Archive unused scripts (`scrape_data.R`, `scrape_data_error_test.R`, `zz_misc.R`, `zz_test.R`)
- Move `scrape_test.R` from project root into `02_Scripts/`
- Standardize scraping function naming convention
- Remove stale `# TODO: replace bucket name` comment from `xx_build_summary_DB.R` line 109
Changelog snippet — paste at the top of the ## 2026-06-26 section
The 2026-06-26 entry already exists with the IAM scoping item. Add this as a second bullet under ### AWS Infrastructure:

markdown
- AWS Budget alert configured (`flyasap-monthly-budget`): monthly cost budget with email notification at 85% forecasted and 100% actual spend
- CloudWatch billing alarm configured (`flyasap-billing-alarm`): fires on `EstimatedCharges` exceeding threshold; SNS topic `flyasap-billing-alarm` delivers email notification; billing alerts opt-in enabled at account level (requires root); alarm scoped to us-east-1 (required region for billing metrics)
The full updated ## 2026-06-26 block will look like this:

markdown
## 2026-06-26

### AWS Infrastructure
- `flyasap-windows` IAM user scoped to `flyasap-app-data` bucket only via inline policy `flyasap-windows-s3-scoped`; policy grants `s3:PutObject` on `arn:aws:s3:::flyasap-app-data/*` and `s3:ListBucket` on `arn:aws:s3:::flyasap-app-data`; any previously attached broad S3 managed policies removed
- AWS Budget alert configured (`flyasap-monthly-budget`): monthly cost budget with email notification at 85% forecasted and 100% actual spend
- CloudWatch billing alarm configured (`flyasap-billing-alarm`): fires on `EstimatedCharges` exceeding threshold; SNS topic `flyasap-billing-alarm` delivers email notification; billing alerts opt-in enabled at account level (requires root); alarm scoped to us-east-1 (required region for billing metrics)
Self-critique: The changelog entry omits the specific dollar thresholds you set (since I don't know what you actually configured — I only suggested $25/$20 as starting points). If you want those in the changelog for future reference, add them to the bullet. Something like ...exceeding $20 after "exceeding threshold." That specificity would be useful if you ever revisit the alarm settings six months from now.

thank you for helping with this task.

You're welcome! The AWS cost guardrails are a good one to have in place early — easy to forget until you get a surprise bill.

Good luck with the remaining items. The CLEAR lane chart and the CLT script bug look like the meatiest things left on the post-launch list whenever you're ready to dig back in.








Claude is AI and can make mistakes. Please double-check responses.







