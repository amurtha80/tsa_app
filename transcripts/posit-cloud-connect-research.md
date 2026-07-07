Posit Cloud Connect research 

Posit has a new hosting site and is shifting away from Shiny apps.io. new site is called Cloud Connect.

Please go research the site and produce a list of steps I would need to take to shift my app from my own computer to cloud connect.

I would consider the $19/month plan


Searched the web
Searched the web
Good enough — I have what I need. The plans page is a JS-rendered wall that won't fetch cleanly, but I have the key specs from the beta blog post and docs. Let me also note one important ASAP-specific wrinkle before writing the steps: Connect Cloud deploys from GitHub, not from a local machine via rsconnect. That's a meaningful difference from shinyapps.io. The DuckDB path issue in app_sidebar.R also needs to be called out explicitly.


Fetched: Deploy a Shiny Application with R to Connect Cloud – Posit Connect Cloud Documentation
Fetched: Deploy a Shiny Application with R to Connect Cloud – Posit Connect Cloud Documentation
Good — I have everything I need. Let me write this up clearly.

Posit Connect Cloud — Migration Steps for ASAP
First, a key orientation point: Connect Cloud is GitHub-first, not rsconnect-first. Unlike shinyapps.io where you pushed directly from R, Connect Cloud pulls your code from a GitHub repo and builds it in the cloud. That changes the workflow meaningfully for ASAP.

What Connect Cloud Is (and Isn't)
Posit is migrating all shinyapps.io users to Connect Cloud by end of 2026, so this migration is coming regardless. Connect Cloud is Posit's next-generation online publishing platform — deploy Shiny apps from GitHub in under a minute, with a public portfolio, secret environment variable management, and automatic push-to-publish. 
Posit Community
Posit

The $19/month plan is the Basic tier. Basic Plan gives you 8GB memory, 2 CPUs, and 100 active hours — ideal for broader dissemination. Basic also supports deploying from private GitHub repositories. For ASAP that's important since your repo is currently public, but good to have private as an option. 
Posit

One important limitation: Connect Cloud is now available as a publishing target in RStudio 2026.04.0 "Globemaster Allium" released April 22, 2026 — you can publish directly from the IDE using the Publish button with no GitHub repository required. But the primary workflow remains GitHub-based. 
Posit

ASAP-Specific Pre-Work (Do This Before Touching Connect Cloud)
These are blockers specific to your app that must be resolved first.

1. Fix the hardcoded DB path in app_sidebar.R

The current line:

r
db_path <- here::here("01_Data", "tsa_app_summ.duckdb")
here::here() resolves relative to your local Windows machine. On Connect Cloud, there's no local filesystem. Your DuckDB summary file needs to either be bundled with the app (committed to the repo) or replaced with a different data source strategy.

Two options:

Bundle the DB: Commit tsa_app_summ.duckdb into the repo (remove 01_Data/ from .gitignore selectively, or move the summary DB to a non-ignored location like 03_App/data/). Connect Cloud will have it at deploy time but it won't auto-update.
Export to CSV/parquet nightly: Have xx_build_summary_db.R also write a flat file (e.g., tsa_wait_time_summ.parquet) that gets committed to the repo, and read that in the app instead of DuckDB. Much simpler for cloud hosting.
The CSV/parquet route is the more practical path given your architecture. The scraper still writes to your local DuckDB; the ETL just also exports a flat summary file to the repo folder.

2. Remove the shiny::runApp() call at the bottom of app_sidebar.R

r
shiny::runApp(
  shinyApp(ui = ui, server = server),
  host = "0.0.0.0",
  port = 3838
)
Connect Cloud expects shinyApp(ui, server) as the last expression, not runApp() with host/port args. Strip that down to just:

r
shinyApp(ui = ui, server = server)
3. Confirm ggrounded is on CRAN

The manifest.json approach only captures CRAN packages cleanly. Verify ggrounded is installable from CRAN (not GitHub-only) before generating the manifest. If it's GitHub-only, you'll need to handle it as a private package dependency.

Step-by-Step Migration
Step 1 — Sign up for Connect Cloud

Go to connect.posit.cloud, create an account, and select the Basic plan ($19/month). Connect your GitHub account when prompted.

Step 2 — Grant Connect Cloud access to your repo

Install the Connect Cloud GitHub App and grant it access to your tsa_app repository. Free users can only use public repos; paid users can use private repos. Since your repo (amurtha80/tsa_app) is public, this is straightforward. 
posit

Step 3 — Prep the app code (pre-work above)

Apply the two code fixes above — remove the runApp() wrapper and fix the DB path. Commit those changes to your repo.

Step 4 — Generate manifest.json

A manifest.json file is required for all R deployments on Connect Cloud. Generate it with rsconnect::writeManifest(), which captures the R version and all package dependencies. The file should live in the root directory or the same subdirectory as your primary app file. 
posit

Run this in your project root:

r
rsconnect::writeManifest()
Commit the resulting manifest.json to the repo. This file must stay updated — re-run writeManifest() any time you add or update a package.

Step 5 — Commit and push everything to GitHub

Make sure manifest.json, the fixed app_sidebar.R, and your summary data file (if bundled) are all pushed to the main branch.

Step 6 — Publish from Connect Cloud

Log in to Connect Cloud, click the Publish icon, select Shiny, select your repository, confirm the branch, select app_sidebar.R (or whatever your primary file is named) as the primary file, and click Publish. Build logs stream during deployment. 
posit

Step 7 — Enable auto-republish (optional but useful)

When you publish from GitHub, automatic republishing is enabled by default — any time you push changes to the connected branch, Connect Cloud will detect the update and redeploy automatically. You can disable this from the Content Settings page. 
posit

This is useful for the data refresh problem: if you go the flat-file route, your nightly ETL can push an updated summary file to GitHub, which triggers an automatic redeploy with fresh data.

Key Things to Know About the Basic Plan
100 active hours/month — this is compute time while the app is actively serving a user session, not clock time. For a low-traffic MVP app, 100 hours should be more than enough.
8GB RAM, 2 CPUs — well above what app_sidebar.R needs for a read-only Shiny app.
Private repo support — included, so you can make the repo private if you want.
No custom domain — that's Enhanced plan only. Your URL will be a connect.posit.cloud/... subdomain.
Custom domains are available on Enhanced or Enterprise plans. 
Posit
The Data Refresh Problem (Important)
This is the biggest architectural gap. Your scrapers run locally every 5 minutes and write to a local DuckDB. The ETL builds tsa_app_summ.duckdb nightly. Connect Cloud can't reach your local machine.

Your options, from simplest to most complex:

Manual re-deploy: Nightly ETL writes a flat file, you push it to GitHub, auto-republish fires. Works but requires the scraper machine to have git access.
GitHub Actions: Schedule a GitHub Action to run the ETL and commit the updated summary file nightly. Requires porting the R ETL to run in a GitHub Actions runner (doable but needs setup).
AWS long-term: Your existing plan for eventual migration to AWS is the right call for the full two-database architecture. Connect Cloud is a good intermediate step for the Shiny frontend while the scraping pipeline stays local.
For MVP, option 1 is the pragmatic choice — add a git push at the end of xx_build_summary_db.R and let auto-republish handle the rest.








Claude is AI and can make mistakes. Please double-check cited sources.







