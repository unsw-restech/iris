#!/usr/bin/env Rscript
# ARES - Statistical modelling in R
#
# Fits and compares linear models, writing plain-text tables and a small
# JSON summary. Base R only - no CRAN packages - so Katana's `r` module is
# enough on its own and there is nothing to install into your home directory.
#
# The default dataset is `swiss`, which ships with R: socioeconomic
# indicators and fertility for 47 French-speaking provinces of Switzerland
# in 1888. It means the workflow runs with no input data.
#
# Usage:
#   Rscript fit_models.R --outdir OUT [--data swiss] [--response Fertility]

# ---- arguments -------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(name, default = NULL) {
  hit <- which(args == paste0("--", name))
  if (length(hit) == 1L && length(args) > hit) return(args[hit + 1L])
  if (is.null(default)) {
    stop(sprintf("required argument --%s is missing", name), call. = FALSE)
  }
  default
}

outdir   <- get_arg("outdir")
data_name <- get_arg("data", "swiss")
response <- get_arg("response", "Fertility")
csv_path <- get_arg("csv", "")

dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

log_path <- file.path(outdir, "analysis_log.txt")
log_con <- file(log_path, open = "wt")
say <- function(...) {
  line <- paste0(...)
  cat(line, "\n", sep = "")
  writeLines(line, log_con)
  flush(log_con)
}

say("========================================")
say("  ARES - Statistical modelling in R")
say("========================================")
say("")
say("R version : ", R.version.string)
say("Platform  : ", R.version$platform)
say("Output dir: ", outdir)
say("")

# ---- data ------------------------------------------------------------------

if (nzchar(csv_path)) {
  say("Reading: ", csv_path)
  dat <- read.csv(csv_path, stringsAsFactors = FALSE)
  data_name <- basename(csv_path)
} else {
  say("Dataset: ", data_name, " (built into R - no input data required)")
  dat <- get(data_name, envir = as.environment("package:datasets"))
}

dat <- as.data.frame(dat)
numeric_cols <- vapply(dat, is.numeric, logical(1))
dat <- dat[, numeric_cols, drop = FALSE]

if (!response %in% names(dat)) {
  stop(sprintf("response '%s' is not a numeric column in %s. Available: %s",
               response, data_name, paste(names(dat), collapse = ", ")),
       call. = FALSE)
}

say("Observations: ", nrow(dat))
say("Variables   : ", ncol(dat), " (", paste(names(dat), collapse = ", "), ")")
say("Response    : ", response)
say("")

# ---- models ----------------------------------------------------------------

predictors <- setdiff(names(dat), response)
full_formula <- as.formula(paste(response, "~", paste(predictors, collapse = " + ")))

# A deliberately reduced model, for a like-for-like comparison against the
# full one. Takes the two predictors most correlated with the response.
correlations <- sapply(predictors, function(p) cor(dat[[p]], dat[[response]]))
top_two <- names(sort(abs(correlations), decreasing = TRUE))[1:min(2, length(predictors))]
reduced_formula <- as.formula(paste(response, "~", paste(top_two, collapse = " + ")))

say("Full model   : ", deparse(full_formula))
say("Reduced model: ", deparse(reduced_formula))
say("")

full_fit <- lm(full_formula, data = dat)
reduced_fit <- lm(reduced_formula, data = dat)

full_summary <- summary(full_fit)

say("Full model R-squared     : ", sprintf("%.4f", full_summary$r.squared))
say("Full model adj R-squared : ", sprintf("%.4f", full_summary$adj.r.squared))
say("Full model AIC           : ", sprintf("%.2f", AIC(full_fit)))
say("Reduced model AIC        : ", sprintf("%.2f", AIC(reduced_fit)))
say("")

comparison <- anova(reduced_fit, full_fit)
p_value <- comparison[["Pr(>F)"]][2]
say("Reduced vs full, F-test p = ", format.pval(p_value, digits = 4))
say(if (!is.na(p_value) && p_value < 0.05)
      "  -> the extra predictors improve fit at the 5% level."
    else
      "  -> no significant improvement from the extra predictors.")
say("")

# ---- outputs ---------------------------------------------------------------

writeLines(
  c("Full model", "==========", "",
    capture.output(full_summary), "",
    "Reduced model", "=============", "",
    capture.output(summary(reduced_fit))),
  file.path(outdir, "model_summary.txt")
)

writeLines(
  c("Model comparison (analysis of variance)",
    "=======================================", "",
    capture.output(comparison), "",
    sprintf("AIC full    : %.4f", AIC(full_fit)),
    sprintf("AIC reduced : %.4f", AIC(reduced_fit))),
  file.path(outdir, "model_comparison.txt")
)

writeLines(
  c("Correlation matrix", "==================", "",
    capture.output(round(cor(dat), 3))),
  file.path(outdir, "correlations.txt")
)

coefs <- as.data.frame(full_summary$coefficients)
names(coefs) <- c("estimate", "std_error", "t_value", "p_value")
coefs$term <- rownames(coefs)
coefs <- coefs[, c("term", "estimate", "std_error", "t_value", "p_value")]
write.csv(coefs, file.path(outdir, "coefficients.csv"), row.names = FALSE)

# Small JSON summary, written without a package so no CRAN install is needed.
json <- sprintf(
  paste0('{\n',
         '  "workflow": "ares-r-statistics",\n',
         '  "version": "1.0.0",\n',
         '  "status": "success",\n',
         '  "r_version": "%s",\n',
         '  "dataset": "%s",\n',
         '  "response": "%s",\n',
         '  "observations": %d,\n',
         '  "predictors": %d,\n',
         '  "r_squared": %.6f,\n',
         '  "adj_r_squared": %.6f,\n',
         '  "aic_full": %.4f,\n',
         '  "aic_reduced": %.4f,\n',
         '  "comparison_p_value": %s\n',
         '}\n'),
  R.version.string, data_name, response, nrow(dat), length(predictors),
  full_summary$r.squared, full_summary$adj.r.squared,
  AIC(full_fit), AIC(reduced_fit),
  if (is.na(p_value)) "null" else sprintf("%.6g", p_value)
)
cat(json, file = file.path(outdir, "metrics.json"))

say("Wrote:")
for (f in c("model_summary.txt", "model_comparison.txt", "correlations.txt",
            "coefficients.csv", "metrics.json", "analysis_log.txt")) {
  say("  ", file.path(outdir, f))
}
say("")
say("========================================")
say("  Complete")
say("========================================")

close(log_con)
