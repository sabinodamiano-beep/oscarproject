import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/vendedor.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/vendedor_model.dart';

/// Implementación del repositorio de autenticación
/// Coordina entre la API remota y el almacenamiento local
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDatasource _remoteDatasource;
  final ApiClient _apiClient;

  // Keys para SharedPreferences
  static const String _tokenKey = 'jwt_token';
  static const String _vendedorKey = 'vendedor_data';
  static const String _empresaKey = 'empresa_actual';
  static const String _empresaNombreKey = 'empresa_nombre';
  static const String _cedulaRecordadaKey = 'cedula_recordada';

  AuthRepositoryImpl({
    AuthRemoteDatasource? remoteDatasource,
    ApiClient? apiClient,
  })  : _remoteDatasource = remoteDatasource ?? AuthRemoteDatasource(),
        _apiClient = apiClient ?? ApiClient();

  @override
  Future<List<Map<String, dynamic>>> getEmpresas() async {
    return await _remoteDatasource.getEmpresas();
  }

  @override
  Future<Vendedor> login(String empresa, String cedula, String password) async {
    final result = await _remoteDatasource.login(empresa, cedula, password);

    final token = result['token'] as String;
    final empresaConfirmada = result['empresa'] as String;
    final vendedor = result['vendedor'] as VendedorModel;

    // Guardar token en el ApiClient para futuras peticiones
    _apiClient.setToken(token);

    // Guardar en SharedPreferences para persistencia
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_empresaKey, empresaConfirmada);
    await prefs.setString(_vendedorKey, jsonEncode(vendedor.toJson()));

    return vendedor;
  }

  @override
  Future<void> logout() async {
    _apiClient.clearToken();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_vendedorKey);
    // Nota: _empresaKey NO se borra, para preseleccionar la empresa
    // en el próximo login del mismo teléfono.
  }

  @override
  Future<bool> haySesionActiva() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);

    if (token == null || token.isEmpty) return false;

    // Restaurar token en el ApiClient
    _apiClient.setToken(token);

    // Verificar que el token siga siendo válido haciendo un request de prueba
    final isConnected = await _apiClient.testConnection();
    if (!isConnected) {
      // Si no hay conexión, asumimos que la sesión sigue activa
      // (puede estar offline temporalmente)
      return true;
    }

    return true;
  }

  @override
  Future<Vendedor?> getVendedorGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    final vendedorJson = prefs.getString(_vendedorKey);

    if (vendedorJson == null) return null;

    final map = jsonDecode(vendedorJson) as Map<String, dynamic>;
    return VendedorModel.fromStorage(map);
  }

  @override
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  @override
  Future<String?> getEmpresaGuardada() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_empresaKey);
  }

  @override
  Future<void> guardarEmpresaNombre(String nombre) async {
    if (nombre.trim().isEmpty) return; // no pisar lo guardado con vacío
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_empresaNombreKey, nombre.trim());
  }

  @override
  Future<String> getEmpresaNombre() async {
    final prefs = await SharedPreferences.getInstance();
    final nombre = prefs.getString(_empresaNombreKey);
    if (nombre != null && nombre.isNotEmpty) return nombre;
    // Fallback: el código de empresa si nunca se guardó el nombre
    return prefs.getString(_empresaKey) ?? '';
  }

  @override
  Future<void> guardarCedulaRecordada(String cedula) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cedulaRecordadaKey, cedula);
  }

  @override
  Future<String?> getCedulaRecordada() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cedulaRecordadaKey);
  }

  @override
  Future<void> limpiarCedulaRecordada() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cedulaRecordadaKey);
  }
}
