# Pull every regular-season pitch from Baseball Savant into DuckDB, a few days at a time.
# Resumable: date ranges already in load_log are skipped, so you can stop and rerun.
# Usage: Rscript R/02_pull_statcast.R 2019 2021 ...          (seasons; run 01_pull_games.R first)
#        Rscript R/02_pull_statcast.R 2025-07-01 2025-07-14  (a date range)

source("R/config.R")

DAYS_PER_REQUEST <- 4
ROW_CAP <- 25000  # Savant truncates CSV results at this many rows

CHAR_COLS <- c(
  "pitch_type", "game_date", "player_name", "events", "description", "des", "game_type",
  "stand", "p_throws", "home_team", "away_team", "type", "bb_type", "inning_topbot",
  "sv_id", "pitch_name", "if_fielding_alignment", "of_fielding_alignment"
)

savant_url <- function(start, end) sprintf(paste0(
  "https://baseballsavant.mlb.com/statcast_search/csv?all=true&type=details",
  "&player_type=batter&hfGT=R%%7C&game_date_gt=%s&game_date_lt=%s"
), start, end)

fetch_chunk <- function(start, end, tries = 3) {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  for (i in seq_len(tries)) {
    ok <- tryCatch(download.file(savant_url(start, end), tmp, quiet = TRUE, mode = "wb") == 0,
                   error = function(e) FALSE)
    if (ok) {
      if (length(readLines(tmp, n = 2, warn = FALSE)) < 2) return(data.frame())
      return(read.csv(tmp, stringsAsFactors = FALSE))
    }
    Sys.sleep(15 * i)
  }
  stop("Failed to download ", start, " to ", end)
}

# Fix column types so every chunk appends to the same table schema.
clean_chunk <- function(d) {
  for (nm in setdiff(names(d), CHAR_COLS)) d[[nm]] <- suppressWarnings(as.numeric(d[[nm]]))
  for (nm in intersect(names(d), CHAR_COLS)) {
    d[[nm]] <- as.character(d[[nm]])
    d[[nm]][d[[nm]] == ""] <- NA
  }
  d$game_date <- as.Date(d$game_date)
  d
}

load_chunk <- function(con, dates) {
  start <- min(dates); end <- max(dates)
  d <- fetch_chunk(start, end)

  if (nrow(d) >= ROW_CAP) {
    if (length(dates) == 1) stop("A single day hit Savant's row cap: ", start)
    half <- ceiling(length(dates) / 2)
    load_chunk(con, dates[1:half])
    load_chunk(con, dates[(half + 1):length(dates)])
    return(invisible())
  }

  if (nrow(d)) d <- clean_chunk(d)
  dbBegin(con)
  if (dbExistsTable(con, "pitches")) {
    dbExecute(con, "DELETE FROM pitches WHERE game_date BETWEEN ? AND ?", params = list(start, end))
  }
  if (nrow(d)) dbWriteTable(con, "pitches", d, append = TRUE)
  dbExecute(con, "INSERT INTO load_log VALUES (?, ?, ?, now())", params = list(start, end, nrow(d)))
  dbCommit(con)
  message(sprintf("%s to %s: %d pitches", start, end, nrow(d)))
  Sys.sleep(3)
}

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Pass seasons (2019 2021) or a date range (2025-07-01 2025-07-14)")

con <- db_connect()
invisible(dbExecute(con, "CREATE TABLE IF NOT EXISTS load_log
                          (start_date DATE, end_date DATE, n_rows INTEGER, loaded_at TIMESTAMP)"))

if (all(grepl("^\\d{4}$", args))) {
  dates <- dbGetQuery(con, sprintf(
    "SELECT DISTINCT game_date FROM games WHERE season IN (%s) ORDER BY game_date",
    paste(as.integer(args), collapse = ",")
  ))$game_date
  if (!length(dates)) stop("No games found for those seasons. Run R/01_pull_games.R first.")
} else {
  dates <- seq(as.Date(args[1]), as.Date(args[2]), by = "day")
}

log <- dbGetQuery(con, "SELECT start_date, end_date FROM load_log")
covered <- function(d) any(log$start_date <= d & log$end_date >= d)
todo <- dates[!vapply(seq_along(dates), function(i) covered(dates[i]), logical(1))]

message(sprintf("%d dates requested, %d already loaded", length(dates), length(dates) - length(todo)))
for (chunk in split(todo, ceiling(seq_along(todo) / DAYS_PER_REQUEST))) load_chunk(con, chunk)

dbDisconnect(con, shutdown = TRUE)
