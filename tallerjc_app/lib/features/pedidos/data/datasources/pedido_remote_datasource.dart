import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/pedido_model.dart';

class PedidosRemoteDatasource {
  final ApiClient _apiClient;

  PedidosRemoteDatasource({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<List<PedidoModel>> getPedidos({String? status, String? buscar}) async {
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (buscar != null && buscar.isNotEmpty) params['buscar'] = buscar;
    String endpoint = ApiConstants.pedidos;
    if (params.isNotEmpty) {
      endpoint += '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    }
    final response = await _apiClient.get(endpoint);
    final lista = response as List;
    return lista.map((json) => PedidoModel.fromJson(json)).toList();
  }

  Future<PedidoModel> getPedidoDetalle(String uidPedido) async {
    final response = await _apiClient.get('${ApiConstants.pedidos}/$uidPedido');
    return PedidoModel.fromJson(response);
  }

  Future<Map<String, dynamic>> crearPedido(Map<String, dynamic> datos) async {
    final response = await _apiClient.post(ApiConstants.pedidos, datos);
    return response;
  }

  Future<Map<String, dynamic>> actualizarPedido(String uidPedido, Map<String, dynamic> datos) async {
    final response = await _apiClient.put('${ApiConstants.pedidos}/$uidPedido', datos);
    return response;
  }

  Future<void> anularPedido(String uidPedido, {String? motivo}) async {
    await _apiClient.delete(
      '${ApiConstants.pedidos}/$uidPedido',
      body: motivo != null ? {'motivo': motivo} : null,
    );
  }
}
