import '../entities/pedido.dart';

abstract class PedidosRepository {
  Future<List<Pedido>> getPedidos({String? status, String? buscar});
  Future<Pedido> getPedidoDetalle(String uidPedido);
  Future<Map<String, dynamic>> crearPedido({
    required int uidCliente,
    String? observaciones,
    required List<Map<String, dynamic>> items,
  });
  Future<Map<String, dynamic>> actualizarPedido(
    String uidPedido, {
    String? observaciones,
    required List<Map<String, dynamic>> items,
  });
  Future<void> anularPedido(String uidPedido, {String? motivo});
}
