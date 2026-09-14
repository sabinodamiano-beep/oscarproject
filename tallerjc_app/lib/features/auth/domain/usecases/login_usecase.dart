import '../entities/vendedor.dart';
import '../repositories/auth_repository.dart';

/// Caso de uso: Iniciar sesión
/// Contiene la lógica de negocio para el login
class LoginUseCase {
  final AuthRepository _repository;

  LoginUseCase({required AuthRepository repository})
      : _repository = repository;

  /// Ejecutar el login
  /// Valida los datos antes de enviar al repositorio
  Future<Vendedor> execute(String empresa, String cedula, String password) async {
    // Validaciones de negocio
    if (empresa.trim().isEmpty) {
      throw ArgumentError('Selecciona tu empresa');
    }
    if (cedula.trim().isEmpty) {
      throw ArgumentError('Ingresa tu cédula o código');
    }
    if (password.trim().isEmpty) {
      throw ArgumentError('Ingresa tu contraseña');
    }

    return await _repository.login(empresa.trim(), cedula.trim(), password);
  }
}
