
# or_string ---------------------------------------------------------------

# Une un vector de términos en "A OR B OR C" (por defecto entre comillas).
or_string <- function(terms, quote = TRUE) {
  if (quote) terms <- paste0('"', terms, '"')
  paste(terms, collapse = " OR ")
}

# concept_block -----------------------------------------------------------

# Convierte UNA lista de conceptos en un grupo entre paréntesis: (a OR b ...).
# Los términos de varias palabras van entre comillas (frase exacta); las
# palabras sueltas y los comodines quedan sin comillas.

concept_block <- function(terms) {
  quoted <- ifelse(grepl(" ", terms), paste0('"', terms, '"'), terms)
  paste0("(", paste(quoted, collapse = " OR "), ")")
}

# all_of ------------------------------------------------------------------

# Une varios bloques de conceptos con AND.
all_of <- function(...) paste(c(...), collapse = " AND ")


# col or na ---------------------------------------------------------------

# Devuelve la columna 'name' si existe en df; si no, un marcador NA.
# Mantiene robustez cuando la API no devuelve, se usa en WOS
col_or_na <- function(df, name, na = NA_character_) {
  if (name %in% names(df)) df[[name]] else na
}

# and query ---------------------------------------------------------------

# Arma la consulta completa uniendo bloques con AND
and_query <- function(...) {
  paste(list(...), collapse = " AND ")
}

