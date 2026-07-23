# =============================================================================
# R/01_retrieve_openalex.R
#
# Descarga registros de OpenAlex buscando países en título y resumen,
# igual que WoS y Scopus — para que los resultados sean comparables.
#
# SI EL SCRIPT SE DETIENE POR CUALQUIER MOTIVO:
# ───────────────────────────────────────────────
# Volver a correr Guarda el progreso a medida que avanza
# (en data/raw/openalex_checkpoint.csv), así que automáticamente
# continua donde quedó, sin perder lo ya descargado ni repetir
# combinaciones.
#
# Para arrancar de cero (en vez de continuar), borra el checkpoint primero:
#   file.remove("data/raw/openalex_checkpoint.csv")
#
# SETUP
# ──────
# 1. Consigue una API key gratis en:
#    https://openalex.org/login?redirect=/settings/api-key
# 2. Abre el archivo `config.txt` (está en esta misma carpeta) con cualquier
#    editor de texto y pega tu email y tu clave entre las comillas:
#      OPENALEX_EMAIL="tu@email.com"
#      OPENALEX_API_KEY="tu_clave"
#    Guarda el archivo. ¡Listo! No hace falta reiniciar nada.
#    (Si `config.txt` no existe, copia `config.example.txt` y renómbralo a
#     `config.txt`. Alternativa avanzada: definir esas variables en .Renviron.)
#
# Salida:     data/raw/openalex_raw.csv
# Checkpoint: data/raw/openalex_checkpoint.csv
# Config:     config.txt   (credenciales; NO se versiona)
# Requiere:   openalexR, dplyr, readr, fs, purrr, tidyr
# =============================================================================

# Librerías --------------------------------------------------------------------
library(openalexR)
library(dplyr)
library(readr)
library(fs)
library(purrr)

# Cargar términos de búsqueda ---------------------------------------------------
source("R/queries.R")
source("R/funciones.R")

# Configuración ------------------------------------------------------------------
# Las credenciales NO se escriben aquí (para no versionarlas). Se leen así:
#   1. Del archivo visible `config.txt` en esta carpeta (la forma recomendada:
#      ábrelo con cualquier editor de texto y cambia los valores). Formato:
#         OPENALEX_EMAIL="tu@email.com"
#         OPENALEX_API_KEY="tu_clave"
#   2. Si config.txt no existe (o le falta un valor), se usa la variable de
#      entorno correspondiente (por ej. definida en .Renviron).
# Consigue tu API key gratis en: https://openalex.org/login?redirect=/settings/api-key
CONFIG_FILE <- "config.txt"

# Lee credenciales: arranca desde el entorno y las sobrescribe con lo que haya en
# config.txt (así config.txt tiene prioridad, y el entorno queda como respaldo).
leer_credenciales <- function(path) {
  cred <- list(email  = Sys.getenv("OPENALEX_EMAIL"),
               apikey = Sys.getenv("OPENALEX_API_KEY"))
  if (file.exists(path)) {
    lineas <- trimws(readLines(path, warn = FALSE))
    lineas <- lineas[nzchar(lineas) & !startsWith(lineas, "#")]  # ignora vacías y comentarios
    for (ln in lineas) {
      partes <- strsplit(ln, "=", fixed = TRUE)[[1]]
      if (length(partes) < 2) next
      clave <- trimws(partes[1])
      valor <- gsub('^"|"$', "", trimws(paste(partes[-1], collapse = "=")))  # quita comillas opcionales
      if (clave == "OPENALEX_EMAIL")   cred$email  <- valor
      if (clave == "OPENALEX_API_KEY") cred$apikey <- valor
    }
  }
  cred
}

cred      <- leer_credenciales(CONFIG_FILE)
MY_EMAIL  <- cred$email
MY_APIKEY <- cred$apikey

if (MY_EMAIL == "") {
  stop("Falta el email. Abre el archivo '", CONFIG_FILE, "' y completa:\n",
       '  OPENALEX_EMAIL="tu@email.com"\n',
       "(o define OPENALEX_EMAIL en tu .Renviron). Ver instrucciones al inicio del script.")
}
if (MY_APIKEY == "") {
  warning("No hay API key: se usará solo el 'polite pool' (mailto), que OpenAlex ",
          "limita con 429. Recomendado: completa OPENALEX_API_KEY en '", CONFIG_FILE, "'.")
}

