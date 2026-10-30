# Fits the final model on recent seasons, estimates home runs added by wind, and tests the pre-game
# forecast on 2025.
# Usage: Rscript R/07_results.R

source("R/config.R")
source("R/analysis_helpers.R")
suppressPackageStartupMessages({
  library(mgcv)
  library(ggplot2)
})

air <- load_air_balls("venue_name = 'Wrigley Field'")

# Validation showed older seasons teach a relationship that no longer holds.
final_balls <- subset(air, season >= 2022)
final_model <- fit_hr_model(final_balls)

save_table(data.frame(
  term = c("Tailwind", "Temperature"),
  odds_ratio_per_unit = round(exp(coef(final_model)[c("wind_out", "temp")]), 3),
  odds_ratio_15_units = round(exp(15 * coef(final_model)[c("wind_out", "temp")]), 2)
), "final_model_odds_ratios")

# ---- Home runs added by wind: the same ball, with the actual wind vs no wind --------------
final_balls$p_actual <- predict(final_model, final_balls, type = "response")
final_balls$p_calm <- predict(final_model, transform(final_balls, wind_out = 0), type = "response")

by_game <- do.call(rbind, lapply(split(final_balls, final_balls$game_pk), function(d) data.frame(
  game_date = d$game_date[1], season = d$season[1], wind_label = d$wind_label[1],
  wind_speed = d$wind_speed[1], temp = d$temp[1], home_runs = sum(d$is_hr),
  expected_hr = sum(d$p_actual), hr_from_wind = sum(d$p_actual - d$p_calm)
)))
by_game_rounded <- transform(by_game, expected_hr = round(expected_hr, 3), hr_from_wind = round(hr_from_wind, 3))
write.csv(by_game_rounded, "output/wind_effect_by_game.csv", row.names = FALSE)
print(summary(by_game$hr_from_wind))

summarise_groups <- function(column) {
  do.call(rbind, lapply(split(by_game, by_game[[column]]), function(d) {
    row <- data.frame(games = nrow(d), home_runs = sum(d$home_runs), hr_per_game = round(mean(d$home_runs), 2),
                      avg_mph = round(mean(d$wind_speed), 1), hr_from_wind_per_game = round(mean(d$hr_from_wind), 2),
                      hr_from_wind_total = round(sum(d$hr_from_wind), 1))
    row[[column]] <- d[[column]][1]
    row[, c(column, setdiff(names(row), column))]
  }))
}
by_direction <- summarise_groups("wind_label")
by_direction <- by_direction[order(-by_direction$hr_from_wind_per_game), ]
save_table(by_direction, "wind_effect_by_direction")
save_table(summarise_groups("season"), "wind_effect_by_season")

columns <- c("game_date", "wind_label", "wind_speed", "temp", "home_runs", "hr_from_wind")
print(head(by_game[order(-by_game$hr_from_wind), columns], 3), row.names = FALSE)
print(head(by_game[order(by_game$hr_from_wind), columns], 3), row.names = FALSE)

by_direction$wind_label <- factor(by_direction$wind_label, levels = rev(by_direction$wind_label))
chart <- ggplot(by_direction, aes(hr_from_wind_per_game, wind_label,
                                  fill = hr_from_wind_per_game > 0)) +
  geom_col(width = 0.7) +
  geom_vline(xintercept = 0, colour = COLOR_MUTED) +
  geom_text(aes(label = sprintf("%+.2f", hr_from_wind_per_game),
                hjust = ifelse(hr_from_wind_per_game > 0, -0.15, 1.15)), size = 3.4) +
  scale_fill_manual(values = c("TRUE" = COLOR_WRIGLEY, "FALSE" = COLOR_CONTRAST), guide = "none") +
  scale_x_continuous(expand = expansion(mult = 0.15)) +
  labs(title = "Home runs per game added or removed by the wind at Wrigley",
       subtitle = "Model estimate, 2022-2025, compared with the same batted balls in calm air.",
       x = "Home runs per game", y = NULL) +
  chart_theme()
save_chart(chart, "wind_effect_by_direction")

# ---- Forecast scenarios -------------------------------------------------------------------
scenarios <- data.frame(
  wind_label = c("Calm", "Out To CF", "Out To CF", "In From CF", "In From CF", "L To R"),
  wind_speed = c(0, 10, 20, 10, 20, 15),
  temp = c(70, 75, 85, 60, 50, 70)
)
scenarios$expected_hr <- round(mapply(function(s, l, t) forecast_hr(final_model, final_balls, s, l, t),
                                      scenarios$wind_speed, scenarios$wind_label, scenarios$temp), 2)
save_table(scenarios, "forecast_scenarios")

# ---- Testing the pre-game forecast on 2025 --------------------------------------------------
past <- subset(air, season %in% 2022:2024)
test <- subset(air, season == 2025)
past_model <- fit_hr_model(past)

games_2025 <- do.call(rbind, lapply(split(test, test$game_pk), function(d) data.frame(
  wind_label = d$wind_label[1], wind_speed = d$wind_speed[1], temp = d$temp[1], home_runs = sum(d$is_hr)
)))
games_2025$forecast <- mapply(function(s, l, t) forecast_hr(past_model, past, s, l, t),
                              games_2025$wind_speed, games_2025$wind_label, games_2025$temp)
naive <- sum(past$is_hr) / length(unique(past$game_pk))

save_table(data.frame(
  forecast = c("Past average", "Weather forecast"),
  avg_forecast = round(c(naive, mean(games_2025$forecast)), 2),
  avg_actual = round(mean(games_2025$home_runs), 2),
  avg_miss = round(c(mean(abs(games_2025$home_runs - naive)),
                     mean(abs(games_2025$home_runs - games_2025$forecast))), 2)
), "forecast_test_2025")
cat("Correlation of forecast with actual home runs:", round(cor(games_2025$forecast, games_2025$home_runs), 2), "\n")

games_2025$group <- cut(games_2025$forecast, quantile(games_2025$forecast, c(0, 1/3, 2/3, 1)),
                        include.lowest = TRUE, labels = c("Low", "Middle", "High"))
save_table(do.call(rbind, lapply(split(games_2025, games_2025$group), function(d) data.frame(
  forecast_group = d$group[1], games = nrow(d), forecast = round(mean(d$forecast), 2),
  actual = round(mean(d$home_runs), 2)
))), "forecast_test_2025_groups")

# Why it runs low before the game: 2025 had more and better contact than the seasons it replays.
save_table(data.frame(
  seasons = c("2022-2024", "2025"),
  balls_in_air_per_game = round(c(nrow(past) / length(unique(past$game_pk)),
                                  nrow(test) / length(unique(test$game_pk))), 1),
  hard_contact_per_game = round(c(
    sum(past$launch_speed >= 100 & past$launch_angle >= 22 & past$launch_angle <= 34) / length(unique(past$game_pk)),
    sum(test$launch_speed >= 100 & test$launch_angle >= 22 & test$launch_angle <= 34) / length(unique(test$game_pk))
  ), 1)
), "contact_per_game")
