# =============================================================================
# run_pipeline.R
#
# Master script — runs the full search workflow in order.
#
# BEFORE RUNNING
# ──────────────
# 1. Add API keys to ~/.Renviron (usethis::edit_r_environ()):
#      WOS_STARTER_KEY="your_wos_key"      # developer.clarivate.com
#      Elsevier_API="your_scopus_key"      # dev.elsevier.com (institution IP/VPN)
#
# 2. Choose ONE script per database — API retrieval OR manual import:
#
#      WoS:    02_retrieve_wos.R   (API)   OR  02b_import_wos.R   (manual .txt)
#      Scopus: 03_retrieve_scopus.R (API)  OR  03b_import_scopus.R (manual .csv)
#
#    Comment out the one you are NOT using below.
#    Both write to the same output file so steps 04–07 are unaffected.
#
# WORKFLOW
# ─────────────────────────────────────────────────────────────────────────────
# Step 01 │ OpenAlex  — API (openalexR, free, set email in script)
# Step 02 │ WoS       — API (rwosstarter) OR manual ISI .txt import
# Step 03 │ Scopus    — API (rscopus, institution IP) OR manual CSV import
# Step 04 │ Merge & deduplicate — DOI exact match only
# Step 05 │ Tag document types  — review / research_paper / other
# Step 06 │ Screen              — country + concept keyword filter
# Step 07 │ Report              — PRISMA counts, distributions
# =============================================================================

library(cli)

cli_h1("Climate Search Pipeline")
cli_alert_info("Start time: {Sys.time()}")

steps <- list(
  list(script = "R/01_retrieve_openalex.R",  label = "01 OpenAlex retrieval"),

  # ── WoS: choose API or import (comment out the other) ──────────────────────
  # list(script = "R/02_retrieve_wos.R",       label = "02 WoS — API"),
   list(script = "R/02b_import_wos.R",      label = "02 WoS — manual import"),

  # ── Scopus: choose API or import (comment out the other) ───────────────────
  # list(script = "R/03_retrieve_scopus.R",    label = "03 Scopus — API"),
   list(script = "R/03b_import_scopus.R",   label = "03 Scopus — manual import"),

  list(script = "R/04_merge_and_dedup.R",    label = "04 Merge & deduplication"),
  list(script = "R/05_tag_doctype.R",        label = "05 Document type tagging"),
  list(script = "R/06_screen.R",             label = "06 Screening"),
  list(script = "R/07_report.R",             label = "07 Report")
)

for (step in steps) {
  cli_h2(step$label)
  tryCatch(
    source(step$script, local = FALSE),
    error = function(e) {
      cli_alert_danger("FAILED: {step$label} — {e$message}")
      stop(e)
    }
  )
  cli_alert_success("{step$label} — done")
}

cli_h1("Pipeline complete")
cli_alert_info("End time: {Sys.time()}")
cli_alert_success("Screened set:  output/screened/screened_pass_strict.csv")
cli_alert_success("PRISMA counts: output/prisma_flow.csv")
