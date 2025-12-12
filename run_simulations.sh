#!/bin/bash

# Script to run multiple simulations with different configurations
# Usage: ./run_simulations.sh [--help]

# Show help if requested
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Script to run multiple simulations with different configurations"
    echo ""
    echo "Usage: ./run_simulations.sh"
    echo ""
    echo "The script runs all combinations of:"
    echo "  - Models (MODELS)"
    echo "  - Temperatures (TEMPERATURES)"
    echo "  - Graph Versions (GRAPH_VERSIONS)"
    echo "  - Input files (INPUT_FILES)"
    echo ""
    echo "To modify the values, edit the variables at the beginning of the script:"
    echo "  MODELS, TEMPERATURES, GRAPH_VERSIONS, INPUT_FILES"
    echo ""
    echo "Configuration options:"
    echo "  PROCESS_IMMEDIATELY - Process results immediately after each simulation (default: true)"
    echo "  SKIP_ANALYZER      - Skip analyzer execution (default: false)"
    echo "  PARALLEL_ANALYZER   - Run analyzer in background (default: false)"
    echo ""
    echo "The script automatically backs up config.yaml and restores it at the end."
    exit 0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/simulator/data/config.yaml"
INPUT_DIR="${SCRIPT_DIR}/simulator/data"
OUTPUT_DIR="${SCRIPT_DIR}/simulator/data/output"
BACKUP_CONFIG="${CONFIG_FILE}.backup"

# Arrays of values to test
# Add or modify values as needed
MODELS=("openai/gpt-5")
TEMPERATURES=(0.0 0.1 0.5)
GRAPH_VERSIONS=("v1" "v2")
INPUT_FILES=("input_const.json" "input_varia.json")

# Configuration options
PROCESS_IMMEDIATELY=true  # Process (rename + analyzer) immediately after each simulation
SKIP_ANALYZER=false       # Set to true to skip analyzer (only rename directories)
PARALLEL_ANALYZER=false   # Set to true to run analyzer in background (faster but less control)

# Function to manage sudo cache
manage_sudo_cache() {
    # Check if sudo is available
    if ! command -v sudo &> /dev/null; then
        echo -e "${YELLOW}Warning: sudo is not available. The script may fail if elevated privileges are needed.${NC}"
        return 1
    fi
    
    # Try to extend sudo cache (asks for password if needed)
    if sudo -v; then
        echo -e "${GREEN}✓ Sudo cache activated/extended${NC}"
        
        # Try to configure extended timeout (requires privileges)
        # This only works if the user has permission to modify sudoers
        # If not, the background process will keep the cache renewed
        echo -e "${BLUE}Attempting to extend sudo timeout...${NC}"
        sudo sh -c 'echo "Defaults timestamp_timeout=14400" >> /etc/sudoers.d/temp_simulator_timeout' 2>/dev/null && \
            echo -e "${GREEN}✓ Sudo timeout extended to 4 hours${NC}" || \
            echo -e "${YELLOW}⚠ Could not extend sudo timeout (normal if you don't have permissions).${NC}"
        echo -e "${BLUE}Using automatic cache renewal as fallback...${NC}"
        
        # Start a background process to renew the cache periodically
        # Renew every 1 minute to ensure it never expires
        # Sudo cache usually expires after 15 minutes (or configured time)
        (
            while true; do
                sleep 300  # Renew every 5 minutes (300 seconds) to ensure availability for hours
                sudo -v 2>/dev/null || break
            done
        ) &
        
        # Store the PID of the renewal process
        SUDO_CACHE_PID=$!
        echo -e "${GREEN}✓ Automatic renewal process started (renews every 1 minute)${NC}"
        return 0
    else
        echo -e "${RED}✗ Error activating sudo cache. You will need to enter the password for each command that requires sudo.${NC}"
        return 1
    fi
}

