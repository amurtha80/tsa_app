# Organizing custom instructions for coding and styling

### User

How to structure custom instructions?

I have some ideas for coding styles, shiny styles and a few other things. What is the best way to organize those in custom instructions?

---

### Assistant

Great question. For a project like this with multiple layers of preferences, here's how I'd think about organizing custom instructions:

Structure by category, ordered by how often they apply

Since you code in R, SQL, and Python across scraping, database work, and Shiny, something like:

General Coding Style

- Preferences that apply everywhere (e.g., pipe style `|>` vs `%>%`, comment density, naming conventions like `snake_case`)

R-Specific

- Tidyverse preferences, how you handle `suppressWarnings/Messages`, `here::here()` usage, global env patterns, cleanup/`rm()` habits

SQL / DuckDB

- Query formatting style, how you prefer CTEs vs subqueries, indentation

Shiny / shinyMobile

- UI layout patterns, whether you prefer `f7Page` structures, how reactive logic should be organized, naming conventions for inputs/outputs

Data / Scraping Patterns

- How you structure scraping functions (your functions follow a consistent kickoff → scrape → tibble → assign → dbAppend → rm → close pattern, which is worth documenting)

A few practical tips:

Write instructions as rules, not examples — "always use `|>` not `%>%`" rather than showing both. Keep each point to one sentence. Prioritize things you find yourself correcting most often.

You can update preferences via Settings → Profile, and they only apply to new conversations going forward.

Want help drafting the actual text for any of those sections based on the patterns I can see in your scripts?

---

### User

What if I have Claude skills files for some of these? Do I just copy/paste them in?

---

### Assistant

No, don't copy/paste them in — that would bloat your custom instructions and create maintenance headaches when skills get updated.

The better mental model:

Custom instructions and skills serve different purposes:

- Skills = "here's how to execute a specific task" (procedural knowledge Claude looks up when needed)

- Custom instructions = "here's how I work and what I prefer" (persistent context about you)

What to put in custom instructions:

Your personal preferences that aren't in any skill file — things like:

- "Always use `|>` not `%>%`"

- "Follow my scraping function pattern: kickoff print → scrape → tibble → assign → dbAppend → rm → close"

- "shinyMobile is my preferred Shiny framework"

- "I use DuckDB, not SQLite, for new work"

- "Name scraping functions `scrape_tsa_data_{airport_code}`"

What to leave in skills:

The procedural how-to that Claude reads at task time — docx formatting rules, frontend design tokens, etc.

The bridge between them:

In your custom instructions, you can reference a skill pattern without duplicating it — something like "for Shiny apps, follow my shinyMobile patterns visible in project files" and let the project context do the rest.

The test: if a preference would still apply 2 years from now regardless of the task, it belongs in custom instructions. If it's task-specific procedure, it belongs in a skill.

Want me to draft the custom instructions text based on what I can infer from your scripts?

---

### User

Yes please draft here with an artifact, and then I will make the final decisions on what to include/exclude.

One thing I can think of is with shiny I prefer bslib

---

### Assistant

A few things worth flagging:

Everything in the draft was inferred from your actual scripts, so it reflects patterns you're already using — not guesses. The scraping function structure in particular is very consistent across all your airport files, so that section should be fairly accurate.

The "Things to Decide" section at the bottom is the most important part — those are genuine ambiguities I spotted that would affect how I generate code for you. The shinyMobile vs bslib question especially, since your current app files use shinyMobile but you mentioned preferring bslib going forward.

Once you mark up what to keep/cut/change, I can produce a final version formatted for pasting directly into Settings → Profile.

---

### User

Please remove the duckdb dbConnect() item for write connections, this is not the syntax I am using currently, I am only connecting to permanent databases

If it makes sense to include the new quack feature for duckdb here (concurrent writes/reads) then please include it here.

for existing pipes, I am ok with the magrittr pipe. For any new pipes I would like ot use the |> pipe universally, as along as new pipe considerations are taking place for passing data along through pipes (etc.) Here is a link that talks through this transition to new internal (non magrittr) pipes.

https://ivelasq.rbind.io/blog/understanding-the-r-pipe/

For now I would like the preferred theme to be theme_minimal() Note this can be changed at a later date.

for NA values in scraped data, I am OK for the data being in there, as the statistical functions I pass are  excluding NA values.

for Shiny, as long as Shiny can adapt to mobile layout, I am OK with bslib that uses bootstrap 5. However, if this is not flexible for mobile/tablet layouts then I am ok to keep shinyMobile

I cannot think of any IDE specific conventions, but if my code calls any out, please include them.

Does this help you revise and complete the custom draft instructions?

---

### Assistant

Yes, that's very clear. Let me look up the DuckDB quack feature and the pipe article before revising.

---

### Assistant

TSA Wait Time Shiny App

---

