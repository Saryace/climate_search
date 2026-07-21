# =============================================================================
# tests/test_openalex_env.R
#
# Comprueba que las credenciales de OpenAlex estén configuradas ANTES de
# lanzar la descarga en R/01_retrieve_openalex.R (que requiere OPENALEX_EMAIL
# y falla con stop() si falta).
#
# Uso:
#   Rscript tests/test_openalex_env.R
#   (o source("tests/test_openalex_env.R") desde una sesión interactiva)
#
# Sale con estado 0 si OPENALEX_EMAIL está presente y con forma de correo;
# sale con estado != 0 (vía stop()) en caso contrario.
# =============================================================================

library(cli)

cli_h1("Test: credenciales de OpenAlex")

email   <- Sys.getenv("OPENALEX_EMAIL")
api_key <- Sys.getenv("OPENALEX_API_KEY")

ok <- TRUE

if (nchar(email) == 0) {
  cli_alert_danger("OPENALEX_EMAIL no está configurado en ~/.Renviron")
  ok <- FALSE
} else if (!grepl("^[^@ ]+@[^@ ]+\\.[^@ ]+$", email)) {
  cli_alert_danger("OPENALEX_EMAIL no tiene forma de correo válido: {email}")
  ok <- FALSE
} else {
  cli_alert_success("OPENALEX_EMAIL configurado: {email}")
}

if (nchar(api_key) == 0) {
  cli_alert_info("OPENALEX_API_KEY no configurado (opcional, aumenta límites de la API)")
} else {
  cli_alert_success("OPENALEX_API_KEY configurado")
}

if (!ok) {
  stop(
    "Faltan credenciales de OpenAlex. Agrega a ~/.Renviron y reinicia R:\n",
    '  OPENALEX_EMAIL="tu@email.com"\n',
    '  OPENALEX_API_KEY="tu_clave"   # opcional'
  )
}

cli_alert_success("Listo para ejecutar R/01_retrieve_openalex.R")