# Registrar mailto y api_key globalmente para que TODAS las peticiones de
# openalexR (incluida la paginación interna) usen la clave y caigan en el pool
# autenticado. Sin la clave, OpenAlex limita el "polite pool" y devuelve 429.
options(openalexR.mailto = MY_EMAIL, openalexR.apikey = MY_APIKEY)

OUT_FILE        <- "data/raw/openalex_raw.csv"
CHECKPOINT_FILE <- "data/raw/openalex_checkpoint.csv"  # DATOS descargados (esquema fijo)
DONE_FILE       <- "data/raw/openalex_done.txt"        # combos completados (1 por línea)
PAUSA_SEG       <- 5L   # segundos entre llamadas
PAUSA_MIN       <- 1L    # piso: nunca esperar menos que esto entre peticiones (aunque PAUSA_SEG sea 0)

# Reintentos ante fallos HTTP transitorios (429/503/timeout). El backoff es una
# lista explícita: la espera ANTES del reintento i es BACKOFF_SEG[i]. Escala rápido
# al principio (recupera bloqueos cortos en segundos) y aguanta bloqueos largos al
# final, para poder dejarlo corriendo toda la noche si OpenAlex está muy limitado.
# Cuando el bloqueo se levanta, el siguiente intento es inmediato (no se espera de más).
BACKOFF_SEG  <- c(10, 60, 120, 300, 900, 1800, 3600)  # 10s, 1m, 2m, 5m, 15m, 30m, 1h
MAX_INTENTOS <- length(BACKOFF_SEG) + 1L               # intento inicial + un reintento por espera

dir_create("data/raw")

# Esquema FIJO de salida. Cada combinación descargada devuelve columnas distintas
# (según los datos), así que forzamos SIEMPRE este conjunto de columnas escalares
# antes de escribir. Así el CSV es rectangular y se puede releer sin errores.
# (El bug anterior: append de filas con distinto nº de columnas → CSV corrupto.)
COLS_SALIDA <- c(
  "id", "doi", "title", "display_name", "publication_year",
  "publication_date", "type", "language", "cited_by_count",
  "author", "ab", "source_db", "query_language", "pais_consulta", "combo_id"
)

# Campos a solicitar a la API de OpenAlex.
FIELDS <- c(
  "id", "doi", "title", "display_name", "publication_year",
  "publication_date", "type", "language",
  "primary_location", "authorships", "abstract_inverted_index",
  "cited_by_count"
)

# ── Construir combinaciones: consulta base × país × año ───────────────────────

combinaciones <- bind_rows(
  tidyr::crossing(
    lang = "english",    base = oa_queries[["english"]],    pais = countries_en, anio = YEAR_FROM:YEAR_TO
  ),
  tidyr::crossing(
    lang = "spanish",    base = oa_queries[["spanish"]],    pais = countries_es, anio = YEAR_FROM:YEAR_TO
  ),
  tidyr::crossing(
    lang = "portuguese", base = oa_queries[["portuguese"]], pais = countries_pt, anio = YEAR_FROM:YEAR_TO
  )
) %>%
  mutate(combo_id = paste(lang, pais, anio, sep = " :: "))

message("Total de combinaciones: ", nrow(combinaciones))

# ── Checkpoint: cargar combinaciones ya completadas, si existen ──────────────

ya_hechas <- character(0)
if (file_exists(DONE_FILE)) {
  ya_hechas <- unique(read_lines(DONE_FILE))
  message("Checkpoint encontrado: ", length(ya_hechas), " combinaciones ya completadas. Se omitirán.")
}

pendientes <- combinaciones %>% filter(!combo_id %in% ya_hechas)
message("Combinaciones pendientes: ", nrow(pendientes))

if (nrow(pendientes) > 0) {
  message(
    "\n============================================================\n",
    "Si este script se detiene o falla por cualquier motivo,\n",
    "simplemente vuelve a ejecutarlo — continuará automáticamente\n",
    "donde quedó, sin perder el progreso ya descargado.\n",
    "============================================================\n"
  )
}

