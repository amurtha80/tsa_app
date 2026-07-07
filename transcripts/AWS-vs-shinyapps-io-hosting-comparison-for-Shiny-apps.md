AWS research for hosting shiny apps . How to host and potential costs when compared to Posit Cloud Connect $19/month plan


Searched the web
Searched the web
Good, I have enough data. Let me put together the comparison.

Here's a thorough breakdown of your options.

shinyapps.io Pricing (Current)
The current shinyapps.io tiers are:

Plan	$/month	Active Hours	Apps
Free	$0	25	5
Starter	$13	100	25
Basic	$49	500	Unlimited
Standard	$119	2,000	Unlimited
Professional	$349	10,000	Unlimited
A few things worth knowing for ASAP specifically:

Custom domains require the Professional tier ($349/mo) — relevant when you want asap.app instead of youraccount.shinyapps.io
Active hours = time the app is actually serving a user session; a low-traffic app burns very little
The Basic plan at $49/mo is probably your eventual ceiling before AWS makes sense — it gives you unlimited apps and 500 active hours
AWS Options
There are three realistic AWS paths, in order of complexity:

1. EC2 + Shiny Server Open Source (Most Common DIY Route)
You spin up a Linux EC2 instance, install R, install Shiny Server (free, open source), and run your app there. You own the server.

Instance sizing for a small app:

Instance	vCPUs	RAM	$/month (on-demand, us-east-1)
t3.micro	2	1 GB	~$7.59
t3.small	2	2 GB	~$15.18
The t3.micro is priced at $0.0104/hr or about $7.59/month. The t3.small runs $0.0208/hr or about $15.18/month. 
Economize
Economize

Total realistic monthly cost (t3.small build):

Component	Estimated Cost
EC2 t3.small instance	~$15
EBS storage (20 GB gp3)	~$1.60
Elastic IP (static public IP)	~$3.60 if unattached; $0 if in use
Data transfer out (light traffic)	<$1
Total	~$18–22/month
Compared to shinyapps.io Basic at $49/mo — this is cheaper. But the cost of your time is real: you're doing OS updates, SSL cert renewals (via Let's Encrypt), Shiny Server config, and troubleshooting when it breaks.

AWS Free Tier note: New AWS accounts get free access to some services for a full year, so you could run a t3.micro free for 12 months to test the setup. 
Charles Bordet

2. EC2 + Docker + ShinyProxy
A more scalable setup that containerizes your app and handles concurrent sessions cleanly. ShinyProxy is an open-source, enterprise-grade solution that uses Docker and JVM technology for secure and scalable deployment — ideal for those who prefer open-source tools and the flexibility of container-based technology. 
Kenwuyang

This adds complexity but is a solid path if you eventually want to host multiple apps with user-level isolation. Probably overkill for ASAP at MVP stage.

3. ECS Fargate (Fully Managed Containers)
AWS manages the infrastructure; you just deploy a Docker container with your app. No EC2 to babysit. AWS ECS with Fargate is a managed platform to host containers with minimal overhead. 
Appsilon

Fargate pricing is more complex (per vCPU-hour + per GB-hour), and for a single small app running continuously it typically lands higher than EC2, closer to $25–40/month depending on the task size. The tradeoff is zero server management.

The Real Comparison for ASAP
Option	$/month	Custom Domain	Complexity	Scales?
shinyapps.io Free	$0	No	None	No
shinyapps.io Basic	$49	No	None	Limited
shinyapps.io Professional	$349	Yes	None	Yes
AWS EC2 t3.small + Shiny Server	~$18–22	Yes (via Route 53)	Medium-High	Manual
AWS Fargate	~$25–40	Yes	Medium	Auto
My Recommendation for Where You Are Now
Stay on shinyapps.io for MVP. It unblocks deployment this week, and the Free or Starter tier is perfectly adequate for light traffic. The active hour concern for ASAP is low — users hit the app, make selections, see a chart, and leave. Sessions are short.

Plan the AWS migration for post-MVP, once you have real traffic data. The EC2 + Shiny Server path is the right long-term move for cost and flexibility. The setup is genuinely a 2–4 hour project if you've touched Linux before — there's good documentation for the R + Shiny Server + nginx + Let's Encrypt stack, and Business Science has a whole book on it.

The $19/month figure you mentioned doesn't match current shinyapps.io pricing (the Starter plan is now $13, Basic is $49) — worth double-checking what plan you were looking at, since it sounds like it may have been the old Starter rate before a price adjustment.

Please update this to posit cloud connect basic pricing of $19/month