# Function to cleanup sudo renewal process
cleanup_sudo_cache() {
    if [ -n "${SUDO_CACHE_PID:-}" ]; then
        kill "$SUDO_CACHE_PID" 2>/dev/null || true
        echo -e "${BLUE}Sudo renewal process terminated${NC}"
    fi
    
    # Remove temporary sudoers configuration if it was created
    if [ -f "/etc/sudoers.d/temp_simulator_timeout" ]; then
        sudo rm -f /etc/sudoers.d/temp_simulator_timeout 2>/dev/null && \
            echo -e "${BLUE}Temporary sudo configuration removed${NC}" || true
    fi
}

# Function to backup config.yaml
backup_config() {
    if [ ! -f "$BACKUP_CONFIG" ]; then
        echo -e "${BLUE}Backing up original config.yaml...${NC}"
        cp "$CONFIG_FILE" "$BACKUP_CONFIG"
    fi
}

# Function to restore original config.yaml
restore_config() {
    if [ -f "$BACKUP_CONFIG" ]; then
        echo -e "${BLUE}Restoring original config.yaml...${NC}"
        cp "$BACKUP_CONFIG" "$CONFIG_FILE"
    fi
}

# Function to update a field in config.yaml
update_config_field() {
    local field_name="$1"
    local value="$2"
    
    case "$field_name" in
        "selected_model")
            # Line 26: selected_model
            sed -i "s|^\([[:space:]]*selected_model:\).*|\1 $value|" "$CONFIG_FILE"
            ;;
        "temperature")
            # Line 45: temperature within multi_agent.generation_config
            sed -i '/multi_agent:/,/^[[:space:]]*agents:/ {
                /generation_config:/,/^[[:space:]]*agents:/ {
                    s/^\([[:space:]]*temperature:\).*/\1 '"$value"'/
                }
            }' "$CONFIG_FILE"
            ;;
        "graph_version")
            # Line 43: graph_version within multi_agent
            sed -i '/multi_agent:/,/^[[:space:]]*generation_config:/ {
                s/^\([[:space:]]*graph_version:\).*/\1 '"$value"'/
            }' "$CONFIG_FILE"
            ;;
    esac
}

# Function to copy input file
copy_input_file() {
    local input_file="$1"
    local source_file="${INPUT_DIR}/${input_file}"
    local target_file="${INPUT_DIR}/input.json"
    
    if [ ! -f "$source_file" ]; then
        echo -e "${RED}Error: Input file not found: $source_file${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Copying $input_file to input.json...${NC}"
    cp "$source_file" "$target_file"
}

# Function to rename output directory
rename_output_directory() {
    local model="$1"
    local temperature="$2"
    local input_file="$3"
    local timestamp="$4"  # Specific timestamp directory to rename
    local graph_version="$5"  # Graph version (v1 or v2)
    
    # Extract model name (remove provider and replace / with -)
    local model_name=$(echo "$model" | sed 's|.*/||' | sed 's|/|-|g')
    
    # Determine input type
    local input_type=""
    if [[ "$input_file" == *"const"* ]]; then
        input_type="const"
    elif [[ "$input_file" == *"varia"* ]]; then
        input_type="varia"
    else
        input_type=$(basename "$input_file" .json)
    fi
    
    # Convert temperature to valid filename format (replace . with -)
    local temp_str=$(echo "$temperature" | sed 's/\./-/g')
    
    # Create directory name: modelName_inputType_temperature_graphVersion
    local new_dir_name="${model_name}_${input_type}_${temp_str}_${graph_version}"
    
    # Find the specific directory by timestamp
    if [ ! -d "$OUTPUT_DIR" ]; then
        echo -e "${YELLOW}Warning: Output directory not found: $OUTPUT_DIR${NC}"
        return 1
    fi
    
    # Use the provided timestamp to find the specific directory
    local target_dir="${OUTPUT_DIR}/${timestamp}"
    
    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
        echo -e "${YELLOW}Warning: Directory not found: $target_dir${NC}"
        return 1
    fi
    
    # Check if the new name already exists
    local new_dir_path="${OUTPUT_DIR}/${new_dir_name}"
    if [ -d "$new_dir_path" ]; then
        echo -e "${YELLOW}Warning: Directory $new_dir_name already exists. Adding numeric suffix...${NC}"
        local counter=1
        while [ -d "${new_dir_path}_${counter}" ]; do
            counter=$((counter + 1))
        done
        new_dir_name="${new_dir_name}_${counter}"
        new_dir_path="${OUTPUT_DIR}/${new_dir_name}"
    fi
    
    # Rename the directory
    echo -e "${BLUE}Renaming directory $timestamp to: $new_dir_name${NC}"
    if mv "$target_dir" "$new_dir_path" 2>/dev/null; then
        echo -e "${GREEN}✓ Directory renamed successfully: $new_dir_name${NC}"
        
        # Also rename corresponding directory in analyzer/output if it exists
        local analyzer_output_dir="${SCRIPT_DIR}/analyzer/output"
        if [ -d "$analyzer_output_dir" ]; then
            local analyzer_old_dir="${analyzer_output_dir}/${timestamp}"
            local analyzer_new_dir="${analyzer_output_dir}/${new_dir_name}"
            
            if [ -d "$analyzer_old_dir" ]; then
                echo -e "${BLUE}Renaming analyzer directory to: $new_dir_name${NC}"
                mv "$analyzer_old_dir" "$analyzer_new_dir" 2>/dev/null || true
            fi
        fi
        
        # Return the renamed directory name
        echo "$new_dir_name"
        return 0
    else
        echo -e "${RED}✗ Error renaming directory${NC}"
        return 1
    fi
}

