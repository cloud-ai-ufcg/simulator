.PHONY: run-all create-plot generate-plot install-deps

# Install R package dependencies
install-deps:
	Rscript -e 'install.packages(c("ggplot2", "dplyr", "readr", "tidyr"), repos="https://cran.r-project.org")'

# Generate the cumulative CPU plot and then generate the final plot with all metrics
run-all: create-plot generate-plot

# Generate the cumulative CPU plot from the input JSON
create-plot:
	Rscript create_plot_for_input.R

# Generate the final plot with all metrics using the cumulative CPU plot as input
generate-plot:
	Rscript generate_plot.R