# ── Función: descargar una combinación (país + año + idioma) ─────────────────

fetch_uno <- function(base, pais, anio, lang) {
  query <- paste0(base, ' AND "', pais, '"')
  
  # Reintentamos hasta MAX_INTENTOS con backoff exponencial. Los fallos HTTP de
  # OpenAlex (429/503/timeout) suelen ser transitorios: esperar y reintentar los
  # resuelve sin perder la combinación ni esperar a la próxima ejecución.
  for (intento in seq_len(MAX_INTENTOS)) {
    Sys.sleep(max(PAUSA_SEG, PAUSA_MIN))  # siempre esperar al menos un poco
    
    # openalexR NO lanza error ante fallos HTTP (429 Too Many Requests, 503 Service
    # Unavailable, otros códigos, timeouts, paginación cortada a la mitad): solo emite
    # un `message` y devuelve 0 filas o resultados PARCIALES. Como con verbose=FALSE
    # openalexR no emite ningún otro mensaje, tratamos CUALQUIER mensaje durante la
    # descarga como fallo. Es más seguro reintentar de más que guardar datos
    # incompletos y marcarlos como "completados".
    fallo        <- FALSE
    motivo_fallo <- NA_character_
    res <- withCallingHandlers(
      tryCatch(
        oa_fetch(
          entity                    = "works",
          title_and_abstract.search = query,
          publication_year          = anio,
          options                   = list(select = FIELDS),
          mailto                    = MY_EMAIL,
          api_key                   = if (nchar(MY_APIKEY) > 0) MY_APIKEY else NULL,
          verbose                   = FALSE
        ),
        error = function(e) {
          fallo        <<- TRUE
          motivo_fallo <<- conditionMessage(e)
          NULL
        }
      ),
      message = function(m) {
        fallo        <<- TRUE
        motivo_fallo <<- trimws(conditionMessage(m))
      }
    )
    
    # Éxito: devolvemos los datos (o un tibble vacío si 0 resultados reales).
    if (!fallo) {
      if (is.null(res) || nrow(res) == 0) return(tibble())
      return(res %>% mutate(source_db = "OpenAlex", query_language = lang, pais_consulta = pais))
    }
    
    # Fallo con intentos restantes → esperar según la lista de backoff y reintentar.
    if (intento < MAX_INTENTOS) {
      espera <- max(BACKOFF_SEG[intento], PAUSA_MIN)          # espera programada, nunca bajo el piso
      espera <- espera + stats::runif(1, 0, min(espera * 0.1, 15))  # jitter acotado: no sincroniza reintentos
      message("  ⚠️  Intento ", intento, "/", MAX_INTENTOS, " falló [", lang, " | ", pais,
              " | ", anio, "]: ", motivo_fallo, " — reintentando en ", round(espera), "s ...")
      Sys.sleep(espera)
    } else {
      # Agotados los intentos: devolvemos NULL para que el loop NO marque la
      # combinación como completada; se reintentará en la próxima ejecución.
      message("  ✗ Falló tras ", MAX_INTENTOS, " intentos [", lang, " | ", pais, " | ", anio,
              "]: ", motivo_fallo, " — se reintentará en la próxima ejecución.")
      return(NULL)
    }
  }
}

# ── Aplanar columnas anidadas de un data frame recién descargado ─────────────

aplanar <- function(df) {
  if ("author" %in% names(df)) {
    df$author <- vapply(df$author, function(a) {
      if (is.null(a) || !is.data.frame(a) || !"au_display_name" %in% names(a)) {
        return(NA_character_)
      }
      paste(a$au_display_name, collapse = "; ")
    }, character(1))
  }
  list_cols <- names(df)[vapply(df, is.list, logical(1))]
  if (length(list_cols) > 0) df <- df %>% select(-all_of(list_cols))
  df
}

# ── Forzar el esquema fijo: exactamente COLS_SALIDA, en orden, rellenando con NA
#    las columnas que falten. Garantiza que el CSV siempre sea rectangular. ─────

