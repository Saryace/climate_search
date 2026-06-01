# ── Instalar paquetes necesarios ─────────────────────────────────────────────

# Instala estos paquetes desde CRAN

install.packages(c(
  "openalexR",   # Conexión con OpenAlex
  "rscopus",     # Conexión con Scopus
  "httr2",       # Solicitudes web/API
  "jsonlite",    # Leer archivos JSON
  "dplyr",       # Manipulación de datos
  "readr",       # Importar/exportar archivos
  "stringr",     # Manejo de texto
  "tidyr",       # Organización de tablas
  "purrr",       # Automatización de tareas
  "glue",        # Crear texto dinámico
  "cli",         # Mensajes en consola
  "fs",          # Manejo de carpetas y archivos
  "remotes"      # Instalar paquetes desde GitHub
))

# Instalar paquete desde GitHub

remotes::install_github("frbcesab/rwosstarter")

