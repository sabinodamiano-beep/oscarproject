import '../entities/vendedor.dart';

/// Contrato del repositorio de autenticación - capa de dominio
/// Define QUÉ se puede hacer, no CÓMO se hace
abstract class AuthRepository {
  /// Obtener la lista de empresas disponibles desde la API
  /// Retorna [{codigo, nombre}]
  Future<List<Map<String, dynamic>>> getEmpresas();

  /// Iniciar sesión en una empresa con cédula/código y contraseña
  /// Retorna el Vendedor si el login es exitoso
  Future<Vendedor> login(String empresa, String cedula, String password);

  /// Cerrar sesión (limpiar token y datos locales)
  Future<void> logout();

  /// Verificar si hay una sesión activa guardada
  Future<bool> haySesionActiva();

  /// Obtener el vendedor guardado localmente
  Future<Vendedor?> getVendedorGuardado();

  /// Obtener el token JWT guardado
  Future<String?> getToken();

  /// Obtener el código de empresa de la sesión actual / última sesión
  Future<String?> getEmpresaGuardada();

  /// Guardar el nombre de la empresa (tenant) para mostrarlo en documentos
  Future<void> guardarEmpresaNombre(String nombre);

  /// Obtener el nombre de la empresa; si nunca se guardó, retorna el código
  Future<String> getEmpresaNombre();

  /// Guardar la cédula del usuario para "Recordar usuario"
  Future<void> guardarCedulaRecordada(String cedula);

  /// Obtener la cédula guardada (recordar usuario)
  Future<String?> getCedulaRecordada();

  /// Limpiar la cédula recordada
  Future<void> limpiarCedulaRecordada();
}
