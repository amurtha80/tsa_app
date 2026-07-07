# FlyASAP (Flyasap.app) — Core Context & Rules

## Project Summary
A mobile-first, web-second R Shiny app displaying historical TSA checkpoint wait times across 13 US airports. 
- **GitHub:** amurtha80/tsa_app
- **Database:** DuckDB (`01_Data/tsa_app.duckdb`) - *Excluded via .gitignore*

## Core Operating Principles
- **Think Before Coding:** State assumptions out loud. If ambiguous, ask. If a simpler approach exists, push back. Stop when confused.
- **Simplicity First:** Write the minimum code required. No speculative abstractions. 
- **Surgical Changes:** Touch only what the task requires. Do not refactor neighboring code. Every changed line must trace back to the request.
- **Data-First Diagnosis:** Run diagnostic SQL queries and confirm facts before writing any fixes.
- **Changelog & TODO Hygiene:** `TODO.md` (managed via `todo_list.txt` workflow) requires a full file copy for updates. `CHANGELOG.md` is append-only; provide dated snippets. Check both upon task completion.

## Deep Reference Documentation
For deep context on development architectures or specific code styles, refer to these local files:
- Technical Architecture & Infrastructure: See `@DEVELOPMENT.md`
- R, Shiny, and Scraping Code Standards: See `@STYLEGUIDE.md`
*If project decisions or actions result in a need for these local files need to be updated during the project life-cycle, please prompt and ask for me to review potential updates to these files so we can make a decision on whether to update the files or not.*

## Common Environment Commands
- **Run Shiny App:** `Rscript -e "shiny::runApp('03_App')"`
- **Run Scraping Orchestrator:** `Rscript 02_Scripts/xx_test_orchestrator_quack.R`
- **Execute Validation Script:** `Rscript 02_Scripts/xx_validate_scrape.R`
- **DuckDB CLI Access:** `duckdb 01_Data/tsa_app.duckdb`

## Context Reference
- Past web chat histories are saved in the `transcripts/` directory.
- Refer to `@transcripts/<filename>.md` for historical decisions.

***
*Self-Critique Guard: Prior to giving any answer, critique it internally. Only provide a "Callouts" footer if there are critical warnings or edge cases the user must be explicitly aware of.*