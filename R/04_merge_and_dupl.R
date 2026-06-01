# =============================================================================
# R/04_merge_and_dedup.R
#
# Combina OpenAlex, Web of Science (WoS) y Scopus,
# y elimina duplicados utilizando coincidencias exactas de DOI normalizados
#
# Sin DOI se conservan sin modificaciones; no se aplica comparación
#
# La columna `found_in_dbs` indica qué bases de datos aportaron cada DOI.
#
# Salidas:
#   data/processed/merged_all.csv      — todos los registros con información
#                                        de la base de datos de origen
#   data/processed/unique_records.csv  — conjunto sin duplicados listo para
#                                        clasificación y etiquetado
#
# Requiere: dplyr, readr, tidyr, cli, fs
# =============================================================================

library(dplyr)
library(readr)
library(tidyr)
library(cli)
library(fs)

# ── Load ──────────────────────────────────────────────────────────────────────

cli_h1("Combinación y eliminación duplicados")

read_safe <- function(path) {
  if (!file_exists(path)) {
    cli_alert_warning("Missing: {path} — skipping.")
    return(tibble())
  }
  read_csv(path, show_col_types = FALSE)
}

openalex <- read_safe("data/raw/openalex_raw.csv")
wos      <- read_safe("data/raw/wos_raw.csv")
scopus   <- read_safe("data/raw/scopus_raw.csv")

# ── Harmonise column names ────────────────────────────────────────────────────
# Target schema: source_db, query_language, title, abstract, doi_clean,
#                year, authors, journal, doc_type, language, uid

harmonise <- function(df, db_name) {
  if (nrow(df) == 0) return(df)

  if (db_name == "OpenAlex") {
    # título: openalexR lo entrega en 'display_name' (o 'title')
    df$title <- dplyr::coalesce(col_or_na(df, "display_name"), col_or_na(df, "title"))
    
    # abstract: openalexR YA lo reconstruye en la columna 'ab'
    df$abstract <- col_or_na(df, "ab")
    
    # revista: el nombre de la fuente viene en 'so'
    df$journal <- col_or_na(df, "so")
    
    # tipo de documento
    df$doc_type <- col_or_na(df, "type")
    
    # autores: 'author' es una columna-lista; unir los nombres con "; "
    df$authors <- if ("author" %in% names(df)) {
      vapply(df$author, function(a) {
        if (is.null(a) || !"au_display_name" %in% names(a)) return(NA_character_)
        paste(a$au_display_name, collapse = "; ")
      }, character(1))
    } else NA_character_
    
    df <- df |>
      rename(
        year = any_of("publication_year"),
        uid  = any_of("id")
      )
  }

  schema_cols <- c("source_db", "query_language", "title", "abstract",
                   "doi_clean", "year", "authors", "journal",
                   "doc_type", "language", "uid")

  for (col in schema_cols) {
    if (!col %in% names(df)) df[[col]] <- NA_character_
  }

  df |>
    select(all_of(schema_cols)) |>
    mutate(
      across(everything(), as.character),
      doi_clean = tolower(trimws(doi_clean)),
      year      = suppressWarnings(as.integer(year))
    )
}

openalex <- harmonise(openalex, "OpenAlex")
wos      <- harmonise(wos,      "WoS")
scopus   <- harmonise(scopus,   "Scopus")

# Combinar ----------------------------------------------------------------

cli_h2("Conteo")
cli_alert_info("OpenAlex: {nrow(openalex)}")
cli_alert_info("WoS:      {nrow(wos)}")
cli_alert_info("Scopus:   {nrow(scopus)}")

all_records <- bind_rows(openalex, wos, scopus) |>
  mutate(record_id = row_number())

cli_alert_info("Total combinados: {nrow(all_records)}")


# DOI eliminación duplicados ----------------------------------------------

cli_h2("DOI eliminación duplicados")

MISSING_DOI <- c(NA_character_, "", "na")

has_doi <- all_records |> filter(!doi_clean %in% MISSING_DOI)
no_doi  <- all_records |>
  filter(doi_clean %in% MISSING_DOI) |>
  mutate(found_in_dbs = source_db, n_dbs = 1L)

cli_alert_info("Con DOI:    {nrow(has_doi)}")
cli_alert_info("Sin DOI: {nrow(no_doi)} (kept as-is)")

# mantener el abstract mas largo
doi_dedup <- has_doi |>
  group_by(doi_clean) |>
  mutate(
    found_in_dbs  = paste(sort(unique(source_db)), collapse = "; "),
    n_dbs         = n_distinct(source_db),
    .abstract_len = nchar(coalesce(abstract, ""))
  ) |>
  arrange(desc(.abstract_len)) |>
  slice(1) |>
  ungroup() |>
  select(-.abstract_len)

cli_alert_success(
  "DOI duplicados eliminados: {nrow(has_doi) - nrow(doi_dedup)}"
)
cli_alert_success(
  "Unique DOI records:     {nrow(doi_dedup)}"
)
cli_alert_info(
  "DOIs found in 2+ databases: {sum(doi_dedup$n_dbs > 1, na.rm = TRUE)}"
)

# ── Final set ─────────────────────────────────────────────────────────────────

unique_records <- bind_rows(doi_dedup, no_doi) |>
  select(-record_id) |>
  arrange(year, title)

cli_h2("Final counts")
cli_alert_success("Total unique records: {nrow(unique_records)}")
cli_alert_info("  With DOI:    {nrow(doi_dedup)}")
cli_alert_info("  Without DOI: {nrow(no_doi)} (no fuzzy matching applied)")

# Database coverage
coverage <- unique_records |>
  separate_rows(found_in_dbs, sep = "; ") |>
  count(found_in_dbs, name = "n_contributed") |>
  arrange(desc(n_contributed))

cli_h2("Unique records contributed per database (post dedup)")
print(coverage)

# ── Save ──────────────────────────────────────────────────────────────────────

dir_create("data/processed")
write_csv(all_records |> select(-record_id), "data/processed/merged_all.csv")
write_csv(unique_records,                     "data/processed/unique_records.csv")

cli_alert_success("Saved data/processed/merged_all.csv     ({nrow(all_records)} rows)")
cli_alert_success("Saved data/processed/unique_records.csv ({nrow(unique_records)} rows)")