normalizar <- function(df) {
  faltantes <- setdiff(COLS_SALIDA, names(df))
  for (col in faltantes) df[[col]] <- NA
  df[, COLS_SALIDA, drop = FALSE]
}

# ── Marcar una combinación como completada (registro append-only, 1 por línea).
#    Separa el "qué ya se hizo" de los datos, para no depender del CSV. ─────────

marcar_hecho <- function(combo_id) {
  cat(combo_id, "\n", sep = "", file = DONE_FILE, append = TRUE)
}

# ── Descarga con checkpoint ───────────────────────────────────────────────────

message("\nIniciando descarga ...")

if (nrow(pendientes) > 0) {
  for (i in seq_len(nrow(pendientes))) {
    fila <- pendientes[i, ]
    message("  [", i, "/", nrow(pendientes), "] ", fila$lang, " | ", fila$pais, " | ", fila$anio)
    
    res <- fetch_uno(fila$base, fila$pais, fila$anio, fila$lang)
    
    if (is.null(res)) {
      # Petición fallida (429/error): NO la marcamos como completada, así se
      # reintenta en la próxima ejecución en vez de perderse silenciosamente.
      next
    }
    
    if (nrow(res) > 0) {
      res <- aplanar(res) %>% mutate(combo_id = fila$combo_id) %>% normalizar()
      write_csv(res, CHECKPOINT_FILE, append = file_exists(CHECKPOINT_FILE))
    }
    # Con datos o vacío (0 resultados reales): la combinación quedó completada.
    # Los fallos (429/error) ya salieron antes con `next`, así que NUNCA se marcan.
    marcar_hecho(fila$combo_id)
  }
} else {
  message("Nada pendiente — todas las combinaciones ya estaban en el checkpoint.")
}

# ── Verificar si quedó algo pendiente (por si el loop se cortó a mitad) ──────

hechas_final <- if (file_exists(DONE_FILE)) unique(read_lines(DONE_FILE)) else character(0)
pendientes_final <- combinaciones %>% filter(!combo_id %in% hechas_final)

if (nrow(pendientes_final) > 0) {
  message(
    "\n⚠️  El script se detuvo antes de terminar. Quedan ",
    nrow(pendientes_final), " combinaciones pendientes.\n",
    "Simplemente vuelve a ejecutar este mismo script para continuar."
  )
} else {
  message("\n✅ Descarga completa — no quedan combinaciones pendientes.")
}

message("\nConsolidando resultados desde el checkpoint...")

# ── Consolidar desde checkpoint ───────────────────────────────────────────────

if (!file_exists(CHECKPOINT_FILE)) {
  message("Todavía no hay datos descargados (", CHECKPOINT_FILE, " no existe). ",
          "Vuelve a ejecutar el script para continuar la descarga.")
} else {
  all_raw <- read_csv(CHECKPOINT_FILE, show_col_types = FALSE) %>%
    filter(!is.na(id))
  
  message("Registros brutos descargados: ", nrow(all_raw))
  
  # ── Normalizar DOI ──────────────────────────────────────────────────────────
  
  all_raw <- all_raw %>%
    mutate(doi_clean = tolower(trimws(coalesce(doi, NA_character_))))
  
  # ── Deduplicar (muchos registros aparecen en varios países) ─────────────────
  
  has_doi <- all_raw %>% filter(!is.na(doi_clean) & doi_clean != "")
  no_doi  <- all_raw %>% filter(is.na(doi_clean)  | doi_clean == "")
  
  all_dedup <- bind_rows(
    has_doi %>% arrange(doi_clean) %>% distinct(doi_clean, .keep_all = TRUE),
    no_doi  %>%
      mutate(title_norm = tolower(trimws(coalesce(display_name, "")))) %>%
      distinct(title_norm, .keep_all = TRUE) %>%
      select(-title_norm)
  )
  
  message("Tras deduplicación: ", nrow(all_dedup),
          " registros (", nrow(all_raw) - nrow(all_dedup), " eliminados)")
  
  # ── Guardar ─────────────────────────────────────────────────────────────────
  
  write_csv(all_dedup, OUT_FILE)
  message("Guardado en ", OUT_FILE)
}