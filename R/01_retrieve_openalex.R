# =============================================================================
# R/01_retrieve_openalex.R
#
# Hace una búsqueda en OpenAlex en los 3 idiomas (EN/ES/PT)
# Remueve los duplicados por el DOI y guarda los datos acá: data/raw/openalex_raw.csv
#
# Paquetes requeridos: openalexR, dplyr, readr, glue, cli, fs
# =============================================================================

library(openalexR)
library(dplyr)
library(readr)
library(glue)
library(cli)
library(fs)

source("R/queries.R") # acá están las búsquedas

# Configuración -----------------------------------------------------------


options(openalexR.mailto = "your@email.com")   # <-- poner email acá como registro

#acá desde el 2021 al 2025
YEAR_FROM <- 2021L 
YEAR_TO   <- 2025L
OUT_RAW   <- "data/raw/openalex_raw.csv"

# las columnas de inforación a extraer
FIELDS <- c(
  "id", "doi", "title", "display_name", "publication_year",
  "publication_date", "type", "language",
  "primary_location", "authorships", "abstract_inverted_index",
  "cited_by_count"
)

# ── Retrieval ─────────────────────────────────────────────────────────────────

cli_h1("OpenAlex análisis")

results_list <- lapply(names(oa_queries), function(lang) {

  cli_h2("Idioma: {lang}")

  tryCatch({
    res <- oa_fetch(
      entity                    = "works",
      title_and_abstract.search = oa_queries[[lang]],
      publication_year          = c(YEAR_FROM, YEAR_TO),
      options                   = list(select = FIELDS),
      verbose                   = TRUE
    )

    if (is.null(res) || nrow(res) == 0) {
      cli_alert_warning("Sin resulados en {lang}.")
      return(NULL)
    }

    cli_alert_success("{nrow(res)} trabajos en {lang}.")
    res$query_language <- lang
    res$source_db      <- "OpenAlex"
    res

  }, error = function(e) {
    cli_alert_danger("Error en {lang}: {e$message}")
    NULL
  })
})

all_raw <- bind_rows(results_list)
cli_alert_info("Número total trabajos: {nrow(all_raw)}")

# Normalizar las DOI ------------------------------------------------------

all_raw <- all_raw |>
  mutate(doi_clean = tolower(trimws(doi)))

# Eliminar duplicados con DOI común ---------------------------------------


has_doi   <- all_raw |> filter(!is.na(doi_clean) & doi_clean != "")
no_doi    <- all_raw |> filter(is.na(doi_clean)  | doi_clean == "")

dedup_doi <- has_doi |>
  arrange(doi_clean) |>
  distinct(doi_clean, .keep_all = TRUE)

# Si algún trabajo no tiene DOI se elimina título repetido
no_doi <- no_doi |>
  mutate(title_norm = tolower(trimws(display_name))) |>
  distinct(title_norm, .keep_all = TRUE) |>
  select(-title_norm)

all_dedup <- bind_rows(dedup_doi, no_doi)

cli_alert_success(
  "Despúes de eliminar duplicados: {nrow(all_dedup)} trabajos ({nrow(all_raw) - nrow(all_dedup)} eliminados)"
)

# Guardar los datos  ------------------------------------------------------

dir_create("data/raw")
write_csv(all_dedup, OUT_RAW)
cli_alert_success("Se guarda en {OUT_RAW}")