Searched the web
Searched the web
Good — I have confirmed the Connect Cloud plan structure (Free, Basic, Enhanced, Enterprise) but the pricing page requires JavaScript to render the actual dollar amounts. I couldn't confirm $19 from a source, but the docs confirm Basic is the tier above Free for individuals. I'll update the comparison to reflect Connect Cloud Basic at $19/month as you specified, note the distinction between Connect Cloud and shinyapps.io, and flag that I couldn't independently verify the exact dollar figure from a rendered pricing page.

Here's the corrected comparison. One important clarification first: Posit Connect Cloud and shinyapps.io are two separate products. Connect Cloud is Posit's next-generation online publishing platform that deploys from GitHub, while shinyapps.io is the older hosted platform. Connect Cloud has Free, Basic, and Enhanced individual plans, with Basic allowing 25 applications and the ability to deploy from private GitHub repositories, and Enhanced offering unlimited applications and private sharing. 
Posit
Posit

I couldn't confirm the exact $19 price from the Connect Cloud pricing page (it requires JavaScript to render), so I've taken your number at face value. Verify it at connect.posit.cloud/plans before making a decision.

Updated Comparison
Option	$/month	Apps	Custom Domain	Complexity
shinyapps.io Free	$0	5	No	None
shinyapps.io Starter	$13	25	No	None
Posit Connect Cloud Basic	$19	25	No	None
shinyapps.io Basic	$49	Unlimited	No	None
Connect Cloud Enhanced	unknown	Unlimited	Yes	None
AWS EC2 t3.small + Shiny Server	~$18–22	Unlimited	Yes	Medium-High
shinyapps.io Professional	$349	Unlimited	Yes	None
Connect Cloud Basic vs. AWS — What Actually Changes
At $19/month vs. ~$18–22/month for EC2, the cost is essentially a wash. The real difference is:

Connect Cloud Basic advantages:

Zero server management — no OS patches, no SSL cert renewals, no Shiny Server config
Deploy from GitHub via push-to-publish — fits your existing repo at amurtha80/tsa_app
Basic and Enhanced plans can deploy content from private GitHub repositories 
Posit
AWS EC2 advantages:

No application count ceiling — relevant if ASAP grows to multiple airports/views as separate apps
Custom domain without jumping to a $349+/month tier
Full control over compute: you pick the RAM, can schedule cron jobs natively, co-locate your scraping pipeline on the same machine if you ever move off Windows Task Scheduler
The DuckDB file lives on the same server as the app — no path/deployment complexity
One Connect Cloud wrinkle for ASAP specifically: your app reads from tsa_app_summ.duckdb, a local file built nightly. Connect Cloud deploys from GitHub, and your .gitignore correctly excludes 01_Data/. That means you'd need a separate strategy to get the summary DB into the deployed environment — likely S3 or similar — which adds complexity that doesn't exist with the shinyapps.io or EC2 paths.

Revised Recommendation
For MVP deployment now: shinyapps.io Free or Starter ($0–$13). Lowest friction, and the DB path problem is the same to solve regardless of which Posit-hosted platform you use.

For post-MVP paid hosting: the Connect Cloud Basic at $19 is competitive with AWS on price and substantially lower on operational burden. AWS becomes the better call once you want a custom domain without paying $349/month, or if you want to consolidate your scraping pipeline and app on one server.

I am telling you I looked at the page myself the tier above free is $19/month

Noted — updated. The comparison table and recommendation now use Posit Connect Cloud Basic at $19/month. No other changes.

Updated Comparison
Option	$/month	Apps	Custom Domain	Complexity
shinyapps.io Free	$0	5	No	None
shinyapps.io Starter	$13	25	No	None
Posit Connect Cloud Basic	$19	25	No	None
shinyapps.io Basic	$49	Unlimited	No	None
Connect Cloud Enhanced	TBD	Unlimited	Yes	None
AWS EC2 t3.small + Shiny Server	~$18–22	Unlimited	Yes	Medium-High
shinyapps.io Professional	$349	Unlimited	Yes	None
Connect Cloud Basic ($19) vs. AWS (~$18–22) — The Real Tradeoff
At near-identical monthly cost, the decision comes down to what you value:

Connect Cloud Basic wins on: zero server management, push-to-deploy from your existing GitHub repo, no infrastructure headaches.

AWS wins on: custom domain without a massive price jump, unlimited apps, full compute control, and the ability to eventually co-locate your scraping pipeline on the same server.

The one ASAP-specific friction point with Connect Cloud: your app reads from tsa_app_summ.duckdb, which is gitignored. Connect Cloud deploys from GitHub, so you'd need a separate mechanism (S3, etc.) to get the summary DB into the deployed environment. That same problem exists on shinyapps.io too — it's not unique to Connect Cloud — but it's worth solving before committing to either platform.

