import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';

/// Acceso remoto del módulo de cobranza. Se trabaja con mapas crudos
/// (igual que la tarjeta de CxC): la API ya devuelve los nombres resueltos
/// de formas de pago y bancos. Desde v1.3.0 el registro también funciona
/// SIN CONEXIÓN vía CobrosOutboxService + caché de CxC del sync de catálogos.
class CobrosRemoteDatasource {
  final ApiClient _apiClient;

  CobrosRemoteDatasource({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Formas de pago y bancos activos (tbl_generalcodes).
  /// Devuelve { formas_pago: [{code, name}], bancos: [{code, name}] }
  Future<Map<String, dynamic>> getCatalogos() async {
    final response = await _apiClient.get('${ApiConstants.cobros}/catalogos');
    return Map<String, dynamic>.from(response);
  }

  /// Historial de cobros de los clientes del vendedor.
  /// status: 02 (en proceso), 06 (confirmado), 99 (anulado) o null (todos)
  Future<List<Map<String, dynamic>>> getCobros({String? status}) async {
    String endpoint = ApiConstants.cobros;
    if (status != null && status.isNotEmpty) {
      endpoint += '?status=${Uri.encodeComponent(status)}';
    }
    final response = await _apiClient.get(endpoint);
    return (response as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> getCobroDetalle(String numpago) async {
    final response = await _apiClient.get('${ApiConstants.cobros}/$numpago');
    return Map<String, dynamic>.from(response);
  }

  /// Todas las CxC pendientes de los clientes del vendedor, para el caché
  /// local de la cobranza offline. { generado_en, documentos: [...] }
  Future<Map<String, dynamic>> getCxcVendedor() async {
    final response =
        await _apiClient.get('${ApiConstants.cobros}/cxc-vendedor');
    return Map<String, dynamic>.from(response);
  }

  /// Registra el cobro. El cobro queda EN PROCESO hasta que la oficina
  /// lo verifique y cierre desde InvenSoft.
  Future<Map<String, dynamic>> crearCobro(Map<String, dynamic> datos) async {
    final response = await _apiClient.post(ApiConstants.cobros, datos);
    return Map<String, dynamic>.from(response);
  }

  Future<void> anularCobro(String numpago, {String? motivo}) async {
    await _apiClient.delete(
      '${ApiConstants.cobros}/$numpago',
      body: motivo != null ? {'motivo': motivo} : null,
    );
  }
}
