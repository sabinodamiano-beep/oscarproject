import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/vendedor_model.dart';

/// Fuente de datos remota para autenticación
/// Se comunica con la API REST
class AuthRemoteDatasource {
  final ApiClient _apiClient;

  AuthRemoteDatasource({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Llamar GET /api/empresas (público, sin token)
  /// Retorna la lista de empresas disponibles: [{codigo, nombre}]
  Future<List<Map<String, dynamic>>> getEmpresas() async {
    final response = await _apiClient.get(ApiConstants.empresas);
    return (response as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Llamar POST /api/login
  /// Retorna token y datos del vendedor
  Future<Map<String, dynamic>> login(
      String empresa, String cedula, String password) async {
    final response = await _apiClient.post(
      ApiConstants.login,
      {'empresa': empresa, 'cedula': cedula, 'password': password},
    );

    // La API devuelve: { token, empresa, vendedor: { uid_vendedor, nombre, apellido, cedula } }
    final token = response['token'] as String;
    final vendedor = VendedorModel.fromJson(response['vendedor']);

    return {
      'token': token,
      'empresa': (response['empresa'] ?? empresa).toString(),
      'vendedor': vendedor,
    };
  }
}
