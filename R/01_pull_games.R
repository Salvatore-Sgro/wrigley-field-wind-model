# Pull regular-season games with venue and game-time weather from the MLB Stats API.
# Usage: Rscript R/01_pull_games.R 2019 2020 2021 ...

source("R/config.R")

get_col <- function(df, name) if (name %in% names(df)) df[[name]] else rep(NA, nrow(df))

fetch_season <- function(season) {
  url <- sprintf(paste0(
    "https://statsapi.mlb.com/api/v1/schedule?sportId=1&gameType=R",
    "&startDate=%d-02-01&endDate=%d-11-30&hydrate=weather,venue"
  ), season, season)
  s <- jsonlite::fromJSON(url, flatten = TRUE)

  games <- bind_rows(lapply(s$dates$games, function(g) data.frame(
    game_pk        = g$gamePk,
    season         = season,
    game_date      = as.Date(g$officialDate),
    state          = get_col(g, "status.detailedState"),
    venue_id       = get_col(g, "venue.id"),
    venue_name     = get_col(g, "venue.name"),
    home_team_name = get_col(g, "teams.home.team.name"),
    day_night      = get_col(g, "dayNight"),
    condition      = get_col(g, "weather.condition"),
    temp           = suppressWarnings(as.numeric(get_col(g, "weather.temp"))),
    wind_raw       = get_col(g, "weather.wind"),
    stringsAsFactors = FALSE
  )))

  games <- games |>
    filter(state %in% c("Final", "Game Over", "Completed Early")) |>
    group_by(game_pk) |> slice_max(game_date, n = 1, with_ties = FALSE) |> ungroup() |>
    select(-state)

  games$wind_speed   <- suppressWarnings(as.numeric(sub("^(\\d+) mph.*$", "\\1", games$wind_raw)))
  games$wind_label   <- trimws(sub("^\\d+ mph,?\\s*", "", games$wind_raw))
  games$wind_dir_deg <- unname(WIND_DIRS[games$wind_label])
  # Calm air has no direction but a known (near-zero) effect; "Varies" stays NA and is excluded later.
  calm <- games$wind_speed %in% 0 | games$wind_label %in% "Calm"
  games$wind_speed[calm] <- 0
  games$wind_dir_deg[calm] <- 0
  games$indoor <- games$condition %in% c("Dome", "Roof Closed")
  games
}

seasons <- as.integer(commandArgs(trailingOnly = TRUE))
if (!length(seasons)) stop("Pass one or more seasons, e.g. Rscript R/01_pull_games.R 2025")

con <- db_connect()
for (season in seasons) {
  games <- fetch_season(season)
  if (dbExistsTable(con, "games")) dbExecute(con, "DELETE FROM games WHERE season = ?", params = list(season))
  dbWriteTable(con, "games", games, append = TRUE)
  message(sprintf("%d: %d games, %.0f%% with usable wind",
                  season, nrow(games), 100 * mean(!is.na(games$wind_dir_deg))))
}
dbDisconnect(con, shutdown = TRUE)
