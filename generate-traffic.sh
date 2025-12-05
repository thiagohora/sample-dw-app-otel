#!/bin/bash

# Script to generate traffic to the Dropwizard application
# This helps test the HTTP metrics collection issue

set -e

APP_URL="${APP_URL:-http://localhost:8080}"
ADMIN_URL="${ADMIN_URL:-http://localhost:8081}"
REQUESTS="${REQUESTS:-100}"
CONCURRENT="${CONCURRENT:-5}"

echo "Generating traffic to $APP_URL"
echo "Requests: $REQUESTS"
echo "Concurrent: $CONCURRENT"
echo ""

# Function to make a request
make_request() {
    local endpoint=$1
    local response=$(curl -s -w "\n%{http_code}" "$endpoint" 2>/dev/null || echo -e "\n000")
    local body=$(echo "$response" | head -n -1)
    local status=$(echo "$response" | tail -n 1)
    
    if [ "$status" = "200" ]; then
        echo "✓ $endpoint -> $body"
    else
        echo "✗ $endpoint -> HTTP $status"
    fi
}

# Test basic connectivity
echo "Testing connectivity..."
if ! curl -s -f "$ADMIN_URL/healthcheck" > /dev/null; then
    echo "ERROR: Application is not responding at $ADMIN_URL"
    exit 1
fi
echo "✓ Application is running"
echo ""

# Generate traffic to ping endpoint
echo "Generating $REQUESTS requests to /ping..."
for i in $(seq 1 $REQUESTS); do
    make_request "$APP_URL/ping" > /dev/null &
    
    # Limit concurrent requests
    if (( i % $CONCURRENT == 0 )); then
        wait
    fi
done
wait
echo "✓ Completed $REQUESTS requests to /ping"
echo ""

# Generate traffic to latency endpoint with random delays
echo "Generating $REQUESTS requests to /latency with random delays..."
for i in $(seq 1 $REQUESTS); do
    # Random delay between 100ms and 2000ms
    delay=$((RANDOM % 1900 + 100))
    make_request "$APP_URL/latency?ms=$delay" > /dev/null &
    
    # Limit concurrent requests
    if (( i % $CONCURRENT == 0 )); then
        wait
    fi
done
wait
echo "✓ Completed $REQUESTS requests to /latency"
echo ""

echo "Traffic generation complete!"
echo ""
echo "Check metrics at:"
echo "  - Prometheus: http://localhost:9090"
echo "  - Grafana: http://localhost:3000"
echo ""
echo "Query examples in Prometheus:"
echo "  - http_server_request_duration_count"
echo "  - rate(http_server_request_duration_count[5m])"

