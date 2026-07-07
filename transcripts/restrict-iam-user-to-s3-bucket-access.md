Deployement todo list item:

Lets work on the following:

Lock flyasap-windows IAM user to flyasap-app-data bucket only
Please walk me through how to complete this task. Feel free to push all instructions at once, I have gotten a lot better in the AWS console, so if something goes wrong while following the instructions, I will reach out.

Let me read the current files before anything else.


Viewed 2 files
Viewed 2 files
Good. Here's the full walkthrough.

Locking flyasap-windows to flyasap-app-data bucket only
What you're doing: Attaching an inline policy directly to the flyasap-windows IAM user that explicitly allows only the S3 actions that xx_build_summary_DB.R needs (s3:PutObject on the bucket), and nothing else. If flyasap-windows currently has broader permissions (e.g., AmazonS3FullAccess or AdministratorAccess), you'll remove those too.

Step 1 — Check what permissions flyasap-windows currently has
Go to IAM → Users → flyasap-windows
Click the Permissions tab
Note what policies are attached. Common culprits to look for:
AmazonS3FullAccess
AmazonS3ReadOnlyAccess
AdministratorAccess
Any inline policy already present
Keep this tab open — you'll come back to remove the broad ones in Step 3.

Step 2 — Create a scoped inline policy
Still on the flyasap-windows Permissions tab:

Click Add permissions → Create inline policy
Switch to the JSON editor tab
Paste this policy:
json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPutToFlyasapBucket",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::flyasap-app-data/*"
    },
    {
      "Sid": "AllowListFlyasapBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::flyasap-app-data"
    }
  ]
}
Click Next
Name it flyasap-windows-s3-scoped
Click Create policy
Why two statements? PutObject operates on objects (arn:.../*), so it needs the /* suffix. ListBucket operates on the bucket itself (arn:... without /*). You don't strictly need ListBucket for the current script, but paws sometimes makes a list call under the hood and it's a read-only no-risk permission. If you want it tighter, you can drop the second statement entirely and just keep PutObject.

Step 3 — Remove any overly broad policies
Back on the Permissions tab, for each broad managed policy you found in Step 1:

Click the checkbox next to it
Click Remove (or the trash icon, depending on your console version)
Confirm
If flyasap-windows had no previously attached policies (it was a fresh user whose only permissions came from the .Renviron credentials), you're done — the inline policy is sufficient.

Step 4 — Verify
The quickest verification is to check whether the nightly pipeline still works after the next 2 AM run. If you want to test sooner without waiting:

On the flyasap-windows Permissions tab, click the Simulate button (or use the IAM Policy Simulator at https://policysim.aws.amazon.com)
Select user flyasap-windows, choose service S3, action PutObject, resource arn:aws:s3:::flyasap-app-data/tsa_app_summ.parquet
Run simulation — should say Allowed
Try the same for S3 → DeleteBucket or S3 → DeleteObject — should say Denied
Alternatively, you can manually run xx_build_summary_DB.R from your Windows machine and confirm the S3 push log line appears: parquet pushed to S3 at ....

What this does NOT lock down (intentionally deferred)
The EC2 instance uses the flyasap-ec2-s3-read IAM role — that's separate from flyasap-windows and not touched here. The EC2 role only needs s3:GetObject to pull the parquet down, which is a separate concern.

After you're done
Once confirmed working, I'll remove the TODO item and add a CHANGELOG entry. Let me know how it goes.

Self-critique: The ListBucket statement is a judgment call I made without asking you — if you want the absolute minimum permissions, drop it and only keep PutObject. The instructions could also be more explicit about what to do if flyasap-windows has no pre-existing managed policies (the user might have been created with no permissions at all, relying purely on the access key credentials, in which case Step 3 is a no-op). I should have flagged that branch explicitly rather than burying it in a parenthetical.

Confirmed working, please provide an updated copy of todo_list.txt and provide a snippet for the updates that need to be added to the changelog.md file


Reading current CHANGELOG
Reading current CHANGELOG
Here are both files.

CHANGELOG snippet — paste at the top, below the --- after the header:
markdown
## 2026-06-26

### AWS Infrastructure
- `flyasap-windows` IAM user scoped to `flyasap-app-data` bucket only via inline policy `flyasap-windows-s3-scoped`; policy grants `s3:PutObject` on `arn:aws:s3:::flyasap-app-data/*` and `s3:ListBucket` on `arn:aws:s3:::flyasap-app-data`; any previously attached broad S3 managed policies removed

---
Full updated todo_list.txt:
markdown
# tsa_app
RShiny Mobile App TSA Historical Wait Times

---

## TODO

### High Priority — Post-Launch Fixes

#### Deployment
- Add third chart for CLEAR lane wait times for airports that have CLEAR data (MIA; others TBD) — chart should only render when data exists for the selected airport/checkpoint combination

#### AWS Infrastructure
- Set up AWS Budget alert and AWS Billing alert

### Active Script Bugs
- **DEN Pre-Check** — missing early morning data (4 AM - 10 AM) despite checkpoint opening at 4 AM; investigate whether scraper was running during those hours or whether data was lost during aggregation
- **CLT** — Checkpoint names from API no longer fully align with page display names; wait times don't align between API and page (page shows ranges, API shows point values)
- **WebSocket warning** — suppress `"got non-close frame while closing"` warning during chromote teardown across all chromote scripts

### New Airports (Lower Priority — Post MVP)
- **BOS** — `BOS_wait_times.R` drafted; needs test run to confirm Zensors API Origin allowlist check passes from R; fallback is chromote approach if 403 persists
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
The only change to the TODO is removing the flyasap-windows IAM line from the AWS Infrastructure section. The trailing - at the bottom of the original file was a formatting artifact — I dropped it in the cleaned copy.

Self-critique: I dated the changelog entry 2026-06-26 based on today's date, but you may have completed this yesterday or want a different date — adjust if needed. The changelog entry is also slightly more verbose than some prior entries in that file; it could be condensed, but given that IAM policy details are easy to forget later, the specificity is probably worth keeping.

Task complete, thank you for your help

You're welcome! Good progress today — the IAM scoping is one of those housekeeping items that's easy to defer but important to have locked down before the app gets more traffic. One less thing to worry about.

Whenever you're ready to pick up the next item, the remaining AWS Infrastructure task (Budget and Billing alerts) is a natural follow-on, or you could pivot to the CLEAR chart feature if you want to work on the app itself. Either way, just let me know.








Claude is AI and can make mistakes. Please double-check responses.







