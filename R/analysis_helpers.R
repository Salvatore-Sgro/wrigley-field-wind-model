# Shared helpers for the analysis scripts.

COLOR_WRIGLEY <- "#2F5FB3"
COLOR_CONTRAST <- "#D0453F"
COLOR_MUTED <- "#8A9099"

read_only_connection <- function() {
  dbConnect(duckdb(DB_PATH, read_only = TRUE, shared_home = FALSE))
}

# Fly balls and line drives with usable weather. Nearly every home run is one of these types (see
# output/batted_ball_types.csv); the rare ground-ball home run is left out.
load_air_balls <- function(where = "TRUE") {
  con <- read_only_connection()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  dbGetQuery(con, sprintf("
    SELECT *
    FROM batted_balls
    WHERE bb_type IN ('fly_ball', 'line_drive')
      AND wind_out IS NOT NULL
      AND temp IS NOT NULL
      AND %s
  ", where))
}

fit_hr_model <- function(data) {
  gam(is_hr ~ wind_out + te(launch_speed, launch_angle) + s(spray_angle) + temp,
      data = data, family = binomial, method = "REML")
}

# Temperature but no wind: compared with fit_hr_model, isolates what the wind adds.
fit_hr_model_no_wind <- function(data) {
  gam(is_hr ~ te(launch_speed, launch_angle) + s(spray_angle) + temp,
      data = data, family = binomial, method = "REML")
}

fit_hr_model_no_weather <- function(data) {
  gam(is_hr ~ te(launch_speed, launch_angle) + s(spray_angle),
      data = data, family = binomial, method = "REML")
}

# Seasons from 2022 on are "recent": validation showed older seasons teach a relationship that no
# longer holds. The newest season in the data is the out-of-sample test season.
FIRST_RECENT_SEASON <- 2022

# Writes a set of seasons compactly, e.g. c(2019, 2021, 2022, 2023) -> "2019, 2021-2023".
season_label <- function(seasons) {
  seasons <- sort(unique(seasons))
  runs <- split(seasons, cumsum(c(1, diff(seasons) != 1)))
  paste(sapply(runs, function(r) if (length(r) == 1) r else paste0(r[1], "-", r[length(r)])), collapse = ", ")
}

# Balls from one game share its single wind reading, so they aren't independent. This resamples whole
# games with replacement and returns the statistic from each resample (one row per resample).
game_bootstrap <- function(data, statistic, reps = 200, seed = 1) {
  set.seed(seed)
  rows_by_game <- split(seq_len(nrow(data)), data$game_pk)
  do.call(rbind, lapply(seq_len(reps), function(i) {
    picked <- sample(length(rows_by_game), replace = TRUE)
    statistic(data[unlist(rows_by_game[picked], use.names = FALSE), ])
  }))
}

brier <- function(y, p) mean((y - p)^2)
log_loss <- function(y, p) -mean(y * log(p) + (1 - y) * log(1 - p))

# The newest season in the data is the out-of-sample test season. A season still being downloaded
# would make a misleading test, so stop unless it looks complete.
MIN_TEST_GAMES <- 75
newest_full_season <- function(air) {
  season <- max(air$season)
  games <- length(unique(air$game_pk[air$season == season]))
  if (games < MIN_TEST_GAMES) {
    stop(sprintf("Newest season %d has only %d Wrigley games with usable weather; is it complete?", season, games))
  }
  season
}

# Replays past batted balls under the forecast weather: expected home runs per game.
forecast_hr <- function(model, balls, wind_speed, wind_label, temp) {
  if (wind_label != "Calm" && wind_speed != 0 && !wind_label %in% names(WIND_DIRS)) {
    stop("No direction for wind label '", wind_label, "'. Use one of: ",
         paste(c("Calm", names(WIND_DIRS)), collapse = ", "))
  }
  dir <- if (wind_label == "Calm" || wind_speed == 0) 0 else WIND_DIRS[[wind_label]]
  nd <- balls
  nd$wind_out <- wind_speed * cos((nd$spray_angle - dir) * pi / 180)
  nd$temp <- temp
  sum(predict(model, nd, type = "response")) / length(unique(balls$game_pk))
}

save_table <- function(data, name) {
  dir.create("output", showWarnings = FALSE)
  write.csv(data, file.path("output", paste0(name, ".csv")), row.names = FALSE)
  cat("\n", name, "\n", sep = "")
  print(as.data.frame(data), row.names = FALSE)
  invisible(data)
}

chart_theme <- function() {
  theme_minimal(base_size = 12) +
    theme(panel.grid.minor = element_blank(),
          plot.title = element_text(face = "bold"),
          plot.title.position = "plot",
          legend.position = "top",
          legend.justification = "left",
          legend.title = element_blank())
}

save_chart <- function(plot, name, width = 8, height = 4.8) {
  dir.create("output", showWarnings = FALSE)
  ggsave(file.path("output", paste0(name, ".png")), plot, width = width, height = height, dpi = 150, bg = "white")
}
