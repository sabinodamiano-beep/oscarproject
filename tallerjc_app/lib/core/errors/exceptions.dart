/// Excepción cuando el servidor responde con error
class ServerException implements Exception {
  final String message;
  final int? statusCode;

  ServerException({required this.message, this.statusCode});

  @override
  String toString() => message;
}

/// Excepción cuando no hay conexión a internet
class NetworkException implements Exception {
  final String message;

  NetworkException({this.message = 'Sin conexión a internet'});

  @override
  String toString() => message;
}

/// Excepción cuando el token JWT expiró o es inválido
class UnauthorizedException implements Exception {
  final String message;

  UnauthorizedException({this.message = 'Sesión expirada, inicia sesión nuevamente'});

  @override
  String toString() => message;
}

/// Excepción de timeout
class AppTimeoutException implements Exception {
  final String message;

  AppTimeoutException({this.message = 'El servidor no responde, intenta más tarde'});

  @override
  String toString() => message;
}