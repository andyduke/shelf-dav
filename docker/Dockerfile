# Official Dart image: https://hub.docker.com/_/dart
# Specify the Dart SDK base image version using dart:<version> (ex: dart:2.12)
FROM dart:stable AS build

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code and AOT compile it.
COPY . .
# Ensure packages are still up-to-date if anything has changed
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

# Build minimal serving image from AOT-compiled `/server` and required system
# libraries and configuration files stored in `/runtime/` from the build stage.
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd -m -u 1000 -s /bin/bash webdav

# Create data directory with proper permissions
RUN mkdir -p /data && chown webdav:webdav /data

# Copy compiled executable
COPY --from=build /app/bin/server /app/bin/server
RUN chmod +x /app/bin/server

# Switch to non-root user
USER webdav

# Set default environment variables
ENV PORT=8080 \
    HOST=0.0.0.0 \
    DATA_DIR=/data \
    DAV_PREFIX=/dav \
    ALLOW_ANONYMOUS=true \
    MAX_CONCURRENT=100 \
    MAX_REQ_PER_SEC=10

# Set data directory as volume
VOLUME ["/data"]

# Expose port
EXPOSE 8080

# Start server.
CMD ["/app/bin/server"]
