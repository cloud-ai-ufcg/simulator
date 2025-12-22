#!/usr/bin/env Rscript
# Install required R packages in user library

cat("Installing required R packages...\n\n")

# Create user library directory if it doesn't exist
user_lib <- Sys.getenv("R_LIBS_USER")
if (!dir.exists(user_lib)) {
  dir.create(user_lib, recursive = TRUE)
  cat("Created user library directory:", user_lib, "\n")
}

# List of required packages
packages <- c("dplyr", "readr")

# Install packages if not already installed
for (pkg in packages) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("Installing package:", pkg, "\n")
    install.packages(pkg, repos = "https://cloud.r-project.org", lib = user_lib, quiet = FALSE)
  } else {
    cat("Package already installed:", pkg, "\n")
  }
}

cat("\n✅ All packages installed successfully!\n")