# Function to save config.yaml and input.json in output directory
save_simulation_files() {
    local dir_name="$1"
    local input_file="$2"
    
    if [ -z "$dir_name" ]; then
        echo -e "${YELLOW}Warning: Directory name not provided${NC}"
        return 1
    fi
    
    local run_dir="${OUTPUT_DIR}/${dir_name}"
    
    if [ ! -d "$run_dir" ]; then
        echo -e "${YELLOW}Warning: Directory not found: $run_dir${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Saving config.yaml and input.json to output directory...${NC}"
    
    # Copy config.yaml
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${run_dir}/config.yaml"
        echo -e "${GREEN}✓ config.yaml saved${NC}"
    else
        echo -e "${YELLOW}Warning: config.yaml not found: $CONFIG_FILE${NC}"
    fi
    
    # Copy input.json (the file used in the simulation)
    local input_source="${INPUT_DIR}/${input_file}"
    if [ -f "$input_source" ]; then
        cp "$input_source" "${run_dir}/input.json"
        echo -e "${GREEN}✓ input.json saved (from $input_file)${NC}"
    else
        # Try to copy current input.json if original file doesn't exist
        local current_input="${INPUT_DIR}/input.json"
        if [ -f "$current_input" ]; then
            cp "$current_input" "${run_dir}/input.json"
            echo -e "${GREEN}✓ input.json saved${NC}"
        else
            echo -e "${YELLOW}Warning: input.json not found${NC}"
        fi
    fi
    
    return 0
}

# Function to run the analyzer
run_analyzer() {
    local dir_name="$1"
    
    if [ -z "$dir_name" ]; then
        echo -e "${YELLOW}Warning: Directory name not provided for analyzer${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Running analyzer for: $dir_name${NC}"
    cd "$SCRIPT_DIR"
    
    # Check if directory exists
    local run_dir="${OUTPUT_DIR}/${dir_name}"
    
    if [ ! -d "$run_dir" ]; then
        echo -e "${YELLOW}Warning: Directory not found: $run_dir${NC}"
        return 1
    fi
    
    # Execute command: cd analyzer && make generate-plots <directory_name>
    # The Makefile accepts directory name as argument or via RUN_DIR
    echo -e "${YELLOW}Executing: cd analyzer && make generate-plots $dir_name${NC}"
    echo -e "${BLUE}DEBUG: Run directory path: $run_dir${NC}"
    
    # Check if metrics.json exists (required by analyzer)
    if [ ! -f "${run_dir}/metrics.json" ]; then
        echo -e "${YELLOW}Warning: metrics.json not found in $run_dir${NC}"
        echo -e "${YELLOW}Skipping analyzer for this directory${NC}"
        return 1
    fi
    
    # Run analyzer with timeout to prevent hanging (30 minutes timeout)
    if timeout 1800 bash -c "cd '${SCRIPT_DIR}/analyzer' && make generate-plots '$dir_name'"; then
        echo -e "${GREEN}✓ Analyzer executed successfully for: $dir_name${NC}"
        return 0
    else
        local timeout_exit=$?
        if [ $timeout_exit -eq 124 ]; then
            echo -e "${RED}✗ Analyzer timed out after 30 minutes for: $dir_name${NC}"
        else
            echo -e "${RED}✗ Error running analyzer for: $dir_name (exit code: $timeout_exit)${NC}"
        fi
        return 1
    fi
}

