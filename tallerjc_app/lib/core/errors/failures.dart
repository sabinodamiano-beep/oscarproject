/// Clase base de fallo - se usa en la capa de dominio
abstract class Failure {
  final String message;

  const Failure({required this.message});

  @override
  String toString() => message;
}

/// Fallo del servidor (API respondió con error)
class ServerFailure extends Failure {
  final int? statusCode;

  const ServerFailure({required super.message, this.statusCode});
}

/// Fallo de red (sin internet o timeout)
class NetworkFailure extends Failure {
  const NetworkFailure({required super.message});
}

/// Fallo de autenticación (token expirado o inválido)
class AuthFailure extends Failure {
  const AuthFailure({required super.message});
}

/// Fallo de validación (datos incorrectos en formulario)
class ValidationFailure extends Failure {
  const ValidationFailure({required super.message});
}