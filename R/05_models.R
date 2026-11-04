# Builds up the distance and home-run models one step at a time, tracking how the wind estimate
# changes. Every step keeps the same rows, so changes come from the model and not the data.
# Usage: Rscript R/05_models.R

source("R/config.R")
source("R/analysis_helpers.R")
suppressPackageStartupMessages({
  library(mgcv)
  library(ggplot2)
})

air <- load_air_balls()
flies <- subset(air, bb_type == "fly_ball" & !is.na(hit_distance_sc))
wr <- subset(flies, venue_name == "Wrigley Field")
outdoor <- subset(flies, !indoor)
cat("Wrigley fly balls:", nrow(wr), " Outdoor fly balls:", nrow(outdoor), "\n")

# ---- Distance at Wrigley ----------------------------------------------------------
distance_models <- list(
  "Tailwind only" = lm(hit_distance_sc ~ wind_out, data = wr),
  "Add exit velocity, launch angle, temperature" =
    lm(hit_distance_sc ~ wind_out + launch_speed + launch_angle + temp, data = wr),
  "Launch angle as a quadratic" =
    lm(hit_distance_sc ~ wind_out + launch_speed + launch_angle + I(launch_angle^2) + temp, data = wr),
  "Smooth launch angle" =
    gam(hit_distance_sc ~ wind_out + launch_speed + s(launch_angle) + temp, data = wr, method = "REML"),
  "Smooth exit velocity too" =
    gam(hit_distance_sc ~ wind_out + s(launch_speed) + s(launch_angle) + temp, data = wr, method = "REML"),
  "Exit velocity and launch angle interact" =
    gam(hit_distance_sc ~ wind_out + te(launch_speed, launch_angle) + temp, data = wr, method = "REML"),
  "Add hit direction" =
    gam(hit_distance_sc ~ wind_out + te(launch_speed, launch_angle) + s(spray_angle) + temp, data = wr, method = "REML")
)
r_squared <- function(m) if (inherits(m, "gam")) summary(m)$r.sq else summary(m)$r.squared

save_table(data.frame(
  model = names(distance_models),
  r_squared = round(sapply(distance_models, r_squared), 3),
  aic = round(sapply(distance_models, AIC)),
  ft_per_mph_tailwind = round(sapply(distance_models, function(m) coef(m)[["wind_out"]]), 2)
), "distance_model_comparison")

# Why the estimate moves: controls correlated with tailwind were inflating or hiding part of it.
correlations <- round(cor(wr[, c("wind_out", "launch_speed", "launch_angle", "temp")]), 2)
save_table(cbind(variable = rownames(correlations), as.data.frame(correlations)), "wrigley_fly_ball_correlations")

best <- distance_models[["Add hit direction"]]
same_ball <- data.frame(launch_speed = 100, launch_angle = 28, spray_angle = 0, temp = 70, wind_out = c(-15, 0, 15))
save_table(cbind(same_ball["wind_out"], predicted_distance_ft = round(predict(best, same_ball), 1)),
           "distance_same_ball_by_wind")

# ---- Wrigley vs other open-air parks ------------------------------------------------
parks <- lm(hit_distance_sc ~ wind_out * is_wrigley + launch_speed + launch_angle + I(launch_angle^2) + temp,
            data = outdoor)
park_effects <- function(m) {
  b <- coef(m)
  c(other = b[["wind_out"]], wrigley = b[["wind_out"]] + b[["wind_out:is_wrigley"]], gap = b[["wind_out:is_wrigley"]])
}
# Intervals resample whole games, since every ball in a game shares one wind reading.
parks_boot <- game_bootstrap(outdoor, function(d) park_effects(update(parks, data = d)))
parks_est <- park_effects(parks)
save_table(data.frame(
  parks = c("Other open-air parks", "Wrigley Field", "Wrigley minus others"),
  ft_per_mph_tailwind = round(parks_est, 2),
  low = round(apply(parks_boot, 2, quantile, 0.025), 2),
  high = round(apply(parks_boot, 2, quantile, 0.975), 2)
), "tailwind_effect_by_park")

