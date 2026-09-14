import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/cliente_model.dart';

class ClientesRemoteDatasource {
  final ApiClient _apiClient;

  ClientesRemoteDatasource({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<List<ClienteModel>> getClientes({String? buscar}) async {
    String endpoint = ApiConstants.clientes;
    if (buscar != null && buscar.isNotEmpty) {
      endpoint += '?buscar=${Uri.encodeComponent(buscar)}';
    }

    final response = await _apiClient.get(endpoint);
    final lista = response as List;
    return lista.map((json) => ClienteModel.fromJson(json)).toList();
  }

  Future<ClienteModel> getClienteDetalle(int uidCliente) async {
    final response = await _apiClient.get('${ApiConstants.clientes}/$uidCliente');
    return ClienteModel.fromJson(response);
  }

  /// Cuentas por cobrar del cliente (solo lectura).
  /// Devuelve {total_deuda, total_documentos, documentos_vencidos,
  /// monto_vencido, documentos: [...]}
  Future<Map<String, dynamic>> getCuentasPorCobrar(int uidCliente) async {
    final response =
        await _apiClient.get('${ApiConstants.clientes}/$uidCliente/cxc');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> crearCliente(Map<String, dynamic> datos) async {
    final response = await _apiClient.post(ApiConstants.clientes, datos);
    return response;
  }
}