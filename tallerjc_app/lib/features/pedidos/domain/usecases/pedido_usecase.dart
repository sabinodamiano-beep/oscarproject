import '../entities/pedido.dart';
import '../repositories/pedido_repository.dart';

/// Lista de pedidos del vendedor autenticado
class GetPedidosUseCase {
  final PedidosRepository _repository;
  GetPedidosUseCase({required PedidosRepository repository})
      : _repository = repository;

  Future<List<Pedido>> execute({String? status, String? buscar}) =>
      _repository.getPedidos(status: status, buscar: buscar);
}

/// Detalle de un pedido
class GetPedidoDetalleUseCase {
  final PedidosRepository _repository;
  GetPedidoDetalleUseCase({required PedidosRepository repository})
      : _repository = repository;

  Future<Pedido> execute(String uidPedido) =>
      _repository.getPedidoDetalle(uidPedido);
}

/// Crear un pedido
class CrearPedidoUseCase {
  final PedidosRepository _repository;
  CrearPedidoUseCase({required PedidosRepository repository})
      : _repository = repository;

  Future<Map<String, dynamic>> execute({
    required int uidCliente,
    String? observaciones,
    required List<Map<String, dynamic>> items,
  }) async {
    if (uidCliente <= 0) {
      throw ArgumentError('Debe seleccionar un cliente');
    }
    if (items.isEmpty) {
      throw ArgumentError('El pedido debe tener al menos un producto');
    }
    return _repository.crearPedido(
      uidCliente: uidCliente,
      observaciones: observaciones?.trim(),
      items: items,
    );
  }
}

/// Actualizar un pedido en proceso
class ActualizarPedidoUseCase {
  final PedidosRepository _repository;
  ActualizarPedidoUseCase({required PedidosRepository repository})
      : _repository = repository;

  Future<Map<String, dynamic>> execute(
    String uidPedido, {
    String? observaciones,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('El pedido debe tener al menos un producto');
    }
    return _repository.actualizarPedido(
      uidPedido,
      observaciones: observaciones?.trim(),
      items: items,
    );
  }
}

/// Anular un pedido (solo EN PROCESO)
class AnularPedidoUseCase {
  final PedidosRepository _repository;
  AnularPedidoUseCase({required PedidosRepository repository})
      : _repository = repository;

  Future<void> execute(String uidPedido, {String? motivo}) =>
      _repository.anularPedido(uidPedido, motivo: motivo);
}
