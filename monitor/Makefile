.PHONY: run port-forward clean stop

all: port-forward run

# Start port forwarding in background
port-forward:
	@echo "Starting port forwarding..."
	@make clean || true  # Clean up any existing processes first
	@./port-foward.sh &
	@sleep 5  # Give some time for port forwarding to establish

# Build and run the monitor
run:
	@echo "Building and running monitor..."
	@go build -o monitor ./cmd/main.go
	@trap 'make stop' INT TERM; ./monitor

# Clean up processes
clean:
	@echo "Cleaning up..."
	@pkill -f "port-foward.sh" || true
	@pkill -f "kubectl.*port-forward" || true
	@rm -f monitor
	@sleep 2  # Give time for ports to be released

# Stop all processes
stop: clean
	@echo "Stopped all processes"