# ---- Does tailwind matter more on some fly balls? -----------------------------------
by_angle <- gam(hit_distance_sc ~ s(launch_angle, by = wind_out) + te(launch_speed, launch_angle) + s(spray_angle) + temp,
                data = wr, method = "REML")
print(AIC(best, by_angle))

angles <- data.frame(launch_angle = seq(20, 65, 5), launch_speed = 100, spray_angle = 0, temp = 70)
angle_effects <- function(m) {
  as.numeric(predict(m, transform(angles, wind_out = 1)) - predict(m, transform(angles, wind_out = 0)))
}
# The model's own standard errors treat every ball as independent, which overstates certainty here.
# The band resamples whole games instead.
angle_boot <- game_bootstrap(wr, function(d) angle_effects(update(by_angle, data = d)))
effect <- angle_effects(by_angle)
angle_effect <- data.frame(launch_angle = angles$launch_angle, ft_per_mph = round(effect, 2),
                           low = round(apply(angle_boot, 2, quantile, 0.025), 2),
                           high = round(apply(angle_boot, 2, quantile, 0.975), 2))
save_table(angle_effect, "tailwind_effect_by_launch_angle")
angle_counts <- as.data.frame(table(launch_angle = cut(wr$launch_angle, c(-90, 25, 35, 45, 55, 60, 65, 90))))
save_table(setNames(angle_counts, c("launch_angle", "fly_balls")), "wrigley_fly_balls_by_launch_angle")

chart <- ggplot(angle_effect, aes(launch_angle, ft_per_mph)) +
  geom_hline(yintercept = 0, colour = COLOR_MUTED) +
  geom_ribbon(aes(ymin = low, ymax = high), fill = COLOR_WRIGLEY, alpha = 0.18) +
  geom_line(colour = COLOR_WRIGLEY, linewidth = 0.9) +
  labs(title = "Tailwind matters most on high fly balls",
       subtitle = "Feet of distance per mph of tailwind at Wrigley, for a 100 mph ball. 95% band from resampling games.",
       x = "Launch angle (degrees)", y = "Feet per mph of tailwind") +
  chart_theme()
save_chart(chart, "tailwind_effect_by_launch_angle")

# ---- Home runs at Wrigley ------------------------------------------------------------
wr_air <- subset(air, venue_name == "Wrigley Field")
hr_logistic <- glm(is_hr ~ wind_out + launch_speed + launch_angle + temp, data = wr_air, family = binomial)
hr_gam <- fit_hr_model(wr_air)
print(AIC(hr_logistic, hr_gam))
save_table(data.frame(
  model = c("Logistic regression", "Logistic GAM"),
  odds_ratio_per_mph = round(c(exp(coef(hr_logistic)[["wind_out"]]), exp(coef(hr_gam)[["wind_out"]])), 3),
  odds_ratio_15_mph = round(c(exp(15 * coef(hr_logistic)[["wind_out"]]), exp(15 * coef(hr_gam)[["wind_out"]])), 2)
), "hr_wind_odds_ratios")

balls <- data.frame(ball = c("Weak", "Borderline", "Crushed"),
                    launch_speed = c(90, 101, 110), launch_angle = c(30, 28, 28),
                    spray_angle = 0, temp = 70)
save_table(data.frame(
  ball = balls$ball, exit_velocity = balls$launch_speed, launch_angle = balls$launch_angle,
  headwind_15 = round(predict(hr_gam, transform(balls, wind_out = -15), type = "response"), 3),
  calm = round(predict(hr_gam, transform(balls, wind_out = 0), type = "response"), 3),
  tailwind_15 = round(predict(hr_gam, transform(balls, wind_out = 15), type = "response"), 3)
), "hr_chance_by_ball_and_wind")
