# Quick mobile app demo deployment

### User

Can you give me an action plan for option 1? The laptop is windows 11 pro. What actions do I need to take on the laptop?

---

### Assistant

Here's the full action plan:

Step 1 — Find your laptop's local IP

Open Command Prompt and run:

```
ipconfig
```

Look for "Wireless LAN adapter Wi-Fi" → "IPv4 Address". It'll look like `192.168.1.x`. Write it down.

Step 2 — Allow port 3838 through Windows Firewall

Open Windows Defender Firewall with Advanced Security (search it in Start). Create an inbound rule:

- Rule Type: Port

- Protocol: TCP, Specific port: `3838`

- Action: Allow the connection

- Profile: check Private (and Domain if you want, skip Public)

- Name it something like "Shiny Local Demo"

Step 3 — Make sure laptop and phone are on the same WiFi

Both devices need to be on the same network. If your laptop is on a corporate/work network with client isolation enabled, this won't work — use your phone's hotspot instead and connect the laptop to it.

Step 4 — Run the app with the right host binding

In RStudio or Positron, run:

r
```r
shiny::runApp(
  "03_App/tsa_wait_time_app/app3shinyassistant.R",
  host = "0.0.0.0",
  port = 3838
)
```

Step 5 — Open on your phone

In your phone's browser, navigate to:

```
http://192.168.1.x:3838
```

(swap in your actual IP from Step 1)

Two things to watch out for:

- If the app reads from `tsa_app.duckdb`, the path needs to resolve correctly when the app runs — since you're running locally this should be fine as long as `here::here()` is set correctly

- Your IP can change if you reconnect to WiFi — if it stops working, re-run `ipconfig` to check

---

### User

This is the code I ran:

# shinyApp(ui = ui, server = server)
# Connect to local shiny app app_sidebar.R with host
shiny::runApp("~/R/tsa_app/03_App/tsa_wait_time_app/app_sidebar.R",
              host = "0.0.0.0",
              port = 3838
              )

This is the error I got:

Error in normalizePath(path.expand(path), winslash, mustWork) :    path[1]="03_App/tsa_wait_time_app/app_sidebar.R": The system cannot find the path specified

---

### Assistant

The path isn't resolving correctly. A couple of quick fixes to try:

Option A — Use the full absolute path

r
```r
shiny::runApp(
  "C:/Users/james/Documents/R/tsa_app/03_App/tsa_wait_time_app/app_sidebar.R",
  host = "0.0.0.0",
  port = 3838
)
```

Option B — Use here::here()

r
```r
shiny::runApp(
  here::here("03_App/tsa_wait_time_app/app_sidebar.R"),
  host = "0.0.0.0",
  port = 3838
)
```

Option C — Set working directory first, then run

r
```r
setwd("C:/Users/james/Documents/R/tsa_app")
shiny::runApp(
  "03_App/tsa_wait_time_app/app_sidebar.R",
  host = "0.0.0.0",
  port = 3838
)
```

Also worth noting — `runApp()` can take a directory path instead of a file path if your app file is named `app.R`. If `app_sidebar.R` is the only file in that folder you may need to pass the folder path and rename the file to `app.R`, or just pass the full file path as shown above.

Which IDE are you running this from — RStudio or Positron? That affects what `~` resolves to, which may be part of the issue.

---

### User

all three options throw the same error. I have multiple apps in that folder, and the app I am using is app_sidebar.R

---

### Assistant

The issue is likely that `runApp()` expects a directory (not a file) when there are multiple files in the folder. Since you have multiple apps in one folder, it gets confused.

Easiest fix — just source the file directly instead:

r
```r
source("C:/Users/james/Documents/R/tsa_app/03_App/tsa_wait_time_app/app_sidebar.R")
```

But that won't let you pass `host` and `port`. So the cleanest approach is to modify the last line of `app_sidebar.R` itself. Find the `shinyApp()` call at the bottom and replace it with:

r
```r
shiny::runApp(
  shinyApp(ui = ui, server = server),
  host = "0.0.0.0",
  port = 3838
)
```

Then just run the whole file normally (Ctrl+Shift+Enter or Source button). The host and port get passed directly to the app object, bypassing the path problem entirely.

Once you're done demoing, swap it back to `shinyApp(ui = ui, server = server)` so it runs normally again.

---

### User

What if I have tailscale

---

### Assistant

Even easier. Tailscale is perfect for this.

What Tailscale gives you: Every device on your Tailscale network gets a stable private IP (like `100.x.x.x`) that never changes, works across any network, and doesn't require firewall rules or same-WiFi constraints.

Action plan:

Step 1 — Install Tailscale on your phone if it isn't already, and make sure both laptop and phone are logged into the same Tailscale account and show as connected.

Step 2 — Find your laptop's Tailscale IP by clicking the Tailscale icon in the system tray. It'll show something like `100.x.x.x`.

Step 3 — Run the app using the same approach from before (modify the bottom of `app_sidebar.R`):

r
```r
shiny::runApp(
  shinyApp(ui = ui, server = server),
  host = "0.0.0.0",
  port = 3838
)
```

Step 4 — Open on your phone:

```
http://100.x.x.x:3838
```

No firewall rules needed, no same-WiFi requirement, works from anywhere. If you're demoing to someone else and they have Tailscale too, you can add them to your tailnet temporarily and they can hit it as well.

---

### User

it worked with tailscale easily was able to play with app, will start a new chat this weekend with some ideas on improving the UI/UX of the app. I also have a few text items I want to have plugged into the app before shipping the MVP.

---

### Assistant

Great, glad Tailscale worked cleanly. A few things to have ready for this weekend's chat:

- Screenshot or screen recording of the current app so we have a shared baseline for UI/UX discussion

- The text copy you want plugged in — just have it written out or in a doc so we can drop it in directly

- Any specific UI/UX pain points or inspirations you noticed while playing with it on mobile

When you start the chat, upload `app_sidebar.R` to the project so I have the current version to work from — the one in the project files now is `app3shinyassistant.R` which sounds like it may be an older iteration.

---

### Assistant

TSA Wait Time Shiny App

---

