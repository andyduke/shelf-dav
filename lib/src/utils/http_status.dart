/// HTTP status code constants for WebDAV
///
/// Provides named constants for HTTP status codes used throughout the WebDAV server.
/// Using constants improves code readability and prevents magic number issues.
class HttpStatus {
  // Informational 1xx
  static const continue_ = 100;

  // Successful 2xx
  static const ok = 200;
  static const created = 201;
  static const accepted = 202;
  static const noContent = 204;
  static const partialContent = 206;

  // Redirection 3xx
  static const movedPermanently = 301;
  static const found = 302;
  static const notModified = 304;

  // Client Error 4xx
  static const badRequest = 400;
  static const unauthorized = 401;
  static const forbidden = 403;
  static const notFound = 404;
  static const methodNotAllowed = 405;
  static const conflict = 409;
  static const preconditionFailed = 412;
  static const requestEntityTooLarge = 413;
  static const unsupportedMediaType = 415;
  static const requestedRangeNotSatisfiable = 416;

  // WebDAV-specific 4xx
  static const unprocessableEntity = 422;
  static const locked = 423;
  static const failedDependency = 424;
  static const tooManyRequests = 429;

  // Server Error 5xx
  static const internalServerError = 500;
  static const notImplemented = 501;
  static const badGateway = 502;
  static const serviceUnavailable = 503;

  // WebDAV-specific
  static const multiStatus = 207;
  static const insufficientStorage = 507;

  // Private constructor to prevent instantiation
  HttpStatus._();
}
