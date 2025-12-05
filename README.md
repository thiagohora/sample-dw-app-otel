# Sample Dropwizard App with OpenTelemetry

This project reproduces the issue described in [opentelemetry-java-instrumentation#15511](https://github.com/open-telemetry/opentelemetry-java-instrumentation/issues/15511).

## Issue Description

After upgrading to Dropwizard 5, HTTP server metrics are not being collected or exposed correctly when `enableVirtualThreads: false`. The application starts without errors, but expected HTTP-related metrics (e.g., request counts, latency timers, request body size) are missing or incomplete.

## Prerequisites

### For Local Development
- JDK 21 or higher
- Maven 3.6+
- OpenTelemetry Java Agent (download from [releases](https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases))
- Optional: OTLP collector or Prometheus for metrics collection

### For Docker (Recommended)
- Docker and Docker Compose

## Quick Start with Docker Compose (Recommended)

The easiest way to run the application with full observability stack is using Docker Compose:

```bash
# Build and start all services
docker-compose up --build

# Or run in detached mode
docker-compose up -d --build
```

This will start:
- **Dropwizard Application** on `http://localhost:8080` (app) and `http://localhost:8081` (admin)
- **Grafana** on `http://localhost:3000` (auto-login enabled)
- **Prometheus** on `http://localhost:9090`
- **Tempo** on `http://localhost:3200`
- **Loki** on `http://localhost:3100`
- **OpenTelemetry Collector** (internal, receives telemetry from the app)

### Accessing the Observability Stack

1. **Grafana**: http://localhost:3000
   - Pre-configured with Prometheus, Tempo, and Loki datasources
   - Explore metrics, traces, and logs

2. **Prometheus**: http://localhost:9090
   - Query metrics directly
   - Check if HTTP server metrics are being collected

3. **Application Endpoints**:
   - Health check: `curl http://localhost:8081/healthcheck`
   - Ping: `curl http://localhost:8080/ping`
   - Latency simulation: `curl "http://localhost:8080/latency?ms=500"`

### Generate Test Traffic

**Option 1: Use the traffic generation script (recommended)**

```bash
# Generate 100 requests (default)
./generate-traffic.sh

# Customize number of requests and concurrency
REQUESTS=500 CONCURRENT=10 ./generate-traffic.sh
```

**Option 2: Quick test script**

```bash
# Test all endpoints once
./quick-test.sh
```

**Option 3: Manual testing**

```bash
# Generate traffic manually
for i in {1..100}; do
  curl http://localhost:8080/ping
  curl "http://localhost:8080/latency?ms=$((RANDOM % 1000))"
  sleep 0.1
done
```

### View Metrics in Grafana

1. Open Grafana at http://localhost:3000
2. Go to **Explore** → Select **Prometheus** datasource
3. Try queries like:
   - `http_server_request_duration_count` - Request count
   - `http_server_request_duration_sum` - Total request duration
   - `rate(http_server_request_duration_count[5m])` - Request rate

### View Traces in Grafana

1. Go to **Explore** → Select **Tempo** datasource
2. Search for traces by service name: `dropwizard-app`
3. Click on a trace to see the full span details

### Stop Services

```bash
docker-compose down

# Remove volumes (clears data)
docker-compose down -v
```

## Building the Application

### With Docker

The Dockerfile will automatically build the application. Or build manually:

```bash
docker build -t dropwizard-app .
```

### Locally

```bash
mvn clean package
```

This will create a fat JAR at `target/sample-dw-app-otel-1.0.0.jar`.

## Running the Application

### Step 1: Download OpenTelemetry Java Agent

Download the latest OpenTelemetry Java agent (version 2.21.0 or later):

```bash
# Example: Download the agent
wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.21.0/opentelemetry-javaagent.jar
```

### Step 2: Run with OpenTelemetry Agent (Virtual Threads Disabled)

This reproduces the issue where metrics are not collected:

```bash
java \
  -javaagent:./opentelemetry-javaagent.jar \
  -Dotel.service.name=dropwizard-test \
  -Dotel.exporter.otlp.endpoint=http://localhost:4317 \
  -Dotel.metrics.exporter=otlp \
  -jar target/sample-dw-app-otel-1.0.0.jar server config.yml
```

**Note**: The `config.yml` file has `enableVirtualThreads: false`, which is the problematic configuration.

### Step 3: Generate Traffic

In another terminal, send some requests to the application:

```bash
# Send multiple requests
for i in {1..100}; do
  curl http://localhost:8080/ping
  sleep 0.1
done
```

Or use a simple load test:

```bash
# Using Apache Bench (if available)
ab -n 1000 -c 10 http://localhost:8080/ping
```

### Step 4: Check Metrics

Check your metrics backend (OTLP collector, Prometheus, etc.) for HTTP server metrics. You should notice that:

- **Expected metrics are missing**: `io.dropwizard.jetty.MutableServletContextHandler.requests`, request duration timers, request/response size meters, per-endpoint and per-status-code metrics
- Only traces and some basic metrics may be present

### Step 5: Verify Workaround (Virtual Threads Enabled)

To verify the workaround, modify `config.yml` to enable virtual threads:

```yaml
server:
  type: default
  enableVirtualThreads: true
```

Restart the application with the same OpenTelemetry agent configuration and send the same traffic. You should observe that HTTP metrics are now collected correctly.

## Expected Behavior

Dropwizard's built-in instrumentation should automatically register:
- Request duration timers
- Request/response size meters
- Per-endpoint and per-status-code metrics (e.g., `io.dropwizard.jetty.MutableServletContextHandler.requests`)

Metrics should appear under the configured metrics backend (Prometheus, console, JMX, OTLP, etc.).

## Actual Behavior (Bug)

When `enableVirtualThreads: false`:
- No HTTP server metrics are reported
- Request/response metrics are missing
- Only traces and some basic metrics may be present

When `enableVirtualThreads: true`:
- HTTP metrics appear to be collected correctly

## Environment

- **JDK**: 21.0.8 (tested with Corretto, but any JDK 21+ should work)
- **OS**: Linux (tested on Amazon Linux, but should work on any Linux)
- **Dropwizard**: 5.0.0
- **OpenTelemetry Java Agent**: 2.21.0

## Alternative: Using Prometheus Exporter

If you prefer to use Prometheus instead of OTLP:

```bash
java \
  -javaagent:./opentelemetry-javaagent.jar \
  -Dotel.service.name=dropwizard-test \
  -Dotel.metrics.exporter=prometheus \
  -Dotel.exporter.prometheus.port=9464 \
  -jar target/sample-dw-app-otel-1.0.0.jar server config.yml
```

Then check metrics at `http://localhost:9464/metrics`.

## Related Issue

- [opentelemetry-java-instrumentation#15511](https://github.com/open-telemetry/opentelemetry-java-instrumentation/issues/15511)

