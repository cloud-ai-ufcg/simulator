# Set the HOME environment variable to the current user's profile directory, crucial for the broker.
$env:HOME = $env:USERPROFILE

# Display a message indicating that HOME has been set (optional, for feedback)
Write-Host "HOME environment variable set to: $env:HOME"

# Execute the main Go program for the simulator
Write-Host "Starting the simulator..."
go run main.go 