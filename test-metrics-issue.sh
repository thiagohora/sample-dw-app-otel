#!/bin/bash

# Script to test and demonstrate the HTTP metrics collection issue
# when enableVirtualThreads: false in Dropwizard 5

set -e

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
COLLECTOR_METRICS_URL="${COLLECTOR_METRICS_URL:-http://localhost:8889}"
APP_URL="${APP_URL:-http://localhost:8080}"
REQUESTS=${REQUESTS:-50}

echo "=========================================="
echo "Testing HTTP Metrics Collection Issue"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  - enableVirtualThreads: false (issue reproduction mode)"
echo "  - Prometheus: ${PROMETHEUS_URL}"
echo "  - Collector Metrics: ${COLLECTOR_METRICS_URL}"
echo "  - App: ${APP_URL}"
echo ""

# Function to check if a service is available
check_service() {
    local url=$1
    local name=$2
    if curl -s -f "${url}" > /dev/null 2>&1; then
        echo "✓ ${name} is available"
        return 0
    else
        echo "✗ ${name} is not available at ${url}"
        return 1
    fi
}

# Check services
echo "Checking services..."
check_service "${PROMETHEUS_URL}/api/v1/query?query=up" "Prometheus" || exit 1
check_service "${COLLECTOR_METRICS_URL}/metrics" "OTel Collector" || exit 1
check_service "${APP_URL}/ping" "Dropwizard App" || exit 1
echo ""

# Generate traffic
echo "Generating ${REQUESTS} requests to create metrics..."
for i in $(seq 1 ${REQUESTS}); do
    curl -s "${APP_URL}/ping" > /dev/null
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Sent ${i} requests..."
    fi
    # Add some latency requests
    if [ $((i % 5)) -eq 0 ]; then
        curl -s "${APP_URL}/latency?ms=$((RANDOM % 500 + 100))" > /dev/null
    fi
done
echo "✓ Traffic generation complete"
echo ""

# Wait for metrics to be exported (OpenTelemetry exports every 60 seconds)
echo "Waiting 65 seconds for metrics to be exported..."
sleep 65
echo ""

