import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/item_model.dart';
import '../models/marca_model.dart';

class ItemsRemoteDatasource {
  final ApiClient _apiClient;

  ItemsRemoteDatasource({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<List<ItemModel>> getItems({String? buscar, String? linea}) async {
    final params = <String, String>{};
    if (buscar != null && buscar.isNotEmpty) params['buscar'] = buscar;
    if (linea != null && linea.isNotEmpty) params['linea'] = linea;
    String endpoint = ApiConstants.productos;
    if (params.isNotEmpty) {
      endpoint += '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    final response = await _apiClient.get(endpoint);
    final lista = response as List;
    return lista.map((json) => ItemModel.fromJson(json)).toList();
  }

  Future<ItemModel> getItemDetalle(String coditems) async {
    final response = await _apiClient.get('${ApiConstants.productos}/$coditems');
    return ItemModel.fromJson(response);
  }

  Future<List<String>> getLineas() async {
    final response = await _apiClient.get(ApiConstants.lineas);
    final lista = response as List;
    return lista
        .map((json) => (json['Nombre_Linea'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<List<MarcaModel>> getMarcas() async {
    final response = await _apiClient.get(ApiConstants.marcas);
    final lista = response as List;
    return lista.map((json) => MarcaModel.fromJson(json)).toList();
  }
}