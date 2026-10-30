# Shared setup. Every script is run from the project root, e.g. Rscript R/01_pull_games.R 2025

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(dplyr)
})

DB_PATH <- "data/baseball.duckdb"

# MLB's wind labels are relative to the field, viewed from home plate.
# Angles use the same convention as spray angle: 0 = toward CF, positive = toward RF.
WIND_DIRS <- c(
  "Out To CF" = 0, "Out To RF" = 45, "Out To LF" = -45,
  "In From CF" = 180, "In From LF" = 135, "In From RF" = -135,
  "L To R" = 90, "R To L" = -90
)

db_connect <- function() {
  dir.create("data", showWarnings = FALSE)
  dbConnect(duckdb(DB_PATH, shared_home = FALSE))
}