# Function to get the most recent output directory timestamp
get_latest_output_dir() {
    if [ ! -d "$OUTPUT_DIR" ]; then
        return 1
    fi
    
    # Find the most recent directory (by modification date)
    local latest_dir=$(ls -td "$OUTPUT_DIR"/20* 2>/dev/null | head -1)
    
    if [ -z "$latest_dir" ] || [ ! -d "$latest_dir" ]; then
        return 1
    fi
    
    # Return just the directory name (timestamp)
    basename "$latest_dir"
}

# Function to run a simulation
run_simulation() {
    local model="$1"
    local temperature="$2"
    local input_file="$3"
    local graph_version="$4"
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Starting simulation with:${NC}"
    echo -e "  Model: $model"
    echo -e "  Temperature: $temperature"
    echo -e "  Graph Version: $graph_version"
    echo -e "  Input File: $input_file"
    echo -e "${GREEN}========================================${NC}\n"
    
    # Copy input file
    copy_input_file "$input_file" || return 1
    
    # Update config.yaml
    update_config_field "selected_model" "$model"
    update_config_field "temperature" "$temperature"
    update_config_field "graph_version" "$graph_version"
    
    # Get timestamp before simulation to identify the new directory
    local dir_before=$(get_latest_output_dir)
    
    # Run simulation - always use make setup-and-start (requires sudo)
    echo -e "${YELLOW}Executing: make setup-and-start (requires sudo)${NC}"
    cd "$SCRIPT_DIR"
    
    if make setup-and-start; then
        echo -e "${GREEN}✓ Simulation completed successfully!${NC}"
        
        # Wait a bit to ensure directory was created
        sleep 2
        
        # Get the new directory timestamp (should be different from before)
        local dir_after=$(get_latest_output_dir)
        
        if [ -n "$dir_after" ] && [ "$dir_after" != "$dir_before" ]; then
            # Return the timestamp directory name for later renaming
            echo "$dir_after"
            return 0
        else
            echo -e "${YELLOW}Warning: Could not identify output directory for this simulation${NC}"
            return 0
        fi
    else
        echo -e "${RED}✗ Error running simulation${NC}"
        return 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}=== Multiple Simulations Execution Script ===${NC}\n"
    
    # Manage sudo cache for automation
    echo -e "${BLUE}Configuring sudo authentication...${NC}"
    echo -e "${YELLOW}Note: You will need to enter your sudo password once at the beginning.${NC}"
    echo -e "${YELLOW}The cache will be maintained throughout the script execution.${NC}\n"
    manage_sudo_cache
    
    # Calculate total simulations
    local total_combinations=$((${#MODELS[@]} * ${#TEMPERATURES[@]} * ${#GRAPH_VERSIONS[@]} * ${#INPUT_FILES[@]}))
    echo -e "${YELLOW}Total simulations to run: $total_combinations${NC}\n"
    
    # Backup config.yaml
    backup_config
    
    # Simulation counters
    local total_simulations=0
    local successful_simulations=0
    local failed_simulations=0
    local failed_simulations_list=()  # Array to store failed simulation details
    local successful_simulations_data=()  # Array to store successful simulation data: "timestamp|model|temperature|graph_version|input_file"
    
    # Run all combinations
    for model in "${MODELS[@]}"; do
        for temperature in "${TEMPERATURES[@]}"; do
            for graph_version in "${GRAPH_VERSIONS[@]}"; do
                for input_file in "${INPUT_FILES[@]}"; do
                    total_simulations=$((total_simulations + 1))
                    echo -e "${BLUE}[$total_simulations/$total_combinations]${NC}"
                    
                    # Run simulation and capture timestamp while displaying output in real-time
                    # Use tee to display output and capture the last line (timestamp) simultaneously
                    local temp_result_file=$(mktemp)
                    local result
                    local exit_code
                    
                    # Run simulation with tee to display output and capture it
                    # Use set -o pipefail to capture the exit code of run_simulation, not tee
                    set -o pipefail
                    run_simulation "$model" "$temperature" "$input_file" "$graph_version" 2>&1 | tee "$temp_result_file"
                    exit_code=$?
                    set +o pipefail
                    
                    # Extract the timestamp from the output
                    # Look for the pattern in the last few lines (timestamp format: YYYYMMDD_HHMMSS)
                    result=$(grep -E '^[0-9]{8}_[0-9]{6}$' "$temp_result_file" 2>/dev/null | tail -1 || echo "")
                    if [ -z "$result" ]; then
                        # Fallback: try to get the last line that looks like a timestamp
                        result=$(tail -1 "$temp_result_file" 2>/dev/null | grep -oE '[0-9]{8}_[0-9]{6}' | head -1 || echo "")
                    fi
                    rm -f "$temp_result_file"
                    
                    echo -e "${BLUE}DEBUG: Extracted timestamp: '$result'${NC}"
                    echo -e "${BLUE}DEBUG: Exit code: $exit_code${NC}"
                    
                    if [ $exit_code -eq 0 ] && [ -n "$result" ] && [[ "$result" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
                        successful_simulations=$((successful_simulations + 1))
                        
                        # Process immediately if enabled
                        if [ "$PROCESS_IMMEDIATELY" = true ]; then
                            echo -e "\n${BLUE}Processing simulation results immediately...${NC}"
                            
                            # Wait a bit more to ensure directory is fully created and accessible
                            echo -e "${BLUE}Waiting for directory to be ready...${NC}"
                            local wait_count=0
                            while [ $wait_count -lt 10 ] && [ ! -d "${OUTPUT_DIR}/${result}" ]; do
                                sleep 1
                                wait_count=$((wait_count + 1))
                            done
                            
                            if [ ! -d "${OUTPUT_DIR}/${result}" ]; then
                                echo -e "${RED}✗ Error: Directory ${OUTPUT_DIR}/${result} not found after waiting${NC}"
                                echo -e "${YELLOW}Continuing with next simulation...${NC}"
                            else
                                echo -e "${GREEN}✓ Directory found: ${OUTPUT_DIR}/${result}${NC}"
                                
                                # Rename output directory
                                local renamed_dir=$(rename_output_directory "$model" "$temperature" "$input_file" "$result" "$graph_version")
                                
                                if [ -n "$renamed_dir" ] && [ "$renamed_dir" != "" ]; then
                                    echo -e "${GREEN}✓ Directory renamed to: $renamed_dir${NC}"
                                    
                                    # Save config.yaml and input.json in output directory
                                    save_simulation_files "$renamed_dir" "$input_file"
                                    
                                    # Run analyzer (or skip if configured)
                                    if [ "$SKIP_ANALYZER" = false ]; then
                                        if [ "$PARALLEL_ANALYZER" = true ]; then
                                            echo -e "${BLUE}Running analyzer in background for: $renamed_dir${NC}"
                                            run_analyzer "$renamed_dir" &
                                        else
                                            echo -e "${BLUE}Running analyzer synchronously for: $renamed_dir${NC}"
                                            run_analyzer "$renamed_dir"
                                        fi
                                    else
                                        echo -e "${YELLOW}Skipping analyzer (SKIP_ANALYZER=true)${NC}"
                                    fi
                                else
                                    echo -e "${YELLOW}Warning: Failed to rename directory or got empty result${NC}"
                                    echo -e "${YELLOW}Continuing with next simulation...${NC}"
                                fi
                            fi
                        else
                            # Store for later processing
                            successful_simulations_data+=("$result|$model|$temperature|$graph_version|$input_file")
                        fi
                    else
                        failed_simulations=$((failed_simulations + 1))
                        # Store failed simulation details
                        failed_simulations_list+=("Model: $model | Temperature: $temperature | Graph Version: $graph_version | Input: $input_file")
                        echo -e "${YELLOW}Continuing with next simulation...${NC}"
                    fi
                    
                    # Small pause between simulations
                    sleep 120
                done
            done
        done
    done
    
    # Process remaining simulations if PROCESS_IMMEDIATELY was false
    if [ "$PROCESS_IMMEDIATELY" = false ] && [ ${#successful_simulations_data[@]} -gt 0 ]; then
        echo -e "\n${BLUE}========================================${NC}"
        echo -e "${BLUE}Processing remaining simulations...${NC}"
        echo -e "${BLUE}========================================${NC}\n"
        
        local processed_count=0
        for sim_data in "${successful_simulations_data[@]}"; do
            IFS='|' read -r timestamp model temperature graph_version input_file <<< "$sim_data"
            processed_count=$((processed_count + 1))
            
            echo -e "${BLUE}[$processed_count/${#successful_simulations_data[@]}] Processing: $timestamp${NC}"
            
            # Rename output directory
            local renamed_dir=$(rename_output_directory "$model" "$temperature" "$input_file" "$timestamp" "$graph_version")
            
            if [ -n "$renamed_dir" ]; then
                # Save config.yaml and input.json in output directory
                save_simulation_files "$renamed_dir" "$input_file"
                
                # Run analyzer (or skip if configured)
                if [ "$SKIP_ANALYZER" = false ]; then
                    if [ "$PARALLEL_ANALYZER" = true ]; then
                        echo -e "${BLUE}Running analyzer in background for: $renamed_dir${NC}"
                        run_analyzer "$renamed_dir" &
                    else
                        run_analyzer "$renamed_dir"
                    fi
                else
                    echo -e "${YELLOW}Skipping analyzer (SKIP_ANALYZER=true)${NC}"
                fi
            fi
        done
        
        # Wait for all background analyzer processes to complete if using parallel mode
        if [ "$PARALLEL_ANALYZER" = true ]; then
            echo -e "${BLUE}Waiting for all analyzer processes to complete...${NC}"
            wait
            echo -e "${GREEN}✓ All analyzer processes completed${NC}"
        fi
    elif [ "$PROCESS_IMMEDIATELY" = true ] && [ "$PARALLEL_ANALYZER" = true ]; then
        # Wait for any background analyzer processes to complete
        echo -e "\n${BLUE}Waiting for all background analyzer processes to complete...${NC}"
        wait
        echo -e "${GREEN}✓ All analyzer processes completed${NC}"
    fi
    
    # Cleanup sudo renewal process
    cleanup_sudo_cache
    
    # Restore original config.yaml
    restore_config
    
    # Final summary
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Simulation Summary:${NC}"
    echo -e "  Total: $total_simulations"
    echo -e "${GREEN}  Successful: $successful_simulations${NC}"
    echo -e "${RED}  Failed: $failed_simulations${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # Display failed simulations details if any
    if [ ${#failed_simulations_list[@]} -gt 0 ]; then
        echo -e "\n${RED}Failed Simulations Details:${NC}"
        for i in "${!failed_simulations_list[@]}"; do
            echo -e "${RED}  $((i + 1)). ${failed_simulations_list[$i]}${NC}"
        done
        echo ""
    fi
}

# Trap to ensure cleanup even on error
cleanup_on_exit() {
    cleanup_sudo_cache
    restore_config
}
trap cleanup_on_exit EXIT INT TERM

# Execute main function
main
