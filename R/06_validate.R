# Tests the home-run model on seasons it never saw. Splits are by season, not at random: balls from
# one game share its conditions, and a random split would also train on the future.
# Usage: Rscript R/06_validate.R

source("R/config.R")
source("R/analysis_helpers.R")
suppressPackageStartupMessages({
  library(mgcv)
  library(ggplot2)
})

air <- load_air_balls("venue_name = 'Wrigley Field'")

# ---- Walk-forward: always train only on earlier seasons -------------------------------
walk_forward <- do.call(rbind, lapply(2022:2025, function(test_season) {
  train <- subset(air, season < test_season)
  test <- subset(air, season == test_season)
  with_weather <- fit_hr_model(train)
  no_weather <- fit_hr_model_no_weather(train)
  p_with <- predict(with_weather, test, type = "response")
  p_without <- predict(no_weather, test, type = "response")
  data.frame(
    season = test_season,
    brier_no_weather = round(brier(test$is_hr, p_without), 4),
    brier_with_weather = round(brier(test$is_hr, p_with), 4),
    odds_ratio_per_mph = round(exp(coef(with_weather)[["wind_out"]]), 3),
    predicted_hr = round(sum(p_with)),
    actual_hr = sum(test$is_hr),
    too_high_pct = round(100 * (sum(p_with) / sum(test$is_hr) - 1))
  )
}))
save_table(walk_forward, "walk_forward_results")

long <- rbind(
  data.frame(season = walk_forward$season, group = "Predicted", home_runs = walk_forward$predicted_hr),
  data.frame(season = walk_forward$season, group = "Actual", home_runs = walk_forward$actual_hr)
)
chart <- ggplot(long, aes(factor(season), home_runs, fill = group)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.68) +
  geom_text(aes(label = home_runs), position = position_dodge(width = 0.75), vjust = -0.4, size = 3.4) +
  scale_fill_manual(values = c("Predicted" = COLOR_CONTRAST, "Actual" = COLOR_WRIGLEY)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(title = "The model predicted too many home runs in every test season",
       subtitle = "Trained only on earlier seasons, then given each ball's actual contact and weather.",
       x = NULL, y = "Home runs at Wrigley") +
  chart_theme()
save_chart(chart, "predicted_vs_actual_by_season")

# ---- The 2025 test in detail ------------------------------------------------------------
train <- subset(air, season < 2025)
test <- subset(air, season == 2025)
model_all <- fit_hr_model(train)
p_all <- predict(model_all, test, type = "response")

p_base <- rep(mean(train$is_hr), nrow(test))
p_logistic <- predict(glm(is_hr ~ wind_out + launch_speed + launch_angle + temp, data = train, family = binomial),
                      test, type = "response")
p_no_weather <- predict(fit_hr_model_no_weather(train), test, type = "response")
save_table(data.frame(
  model = c("Average rate", "Logistic regression", "GAM, no weather", "GAM, with weather"),
  brier = round(c(brier(test$is_hr, p_base), brier(test$is_hr, p_logistic),
                  brier(test$is_hr, p_no_weather), brier(test$is_hr, p_all)), 4),
  log_loss = round(c(log_loss(test$is_hr, p_base), log_loss(test$is_hr, p_logistic),
                     log_loss(test$is_hr, p_no_weather), log_loss(test$is_hr, p_all)), 4)
), "scores_on_2025")

calibration <- data.frame(p = p_all, y = test$is_hr)
calibration$bucket <- cut(calibration$p, c(0, .01, .05, .1, .25, .5, .75, .9, 1), include.lowest = TRUE)
save_table(do.call(rbind, lapply(split(calibration, calibration$bucket), function(d) data.frame(
  predicted_range = as.character(d$bucket[1]), balls = nrow(d),
  predicted = round(mean(d$p), 3), actual = round(mean(d$y), 3)
))), "calibration_2025")

# ---- Why it runs high: the same contact has been carrying less ----------------------------
hard_contact <- subset(air, launch_speed >= 100 & launch_angle >= 22 & launch_angle <= 34)
save_table(do.call(rbind, lapply(split(hard_contact, hard_contact$season), function(d) data.frame(
  season = d$season[1], balls = nrow(d), hr_rate = round(mean(d$is_hr), 3),
  avg_exit_velocity = round(mean(d$launch_speed), 1),
  avg_distance_ft = round(mean(d$hit_distance_sc, na.rm = TRUE)),
  avg_tailwind = round(mean(d$wind_out), 1)
))), "hard_contact_by_season")

# ---- A fix: train only on recent seasons --------------------------------------------------
recent <- subset(air, season %in% 2022:2024)
p_recent <- predict(fit_hr_model(recent), test, type = "response")
save_table(data.frame(
  training_seasons = c("2019, 2021-2024", "2022-2024"),
  balls = c(nrow(train), nrow(recent)),
  brier = round(c(brier(test$is_hr, p_all), brier(test$is_hr, p_recent)), 4),
  predicted_hr = round(c(sum(p_all), sum(p_recent))),
  actual_hr = sum(test$is_hr)
), "recent_seasons_fix")
