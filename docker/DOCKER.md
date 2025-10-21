# Docker Deployment Guide

This guide explains how to deploy shelf_dav using Docker.

## Quick Start

### Using Docker Compose (Recommended)

1. **Start the server with anonymous access:**
   ```bash
   docker-compose -f docker/docker-compose.yml up -d
   ```

   The WebDAV server will be available at `http://localhost:8080/dav`

2. **Start with authentication enabled:**
   ```bash
   docker-compose -f docker/docker-compose.yml --profile auth up -d webdav-auth
   ```

   Default credentials: `admin` / `changeme`
   Server available at `http://localhost:8081/dav`

3. **View logs:**
   ```bash
   docker-compose -f docker/docker-compose.yml logs -f
   ```

4. **Stop the server:**
   ```bash
   docker-compose -f docker/docker-compose.yml down
   ```

### Using Docker CLI

1. **Build the image:**
   ```bash
   docker build -f docker/Dockerfile -t shelf-webdav .
   ```

2. **Run with anonymous access:**
   ```bash
   docker run -d \
     --name webdav \
     -p 8080:8080 \
     -v $(pwd)/data:/data \
     shelf-webdav
   ```

3. **Run with authentication:**
   ```bash
   docker run -d \
     --name webdav-auth \
     -p 8080:8080 \
     -e ALLOW_ANONYMOUS=false \
     -e DAV_USERNAME=admin \
     -e DAV_PASSWORD=your-secure-password \
     -v $(pwd)/data:/data \
     shelf-webdav
   ```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Server port |
| `HOST` | `0.0.0.0` | Bind address (0.0.0.0 for all interfaces) |
| `DATA_DIR` | `/data` | WebDAV root directory path |
| `DAV_PREFIX` | `/dav` | URL prefix for WebDAV endpoints |
| `ALLOW_ANONYMOUS` | `true` | Allow unauthenticated access |
| `DAV_USERNAME` | - | Username for HTTP Basic Authentication |
| `DAV_PASSWORD` | - | Password for HTTP Basic Authentication |
| `MAX_CONCURRENT` | `100` | Maximum concurrent requests |
| `MAX_REQ_PER_SEC` | `10` | Maximum requests per second per IP |

### Volume Mounts

The container expects data to be mounted at `/data`. Example:

```bash
docker run -v /path/on/host:/data shelf-webdav
```

## Usage Examples

### Deployment with Authentication

Create a `docker-compose.override.yml` in the project root:

```yaml
version: '3.8'

services:
  webdav:
    environment:
      - ALLOW_ANONYMOUS=false
      - DAV_USERNAME=${WEBDAV_USER}
      - DAV_PASSWORD=${WEBDAV_PASS}
      - MAX_CONCURRENT=200
      - MAX_REQ_PER_SEC=20
    volumes:
      - /mnt/storage:/data
```

Create a `.env` file in the project root:
```
WEBDAV_USER=admin
WEBDAV_PASS=very-secure-password-here
```

Start the server from the project root:
```bash
docker-compose -f docker/docker-compose.yml -f docker-compose.override.yml up -d
```

### Read-Only WebDAV Server

Mount the data directory as read-only:

```bash
docker run -d \
  --name webdav-readonly \
  -p 8080:8080 \
  -v $(pwd)/data:/data:ro \
  shelf-webdav
```

## Connecting to the Server

### macOS Finder

1. Open Finder
2. Press `Cmd+K` or Go → Connect to Server
3. Enter: `http://localhost:8080/dav`
4. If authentication is enabled, enter username and password

### Windows Explorer

1. Open File Explorer
2. Right-click "This PC" → "Map network drive"
3. Enter: `http://localhost:8080/dav`
4. If authentication is enabled, enter username and password

### Linux (Nautilus/Files)

1. Open Files
2. Press `Ctrl+L`
3. Enter: `dav://localhost:8080/dav`
4. If authentication is enabled, enter username and password

### Command Line (curl)

```bash
# List files
curl http://localhost:8080/dav/

# With authentication
curl -u admin:password http://localhost:8080/dav/

# Upload file
curl -T myfile.txt http://localhost:8080/dav/myfile.txt

# Download file
curl -O http://localhost:8080/dav/myfile.txt
```

## Troubleshooting

### Permission Denied

If you see permission errors, ensure the data directory has proper permissions:

```bash
mkdir -p data
chmod 777 data  # Or use appropriate user/group ownership
```

### Cannot Connect

1. Check if the container is running:
   ```bash
   docker ps
   ```

2. Check container logs:
   ```bash
   docker logs webdav
   ```

3. Verify port is not already in use:
   ```bash
   lsof -i :8080
   ```

### Authentication Issues

If authentication isn't working:

1. Verify environment variables are set:
   ```bash
   docker exec webdav env | grep DAV
   ```

2. Ensure `ALLOW_ANONYMOUS=false` is set

3. Check username/password are correct

## Health Checks

The docker-compose.yml includes a health check. To manually check:

```bash
docker exec webdav wget --quiet --tries=1 --spider http://localhost:8080/dav/
echo $?  # 0 = healthy, non-zero = unhealthy
```