# Function to query Prometheus
query_prometheus() {
    local query=$1
    local name=$2
    local response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=$(echo "${query}" | sed 's/ /%20/g')" 2>/dev/null)
    local result="0"
    if command -v jq >/dev/null 2>&1; then
        result=$(echo "${response}" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    else
        # Fallback if jq is not available - count "metric" occurrences
        result=$(echo "${response}" | grep -c '"metric"' 2>/dev/null || echo "0")
    fi
    echo "  ${name}: ${result} series found" >&2
    if [ "${result}" -gt 0 ] && command -v jq >/dev/null 2>&1; then
        # Show sample metric name
        local sample=$(echo "${response}" | jq -r '.data.result[0].metric.__name__ // empty' 2>/dev/null | head -1)
        if [ -n "${sample}" ] && [ "${sample}" != "null" ]; then
            echo "    Sample metric: ${sample}" >&2
        fi
    fi
    echo "${result}" | tr -d '\n'
}

# Function to check for a metric in collector
check_collector_metric() {
    local metric=$1
    local name=$2
    local count=$(curl -s "${COLLECTOR_METRICS_URL}/metrics" 2>/dev/null | grep -c "^${metric}" || echo "0")
    echo "  ${name}: ${count} series found" >&2
    echo "${count}" | tr -d '\n'
}

echo "=========================================="
echo "Checking OpenTelemetry HTTP Metrics"
echo "=========================================="
echo ""
echo "These metrics come from OpenTelemetry Java Agent instrumentation:"
echo ""

# Check OpenTelemetry HTTP metrics
echo "Checking for OpenTelemetry HTTP server metrics..."
otel_http_duration=$(query_prometheus "http_server_request_duration_seconds_count" "http_server_request_duration_seconds_count")
otel_http_duration_bucket=$(query_prometheus "http_server_request_duration_seconds_bucket" "http_server_request_duration_seconds_bucket")
otel_http_active=$(query_prometheus "http_server_active_requests" "http_server_active_requests")

echo ""
echo "OpenTelemetry Metrics Summary:"
# Convert to integers for comparison
otel_http_duration=${otel_http_duration:-0}
otel_http_duration_bucket=${otel_http_duration_bucket:-0}
if [ "${otel_http_duration}" -gt 0 ] || [ "${otel_http_duration_bucket}" -gt 0 ]; then
    echo "  ✓ OpenTelemetry HTTP metrics ARE present"
    echo "    - This is expected - OpenTelemetry agent instrumentation works"
    echo "    - Duration count: ${otel_http_duration} series"
    echo "    - Duration buckets: ${otel_http_duration_bucket} series"
else
    echo "  ✗ OpenTelemetry HTTP metrics are NOT present"
    echo "    - This indicates a setup issue"
    echo "    - Check that the app is running and metrics are being exported"
fi
echo ""

echo "=========================================="
echo "Checking Dropwizard Built-in Metrics"
echo "=========================================="
echo ""
echo "These metrics come from Dropwizard's built-in instrumentation:"
echo ""

# Check Dropwizard metrics (these are the ones that should be missing)
echo "Checking for Dropwizard built-in metrics..."
dropwizard_requests=$(query_prometheus 'io_dropwizard_jetty_MutableServletContextHandler_requests_total' "io.dropwizard.jetty.MutableServletContextHandler.requests")
dropwizard_requests_1m=$(query_prometheus 'io_dropwizard_jetty_MutableServletContextHandler_requests_1m' "io.dropwizard.jetty.MutableServletContextHandler.requests (1m rate)")

# Also check for other Dropwizard metrics that might be present
dropwizard_any=$(query_prometheus '{__name__=~"io_dropwizard.*"}' "Any Dropwizard metrics (io.dropwizard.*)")

# Also check collector metrics endpoint
echo ""
echo "Checking collector metrics endpoint for Dropwizard metrics:"
dropwizard_collector=$(check_collector_metric "io_dropwizard" "Dropwizard metrics (io.dropwizard.*)")

echo ""
echo "Dropwizard Metrics Summary:"
# Convert to integers for comparison
dropwizard_requests=${dropwizard_requests:-0}
dropwizard_any=${dropwizard_any:-0}
if [ "${dropwizard_requests}" -gt 0 ] || [ "${dropwizard_any}" -gt 0 ]; then
    echo "  ✓ Dropwizard built-in metrics ARE present"
    if [ "${dropwizard_requests}" -gt 0 ]; then
        echo "    - Found: io.dropwizard.jetty.MutableServletContextHandler.requests"
    fi
    if [ "${dropwizard_any}" -gt 0 ]; then
        echo "    - Found ${dropwizard_any} Dropwizard metric series"
    fi
    echo "    - This means the issue is NOT reproduced (virtual threads might be enabled?)"
else
    echo "  ✗ Dropwizard built-in metrics are NOT present"
    echo "    - This is the ISSUE: Dropwizard metrics missing when enableVirtualThreads: false"
    echo "    - Expected metric: io.dropwizard.jetty.MutableServletContextHandler.requests"
    echo "    - Expected: Request duration timers, request/response size meters"
fi
echo ""

echo "=========================================="
echo "Issue Summary"
echo "=========================================="
echo ""
if [ "${dropwizard_requests}" -eq 0 ] && [ "${dropwizard_any}" -eq 0 ]; then
    echo "✓ ISSUE REPRODUCED:"
    echo "  When enableVirtualThreads: false:"
    echo "    ✓ OpenTelemetry HTTP metrics: Present (from OTel Java agent)"
    echo "    ✗ Dropwizard built-in metrics: Missing (from Dropwizard instrumentation)"
    echo ""
    echo "  The issue is that Dropwizard's own metrics are not being collected"
    echo "  when virtual threads are disabled, even though OpenTelemetry metrics work."
    echo ""
    echo "  Expected Dropwizard metrics that should be present:"
    echo "    - io.dropwizard.jetty.MutableServletContextHandler.requests"
    echo "    - Request duration timers"
    echo "    - Request/response size meters"
    echo "    - Per-endpoint and per-status-code metrics"
    echo ""
    echo "  To verify the fix, enable virtual threads:"
    echo "    Set ENABLE_VIRTUAL_THREADS=true in docker-compose.yml"
else
    echo "⚠ ISSUE NOT REPRODUCED:"
    echo "  Dropwizard metrics ARE present. This could mean:"
    echo "    - Virtual threads are enabled (ENABLE_VIRTUAL_THREADS=true)"
    echo "    - The issue has been fixed"
    echo "    - Metrics are being collected through a different mechanism"
    echo ""
fi
echo ""

# Show sample queries
echo "=========================================="
echo "Sample Prometheus Queries"
echo "=========================================="
echo ""
echo "OpenTelemetry HTTP metrics:"
echo "  http_server_request_duration_seconds_count"
echo "  http_server_request_duration_seconds_bucket"
echo "  rate(http_server_request_duration_seconds_count[5m])"
echo ""
echo "Dropwizard metrics (should be present but are missing):"
echo "  io_dropwizard_jetty_MutableServletContextHandler_requests_total"
echo "  io_dropwizard_jetty_MutableServletContextHandler_requests_1m"
echo ""
echo "Query in Prometheus UI: ${PROMETHEUS_URL}"
echo ""
echo "Direct metric inspection:"
echo "  Collector metrics: ${COLLECTOR_METRICS_URL}/metrics"
echo "  Prometheus query API: ${PROMETHEUS_URL}/api/v1/query"
echo ""
echo "To see all HTTP metrics in Prometheus, try:"
echo "  curl -s '${PROMETHEUS_URL}/api/v1/query?query=http_server_request_duration_seconds_count' | jq"
echo ""
echo "To see all Dropwizard metrics (should be empty):"
echo "  curl -s '${PROMETHEUS_URL}/api/v1/query?query={__name__=~\"io_dropwizard.*\"}' | jq"
echo ""

