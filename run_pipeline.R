# =============================================================================
# run_pipeline.R
#
# Script maestro que ejecuta todas las búsquedas
# Descarga desde las 3 bases por API y eliminina duplicados por DOI
#
# ANTES DE EJECUTAR
#
# 1. Instala los paquetes:
#      source("PACKAGES.R")
#
# 2. Agrega las claves API a ~/.Renviron (usethis::edit_r_environ()):
#      WOS_STARTER_KEY="tu_clave_wos"      # developer.clarivate.com
#      Elsevier_API="tu_clave_scopus"      # dev.elsevier.com (IP/VPN institucional)
#    Reiniciar R después de guardar.
#
# 3. Configura el correo de OpenAlex en R/01_retrieve_openalex.R:
#      options(openalexR.mailto = "tu@correo.com")
#
# PASOS
# Paso 01 │ OpenAlex (openalexR, gratis, requiere email)
# Paso 02 │ WoS API (rwosstarter, requiere WOS_STARTER_KEY)
# Paso 03 │ Scopus API (rscopus, requiere Elsevier_API + IP institucional)
# Paso 04 │ Unir y deduplicar — coincidencia exacta por DOI
# =============================================================================

library(cli)

cli_h1("Pipeline de búsqueda — Climate Search")
cli_alert_info("Inicio: {Sys.time()}")

pasos <- list(
  list(script = "R/01_retrieve_openalex.R", etiqueta = "01 OpenAlex descarga"),
  list(script = "R/02_retrieve_wos.R",      etiqueta = "02 WoS descarga (API)"),
  list(script = "R/03_retrieve_scopus.R",   etiqueta = "03 Scopus descarga (API)"),
  list(script = "R/04_merge_and_dupl.R",   etiqueta = "04 Unión y deduplicación")
)

for (paso in pasos) {
  cli_h2(paso$etiqueta)
  tryCatch(
    source(paso$script, local = FALSE),
    error = function(e) {
      cli_alert_danger("FALLÓ: {paso$etiqueta} — {e$message}")
      stop(e)
    }
  )
  cli_alert_success("{paso$etiqueta} — listo")
}

cli_h1("Pipeline completo")
cli_alert_info("Fin: {Sys.time()}")
cli_alert_success("Registros crudos:   data/raw/*_raw.csv")
cli_alert_success("Registros únicos:   data/processed/unique_records.csv")