Bottom line: Connect Cloud Basic at $19 is a solid MVP choice if you want managed hosting at the lowest paid price point. AWS becomes worth the added complexity once you want a custom domain or plan to consolidate your pipeline.

1782003117696_image.png
Ok let's roll this analysis again and have you rerun it. I now see that the enhanced package is $59/month, and that is the first level that allows a custom URL. That is not acceptable. I need to flip to either AWS entirely, or figure out how to potentially use Netlify for short term to AWS or Netlify permanently... here is a screenshot I took of their calculator if that will help in this analysis

Good — the screenshot helps, but I want to make sure I'm looking at the right thing before rerunning the analysis.

A few things I want to confirm before I proceed:

1. What platform is this screenshot from?

This looks like it could be Netlify, Render, Railway, or Fly.io — the credit-based pricing model (production deploys, bandwidth GB, compute GB-hours, web requests) doesn't match Posit Connect Cloud's pricing structure at all. Can you confirm what site this is from? The analysis will be very different depending on the answer.

2. What is the $19/month product you saw?

Based on what you described earlier and what I can confirm from Posit's docs, the Connect Cloud tiers are Free → Basic → Enhanced → Enterprise. If you saw $19 on a page, it may have been a different product (shinyapps.io has a $13 Starter), or Connect Cloud Basic before the Enhanced tier unlocks custom domains at $59. I want to make sure I'm comparing the right things.

3. What does "custom URL" mean for ASAP specifically?

Are you looking for flyasap.us to resolve directly to the app, or would a subdomain like app.flyasap.us work? Some platforms support custom subdomains at lower tiers than full apex domain routing — worth knowing before ruling options out.

4. Netlify — are you thinking of it as a static host, or have you already looked into whether it can run a Shiny app?

Netlify is a static/serverless host — it can't run a persistent R process natively. Shiny on Netlify requires a workaround (usually a separate R backend on something like EC2, with Netlify just fronting it). If that's already on your radar, great. If not, it changes the calculus.

Once you confirm the screenshot source and the custom domain requirement, I can rerun the full comparison cleanly.

1) that image is from netlify

2) forget posit connect and shinyapps.io and all related pricing

3) custom URL means you can bring your own URL to posit cloud connect and not use their URL structure. so it would be like positconnect.flyasapapp.com

4) was not aware you couldn't natively host a shiny app on netlify

https://flyasap.app is live and secure. That's a huge milestone.

✅ Ubuntu updated
✅ R 4.3.3 installed
✅ Shiny Server running
✅ AWS CLI 2.35.11 installed
✅ IAM role confirmed working
✅ All R packages installed
✅ nginx configured
✅ Let's Encrypt SSL issued
✅ Route 53 / Cloudflare DNS configured
✅ https://flyasap.app live and serving over HTTPS

Three remaining items on the checklist:

EC2 cron job — pull parquet from S3 nightly, restart Shiny
IAM permissions scoping — lock down flyasap-windows to flyasap-app-data bucket only
AWS Budget — monthly spend alert
Plus the actual app deployment — getting app_sidebar.R onto the server.

How much time do you have? I want to prioritize the right next step based on what you can finish tonight.

Add an AWS billing alert for a #12. 

I want to hang it up for the evening. Would it make sense to shut down the instance tonight to prevent usage? 

If so do I have to go through all this work again when I restart it tomorrow?

Good call adding the billing alert as #12. Updated checklist:

✅ IAM user setup
✅ S3 bucket creation
✅ EC2 provisioning
✅ Server setup — R, Shiny Server, nginx, AWS CLI
✅ R package installation
✅ nginx config
✅ Let's Encrypt SSL
✅ Route 53 + Cloudflare DNS
EC2 cron job — pull parquet from S3 nightly, restart Shiny
IAM permissions scoping
AWS Budget
AWS Billing Alert
On shutting down the instance tonight:

Yes, stop it to save compute costs. And no — you won't lose any of your work. Everything installed on the server (R, Shiny Server, nginx, SSL certificates, packages) is saved on the EBS volume and persists across stops and starts.

The only thing that matters when you restart: your Elastic IP stays associated, so flyasap.app will still point to the right place automatically.

To stop tonight:

EC2 dashboard → select flyasap-app → Instance state → Stop instance
To resume tomorrow:

EC2 dashboard → select flyasap-app → Instance state → Start instance
Wait for Running status
SSH back in and pick up where we left off
Good work tonight — https://flyasap.app being live is a major step. See you tomorrow.








Claude is AI and can make mistakes. Please double-check responses.






