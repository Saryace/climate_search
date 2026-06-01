# =============================================================================
# R/02_retrieve_wos.R
#
# Recupera registros de Web of Science mediante la API WoS Starter
# Requiere rwosstarter (GitHub) y una clave API de Clarivate
#
# Configuración
# 1. Obtener una clave gratuita en https://developer.clarivate.com
#    → solicitar acceso a "Web of Science Starter API"
# 2. Agregar la clave al archivo ~/.Renviron
#    (ejecutar usethis::edit_r_environ()):
#      WOS_STARTER_KEY="tu_clave_aquí"
#    Reiniciar R después de guardar
# 3. Instalar el paquete:
#      remotes::install_github("frbcesab/rwosstarter")
#
# OTROS
# - La clave se lee automáticamente desde la variable de entorno
#   WOS_STARTER_KEY.
# - wos_search(query)      → devuelve un número entero con el TOTAL
#                            de registros coincidentes
# - wos_get_records(query) → devuelve los registros como tibble
# - LÍMITE: 1 solicitud/segundo, máximo 1000 registros por consulta.
#   Si una consulta supera 1000 resultados, el script advierte y sugiere
#   dividir la búsqueda por año.
#
# Salida: data/raw/wos_raw.csv

# =============================================================================

library(rwosstarter)
library(dplyr)
library(readr)
library(purrr)
library(cli)
library(fs)
library(glue)

source("R/queries.R")

# Configuración años  -----------------------------------------------------

YEAR_FROM <- 2021L
YEAR_TO   <- 2025L
OUT_FILE  <- "data/raw/wos_raw.csv"
MAX_LIMIT <- 1000L

# API de WOS --------------------------------------------------------------

cli_h1("WOS API")

WOS_API_KEY <- Sys.getenv("WOS_STARTER_KEY")
if (nchar(WOS_API_KEY) == 0) {
  stop(
    "WOS_STARTER_KEY no está en ~/.Renviron.\n"
  )
}


# Llamada WOS -------------------------------------------------------------

fetch_wos <- function(query, lang_label) {
  cli_h2("Idioma {lang_label}")
  cli_alert_info("Query (truncated): {substr(query, 1, 120)}...")
  
  tryCatch({
    total <- wos_search(query)
    cli_alert_info("Total: {total}")
    
    if (is.na(total) || total == 0) {
      cli_alert_warning("Sin resultados")
      return(tibble())
    }
    
    if (total > MAX_LIMIT) {
      cli_alert_warning(
        "{total} Llegando al máximo {MAX_LIMIT}"
      )
    }
    
    records <- wos_get_records(query, limit = min(total, MAX_LIMIT))
    cli_alert_success("{nrow(records)} trabajos encontrados.")
    
    records |>
      transmute(
        source_db      = "WoS",
        query_language = lang_label,
        title     = col_or_na(records, "title"),
        abstract  = NA_character_,                            # not returned by Starter API
        doi_clean = tolower(trimws(col_or_na(records, "doi"))),
        year      = suppressWarnings(as.integer(col_or_na(records, "published_year"))),
        authors   = col_or_na(records, "authors"),
        journal   = col_or_na(records, "source"),
        doc_type  = col_or_na(records, "doc_type"),           # NA if absent on this tier
        language  = NA_character_,                            # not returned by Starter API
        uid       = col_or_na(records, "ut")
      )
    
  }, error = function(e) {
    cli_alert_danger("Error: {e$message}")
    tibble()
  })
}

results_list <- imap(wos_queries, fetch_wos)
all_raw      <- bind_rows(results_list)

cli_alert_info("Total trabajos: {nrow(all_raw)}")

# Eliminación duplicados --------------------------------------------------


has_doi <- all_raw |> filter(!is.na(doi_clean) & doi_clean != "" & doi_clean != "na")
no_doi  <- all_raw |> filter(is.na(doi_clean)  | doi_clean == "" | doi_clean == "na")

wos_dedup <- bind_rows(
  has_doi |> arrange(doi_clean) |> distinct(doi_clean, .keep_all = TRUE),
  no_doi  |> distinct(uid, .keep_all = TRUE)
)

cli_alert_success(
  "Despúes de eliminar duplicados: {nrow(wos_dedup)} ({nrow(all_raw) - nrow(wos_dedup)} eliminados)"
)

dir_create("data/raw")
write_csv(wos_dedup, OUT_FILE)
cli_alert_success("Se guarda en {OUT_FILE}")
