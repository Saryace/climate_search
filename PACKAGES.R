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

# ── Configuración de claves API ──────────────────────────────────────────────

# Algunas bases de datos requieren claves de acceso (API keys).

# Estas claves son personales y NO deben compartirse públicamente.

# Para configurarlas:

# 1. Ejecuta en R:

#

# usethis::edit_r_environ()

#

# 2. Se abrirá el archivo ~/.Renviron

#

# 3. Agrega tus claves así:

#

# WOS_STARTER_KEY="tu_clave_wos"

# Elsevier_API="tu_clave_scopus"

#

# 4. Guarda el archivo y reinicia R.

# ⚠ IMPORTANTE:

# - No subir claves API a GitHub

# - No compartir claves en correos o documentos públicos

# - Mantener el archivo .Renviron privado

# ── Obtener claves API ───────────────────────────────────────────────────────

# Web of Science Starter API

# Sitio:

# https://developer.clarivate.com

#

# La versión gratuita permite aproximadamente:

# - hasta 1000 registros por consulta por día

# Scopus / Elsevier API

# Sitio:

# https://dev.elsevier.com

#

# Requiere:

# - suscripción institucional

# - acceso desde red universitaria usar un VPN institucional

#

# La clave suele estar vinculada a la IP institucional.

# ── Alternativa manual (sin API) ─────────────────────────────────────────────

# Si no tienes claves API, puedes exportar resultados manualmente

# desde las plataformas y guardar los archivos aquí:

# Web of Science (.txt)

# Debes seleccionar al exportar lo siguiente:

# Format: Plain Text
# Record content: Full Record

# Luego descargar búsquedas acá:

# data/raw/wos_export_english.txt

# data/raw/wos_export_spanish.txt

# data/raw/wos_export_portuguese.txt

# Scopus (.csv)

# En Scopus debes seleccionar toda la información de "Citation information" y sumar en "Abstract & keywords" la opción Abstracts

# data/raw/scopus_export_english.csv

# data/raw/scopus_export_spanish.csv

# data/raw/scopus_export_portuguese.csv

# En el pipeline se puede eler

# - modo API

# - o archivos exportados manualmente
