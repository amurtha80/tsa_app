Make shiny app more performant for more concurrent users.

Here are a few resources to review before we begin our conversation:

Chapter 23 Performance | Mastering Shiny https://share.google/6JaJyPehKQM7c24at

4 Tips to Make Your Shiny Dashboard Faster | Posit https://share.google/3tA8XMMKyfwsJ63oz

Scaling R Shiny: How We Built a Shiny App for 700 Users https://share.google/iH8mR8X3lugsui55R

Chapter 16 Optimizing {shiny} Code | Engineering Production-Grade Shiny Apps https://share.google/e7LzFRf1zEHNvmWqC

https://youtu.be/Eqlh3iE1BiU?is=xUGH5l-wFAO_krtz

This last video would be interesting as it's a use case on 100k users

Show more
Let me read the resources you shared before we discuss anything.


Searched the web
Searched the web
Good, I've read all four resources. The YouTube link I can't fetch but I have enough from the other four. Let me now look at app_sidebar.R carefully before forming my assessment.


Reading app_sidebar.R to assess current performance characteristics
Reading app_sidebar.R to assess current performance characteristics

Reading app_sidebar.R to assess current performance characteristics
Done
Good. I have a complete picture now. Let me be direct with my analysis before proposing anything.

Assessment: what's actually happening in this app
First, a frank reality check on scale. The resources you sent are aimed at apps with hundreds to thousands of concurrent users. ASAP at MVP stage is unlikely to see more than a handful. But the patterns from those resources still matter — and a few of them apply directly right now with zero cost.

What the app is doing per user session:

summ_data is loaded from DuckDB once at app startup (lines 36–44), outside the server function. This is already correct — it's the single most important scoping rule. All users share this in-memory data frame. ✅
Every time a user changes any input, filtered_data() re-filters the in-memory data frame. That filter runs on ~9 rows of output from what's likely a small table. This is fast enough that it's not a bottleneck. ✅
The real cost per user interaction: two renderPlot() calls. ggplot2 renders are the dominant expense. Each input change triggers two full ggplot builds — chart_std and chart_pre — using the same filtered_data() and the same subtitle. The plots are identical except for which column pair (avg_time_std/max_time_std vs avg_time_tsa_precheck/max_time_tsa_precheck) they display.
filtered_data() is computed twice per interaction — once inside output$chart_std and once inside output$chart_pre, because both renderPlot blocks call filtered_data() independently. Shiny's reactivity means this is actually one computation (reactive caches its last result), but the ggplot builds are two separate full renders. ✅/⚠️
output$navbar_ui <- renderUI() rebuilds the entire navbar HTML on every accent_color change. This is minor but unnecessary for users who never touch settings.
The three changes worth making, ranked by impact
1. bindCache() on both renderPlot() calls — highest impact

This is the single biggest win from Mastering Shiny Ch. 23. The cache is shared across all user sessions. If user A renders ATL / INT'L MAIN / Mon / 08:00 with Teal, every subsequent user requesting the same combination gets the plot from memory instantly — no ggplot build at all. The cache key is the full combination of inputs that uniquely determine the plot.

The catch: accent_hex() is part of what determines the visual output, so it must be in the cache key too.

2. Pre-compute checkpoints_by_airport lookup outside server()

Currently, every time a user changes airport, the server filters summ_data to find checkpoint names. This is cheap but runs once per session per airport change. Better: build the lookup once at startup.

3. subtitle duplication — minor

Both renderPlot blocks construct the same subtitle string. This is trivial but worth cleaning up.

What I am NOT recommending (and why)
future/promises async: The bottleneck here is ggplot rendering, not I/O or long-running computation. Async solves cross-session blocking from slow operations. It adds substantial complexity for no benefit in this app's current state.
Separate data prep script: Already done — xx_build_summary_db.R runs nightly and summ_data loads at startup. This is correct.
memoise: bindCache() supersedes memoise for Shiny since v1.6.0. No reason to add both.
data.table indexing: The Appsilon 700-user article recommends this for large-scale filtering. summ_data is a small in-memory table. Premature optimization.
Assumptions I'm making — confirm before I write code
summ_data is small enough to fit comfortably in EC2 memory. The nightly summary aggregates to 15-min buckets by airport/checkpoint/weekday — probably a few thousand rows at most. If that's right, keeping it in memory at app level is correct and I won't change it.
The cache key for bindCache() should be (airport, checkpoint, day, time_slot, accent_color). The plots don't change with dark_mode (dark mode affects the bslib theme CSS, not the ggplot itself). Confirm this is right — do you want cached plots to be independent of dark/light mode?
You're okay with the default in-process cache (cachem::cache_mem(), 200MB limit, shared across all sessions in one process, lost on restart). Given you're on a single EC2 process for MVP, this is fine. Post-MVP with multiple workers you'd want cache_disk() for cross-process sharing. Confirm.
The subtitle cleanup is acceptable. I'd compute it once and pass to both charts. Small change, confirm you want it.
If all four assumptions are correct, I can write the exact surgical changes — probably 15–20 lines touched total, no rewrites.

