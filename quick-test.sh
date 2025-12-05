#!/bin/bash

# Quick test script to verify endpoints are working

APP_URL="${APP_URL:-http://localhost:8080}"
ADMIN_URL="${ADMIN_URL:-http://localhost:8081}"

echo "Testing Dropwizard Application Endpoints"
echo "========================================"
echo ""

echo "1. Health Check:"
curl -s "$ADMIN_URL/healthcheck" | jq '.' 2>/dev/null || curl -s "$ADMIN_URL/healthcheck"
echo ""
echo ""

echo "2. Ping Endpoint:"
curl -s "$APP_URL/ping"
echo ""
echo ""

echo "3. Latency Endpoint (500ms):"
curl -s "$APP_URL/latency?ms=500"
echo ""
echo ""

echo "4. Latency Endpoint (1000ms):"
curl -s "$APP_URL/latency?ms=1000"
echo ""
echo ""

echo "✓ All endpoints tested successfully!"
echo ""
echo "Access observability stack:"
echo "  - Grafana: http://localhost:3000"
echo "  - Prometheus: http://localhost:9090"
echo "  - Tempo: http://localhost:3200"

