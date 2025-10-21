# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.0

### Added
- Initial WebDAV server implementation built on Shelf framework
- Full support for core WebDAV methods (GET, PUT, DELETE, HEAD, OPTIONS, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE)
- LOCK/UNLOCK support with RFC 4918 compliance (requires `enableLocking: true`)
- Authentication system with pluggable providers (Basic Auth, role-based, path-based)
- Authorization system with multiple built-in providers
- Property storage with memory, file abd DBM-based backends
- Lock storage with memory and DBM backend and custom storage support
- Request throttling with concurrent request limiting and per-IP rate limiting
- ETag support for optimistic concurrency control
- 207 Multi-Status responses for partial failures in collection operations
- Atomic file operations (writes, moves) to prevent data corruption
- Path traversal protection with multiple validation layers
- Configurable server options via DAVConfig
- Docker deployment support with Dockerfile and docker-compose
- Comprehensive test suite using webdav_client
- Metrics collection for monitoring server performance
- Examples for standalone and embedded usage