1) currently with 12 airports and 365 days of data I think we are at 32208 rows and the number of columns, some of that data being NAs. As airports get added this will increase that file size. Will have to look at size but putting in parquet should be efficient.

2)yes for now let's have cached plots to be independent of light/dark mode

3)I am not familiar enough with #3 to provide an opinion, we should talk through this one more.

4)yes proceed with subtitle cleanup.

On that note we will need to provide more text later above the filters, but that is static and shouldn't affect performance.

Good. Let me work through assumption 3 before touching any code.

Assumption 3: Which cache to use
bindCache() needs somewhere to store the cached plots. Shiny gives you two built-in options:

cache_mem() — stores cached plots in RAM on the server process. Fast. Lost on restart. Shared across all user sessions within one process, but not across multiple worker processes.

cache_disk() — stores cached plots as files on disk. Survives restarts. Can be shared across multiple worker processes if they point to the same directory.

Here's the tradeoff in plain terms for your situation:

For MVP on a single EC2 process, cache_mem() works fine. Every user in that one process benefits from the same cache. When the app restarts (e.g. you redeploy), the cache is empty and rebuilds as users hit it — no big deal.

The question is: how expensive are the cache misses? A ggplot build for 9 bars is fast — probably 100–300ms per chart. Not painful. The cache is a nice-to-have, not a crisis fix. If the app restarts nightly (or you redeploy frequently), cache_disk() means users on day 2 still get cached plots from day 1.

However — and this is the part I want you to think about — your summary data rebuilds nightly via xx_build_summary_db.R. That means cached plots from yesterday are stale after the nightly build runs. With cache_mem() this is a non-issue (restart clears it). With cache_disk() you'd need to either clear the cache directory as part of the nightly build, or set a max_age parameter, otherwise users would get yesterday's plots from cache even though the data changed.

My recommendation: cache_mem() for MVP. Simple, zero configuration, zero stale-data risk. Revisit cache_disk() only when you're running multiple worker processes.

Two questions before I proceed:

Does the EC2 process restart nightly anyway (e.g. as part of how the nightly summary build gets picked up), or does the Shiny process stay alive continuously and just read new data from the rebuilt DuckDB?
On the parquet idea for summ_data: are you thinking of replacing the DuckDB summary database with a parquet file that the app reads at startup, or keeping DuckDB as the storage format and just noting parquet as a future option for the raw scrape data? I want to make sure I'm not scoping the wrong thing.
1) I have not built something like this before, so I would have to defer to documentation or best practices on whether or not the ec2 instance would get me started when the date assembly rebuild is updated.

Good — that's an honest answer and exactly the right thing to say. Let me think through this properly before recommending anything.

The stale cache problem, restated simply
The nightly build rewrites tsa_app_summ.duckdb. The app reads that file once at startup into summ_data. So the app already has a stale data problem that's independent of caching — if the app process stays alive overnight, users see yesterday's summaries until something restarts it.

This means the cache question and the data freshness question are actually the same question: what causes the app process to restart?

I don't know the answer to that yet, and neither do you. That's fine — but it means I shouldn't design the cache strategy around an assumption about restart behavior that hasn't been established yet.

What I'd need to know before recommending cache_mem vs cache_disk
Question 1: When the nightly xx_build_summary_db.R finishes writing the new DuckDB file, does the Shiny app automatically pick up the new data — or does someone (or something) need to restart the Shiny process?

This is a deployment architecture question. On EC2 with a bare R process managed by something like systemd, a restart is explicit — you'd add a systemctl restart shiny to the end of the nightly build script. The app wouldn't pick up new data otherwise.

If a nightly restart is already in the plan, cache_mem is the right call — zero config, zero stale risk. The cache empties on restart and rebuilds as users hit it.

If no restart mechanism exists yet, that's a gap that needs to be filled regardless of caching. We'd want to solve the data freshness problem first, then the cache choice falls out naturally.

My recommendation: decide the data freshness mechanism first
Before I write any cache code, I'd suggest we land on one of these two approaches:

Option A — Nightly restart (simplest): The nightly build script ends with a systemctl restart command (or equivalent). The app picks up fresh data on restart. Use cache_mem. No stale risk. This is the right MVP approach.

Option B — Hot reload without restart: The app polls for a new DB file or uses reactivePoll() to detect when tsa_app_summ.duckdb has been updated, then re-reads summ_data without restarting. More complex, no downtime. Use cache_mem but invalidate on reload. Post-MVP complexity.

