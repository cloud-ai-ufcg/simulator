#!/bin/bash

# Ensure HOME is set, using USERPROFILE as a fallback (useful for WSL/Git Bash).
export HOME="${HOME:-$USERPROFILE}"

echo "HOME environment variable is set to: $HOME"

echo "Starting the simulator..."
go run main.go 