FROM maven:3.9-amazoncorretto-21 AS builder

WORKDIR /build

# Copy pom.xml first for better layer caching
COPY pom.xml .
# Copy source code
COPY src ./src

# Build the application (Maven will cache dependencies in ~/.m2/repository)
RUN mvn clean install -DskipTests -B

# Verify JAR was created and copy to fixed name for easier copying
RUN JAR_FILE=$(ls /build/target/sample-dw-app-otel-*.jar | head -1) && \
    cp "$JAR_FILE" /build/target/app.jar && \
    ls -la /build/target/app.jar || (echo "JAR file not found!" && exit 1)

# Runtime stage
FROM amazoncorretto:21-alpine

WORKDIR /app

# Install curl and netcat-openbsd for health checks and waiting
RUN apk add --no-cache curl netcat-openbsd

# Copy the built JAR (renamed to app.jar in builder stage)
COPY --from=builder /build/target/app.jar app.jar

# Copy config
COPY config.yml config.yml

# Copy wait script
COPY wait-for-otel.sh /app/wait-for-otel.sh
RUN chmod +x /app/wait-for-otel.sh

# Download OpenTelemetry Java agent
RUN curl -L -o opentelemetry-javaagent.jar \
    https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.21.0/opentelemetry-javaagent.jar

# Expose application port
EXPOSE 8080 8081

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8081/healthcheck || exit 1

# Run the application with OpenTelemetry agent
# Wait for otel-collector to be ready, then start the app
ENTRYPOINT ["/app/wait-for-otel.sh", "otel-collector", "4317", "java", \
    "-javaagent:/app/opentelemetry-javaagent.jar", \
    "-Dotel.service.name=dropwizard-app", \
    "-Dotel.exporter.otlp.endpoint=http://otel-collector:4317", \
    "-Dotel.metrics.exporter=otlp", \
    "-Dotel.traces.exporter=otlp", \
    "-Dotel.logs.exporter=otlp", \
    "-Dotel.exporter.otlp.timeout=10s", \
    "-Dotel.bsp.schedule.delay=1000", \
    "-Dotel.resource.attributes=service.name=dropwizard-app,service.version=1.0.0", \
    "-jar", "app.jar", "server", "config.yml"]