Option A is the right answer for MVP. It's one line added to the nightly build script, it's operationally simple, and it solves data freshness and cache staleness in the same move.

What I can write right now without that decision
The two changes that are independent of the cache strategy:

Pre-compute the checkpoints_by_airport lookup once at startup instead of filtering summ_data per user per airport change.
Compute subtitle once inside the server and pass it to both chart renders instead of building it twice.
Both are surgical, low-risk, and don't interact with the cache question at all.

Do you want me to write those two now, and hold on bindCache() until we've confirmed the nightly restart approach?

One thing to add, I am seriously thinking about pushing a parquet file to the ec2 instance and letting shiny pick up the parquet file to read it, that way we don't have duck DB concurrency issues with the app.

Good instinct. Let me think through this out loud before we go anywhere near code.

What you're actually proposing
The nightly build script (xx_build_summary_db.R) currently writes a summary DuckDB file. You're considering having it instead write a parquet file, push that to EC2, and have the Shiny app read the parquet directly at startup — bypassing DuckDB on the app side entirely.

This is a legitimate architectural simplification, not a hack. Let me state what it changes:

DuckDB on EC2 (current plan): App connects to DuckDB at startup, reads into memory, disconnects. DuckDB is involved in the app's startup path. Any future concurrent read/write concern (even theoretical) touches DuckDB.

Parquet on EC2 (proposed): App reads a parquet file at startup with arrow::read_parquet() or nanoparquet::read_parquet(). No DuckDB involved on the EC2 side at all. DuckDB stays on your Windows laptop where it belongs — as the scraping database.

The DuckDB concurrency concern you're referencing is between the scraper writing to tsa_app.duckdb and the summary build reading it. That's a separate file from tsa_app_summ.duckdb, so the app was never in that race. But removing DuckDB from EC2 entirely is still cleaner — fewer moving parts, one fewer dependency to install on EC2, and parquet is a well-understood read-only format.

What I need to understand before agreeing fully
Question 1: How does the parquet file get to EC2?

The nightly build runs on your Windows laptop. After it writes the parquet file, something needs to push it to EC2. The two natural options are:

The nightly build script itself calls aws s3 cp or scp to push the file after writing it
You commit the parquet to GitHub and EC2 pulls from GitHub (but .gitignore excludes 01_Data/ — you'd need a separate repo or a deliberate exception)
The GitHub route has a problem: parquet files in a public repo expose your data. The direct push to EC2 via scp or AWS CLI is cleaner. Which direction were you thinking?

Question 2: How does the Shiny app pick up the new parquet nightly?

If the app reads the parquet once at startup into summ_data, a new parquet file sitting on disk doesn't help until the process restarts. This is the same data freshness question from before — parquet doesn't solve it, it just moves the file format. The restart mechanism still needs to exist.

Question 3: Which parquet library?

You already use nanoparquet in zz_airports.R. That's a reasonable default. arrow is heavier but adds more capability. For a simple read at startup, nanoparquet is sufficient. Confirming you'd want to stay consistent with what's already in the project.

My honest take
The parquet idea is the right call for MVP. It simplifies the EC2 environment meaningfully. But it doesn't change the performance work we were discussing — bindCache(), the checkpoint lookup, the subtitle dedup. Those are still valid on top of whatever file format you land on.

The sequencing I'd suggest:

Decide parquet approach (file transfer mechanism + restart mechanism)
Make the code changes we already agreed on (subtitle cleanup, checkpoint lookup)
Add bindCache() once the restart strategy is clear
Does that sequencing make sense, and what's your answer on the file transfer question?

we would need to have the build script push the file to AWS s3 bucket after writing it

I think restarting the shiny app overnight when the data gets pushed to an s3 bucket is fine.

nanoparquet should be OK because we are just reading the data from the file and not doing anything else with the data.

Understood. I'll wait for you to upload the updated file before touching anything.

todo_list.txt file uploaded for you to modify

Let me read the uploaded file before touching anything.


Reading updated todo_list.txt
Reading updated todo_list.txt
Good. The file is clear. Here's what I'm doing before writing anything:

The items completed this session that need to be marked done are:

bindCache() with cache_mem() on both renderPlot() calls — done
bucket_label 12-hour format at render time — done
Parquet export in xx_build_summary_db.R with S3 push via paws — done
app_sidebar.R reading parquet via nanoparquet — done
The item still open from App Performance:

Verify %I:%M %p produces "12:00 AM" on Windows — still pending, needs desktop rig test
Everything else stays as-is.


Ran 2 commands, edited a file, read a file
Ran 2 commands, edited a file, read a file
Four items marked done with brief notes on what changed from the original spec. One item left open in App Performance — the Windows locale verification — since that still needs the desktop rig test. Everything else untouched.


Todo list
TXT 







Claude is AI and can make mistakes. Please double-check responses.






