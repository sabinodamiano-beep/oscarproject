import 'dart:convert';

import '../../../../core/database/local_database.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/sync/connection_monitor.dart';
import '../../../../core/sync/outbox_sync_service.dart';
import '../../domain/entities/pedido.dart';
import '../../domain/repositories/pedido_repository.dart';
import '../datasources/pedido_remote_datasource.dart';
import '../models/pedido_model.dart';

/// Pedidos del servidor. Sin conexión:
///  - la lista sale del último listado descargado (guardado en `meta`),
///  - el detalle sale del último detalle visto de ese pedido,
///  - crear va por el outbox (ver PedidosProvider), editar y anular exigen conexión.
class PedidosRepositoryImpl implements PedidosRepository {
  final PedidosRemoteDatasource _remoteDatasource;
  final LocalDatabase _local = LocalDatabase.instance;
  final ConnectionMonitor _monitor = ConnectionMonitor.instance;

  PedidosRepositoryImpl({PedidosRemoteDatasource? remoteDatasource})
      : _remoteDatasource = remoteDatasource ?? PedidosRemoteDatasource();

  String get _claveLista => 'pedidos_lista_${OutboxSyncService.instance.uidVendedor ?? 'x'}';
  String _claveDetalle(String uid) => 'pedido_detalle_$uid';

  @override
  Future<List<Pedido>> getPedidos({String? status, String? buscar}) async {
    if (_monitor.intentarRemoto) {
      try {
        final lista = await _remoteDatasource.getPedidos(status: status, buscar: buscar);
        // Solo se cachea el listado completo (sin filtros), que es el que sirve offline.
        if ((status == null || status.isEmpty) && (buscar == null || buscar.isEmpty)) {
          _guardarLista(lista);
        }
        return lista;
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    return _listaLocal(status: status, buscar: buscar);
  }

  @override
  Future<Pedido> getPedidoDetalle(String uidPedido) async {
    if (_monitor.intentarRemoto) {
      try {
        final p = await _remoteDatasource.getPedidoDetalle(uidPedido);
        _guardarDetalle(uidPedido, p);
        return p;
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    if (!_local.abierta) throw NetworkException();
    final json = await _local.getMeta(_claveDetalle(uidPedido));
    if (json == null) {
      throw NetworkException(message: 'Sin conexión. Este pedido no se ha abierto antes en el teléfono.');
    }
    return PedidoModel.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map));
  }

  @override
  Future<Map<String, dynamic>> crearPedido({
    required int uidCliente,
    String? observaciones,
    required List<Map<String, dynamic>> items,
  }) {
    // Ruta directa (sin outbox). El provider usa OutboxSyncService; esta queda
    // para compatibilidad.
    final datos = PedidoModel.toCreateJson(
      uidCliente: uidCliente,
      observaciones: observaciones,
      items: items,
    );
    return _remoteDatasource.crearPedido(datos);
  }

  @override
  Future<Map<String, dynamic>> actualizarPedido(
    String uidPedido, {
    String? observaciones,
    required List<Map<String, dynamic>> items,
  }) {
    _exigirConexion('Editar un pedido ya enviado');
    return _remoteDatasource.actualizarPedido(
      uidPedido,
      pedidoToUpdateJson(observaciones: observaciones, items: items),
    );
  }

  @override
  Future<void> anularPedido(String uidPedido, {String? motivo}) {
    _exigirConexion('Anular un pedido');
    return _remoteDatasource.anularPedido(uidPedido, motivo: motivo);
  }

  // ------------------------------------------------------------ caché

  void _exigirConexion(String accion) {
    if (!_monitor.intentarRemoto) {
      throw NetworkException(message: '$accion requiere conexión. Intenta cuando tengas señal.');
    }
  }

  Future<void> _guardarLista(List<PedidoModel> lista) async {
    if (!_local.abierta) return;
    try {
      await _local.setMeta(_claveLista, jsonEncode(lista.map(_pedidoAJson).toList()));
    } catch (_) {}
  }

  Future<void> _guardarDetalle(String uid, PedidoModel p) async {
    if (!_local.abierta) return;
    try {
      await _local.setMeta(_claveDetalle(uid), jsonEncode(_pedidoAJson(p)));
    } catch (_) {}
  }

  Future<List<Pedido>> _listaLocal({String? status, String? buscar}) async {
    if (!_local.abierta) throw NetworkException();
    final json = await _local.getMeta(_claveLista);
    if (json == null) {
      throw NetworkException(message: 'Sin conexión y sin pedidos guardados en el teléfono.');
    }
    final lista = (jsonDecode(json) as List)
        .map((e) => PedidoModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((p) => status == null || status.isEmpty || p.idStatus == status)
        .where((p) {
          if (buscar == null || buscar.trim().isEmpty) return true;
          final q = LocalDatabase.normalizar([buscar]);
          return LocalDatabase.normalizar([p.uidPedido, p.clienteNombre]).contains(q);
        })
        .toList();
    return lista;
  }

  /// Serialización inversa de PedidoModel.fromJson (mismas claves de la API).
  Map<String, dynamic> _pedidoAJson(Pedido p) => {
        'uid_pedido': p.uidPedido,
        'fecha_pedido': p.fechaPedido?.toIso8601String(),
        'id_status': p.idStatus,
        'status': p.status,
        'uid_cliente': p.uidCliente,
        'str_cliente_nombres': p.clienteNombre,
        'str_cliente_apellidos': '',
        'str_cliente_direccion': p.clienteDireccion,
        'TotalItems': p.totalItems,
        'total': p.total,
        'observaciones': p.observaciones,
        'facturado': p.facturado,
        'numfactu': p.numFactura,
        'items': p.items
            .map((i) => {
                  'coditems': i.coditems,
                  'descripcion': i.descripcion,
                  'cantidad': i.cantidad,
                  'cantidad_unidad': i.cantidadUnidad,
                  'unidad_total': i.unidadTotal,
                  'precunit': i.precunit,
                  'total': i.total,
                  'DOLpre': i.dolPre,
                  'cantunidad': i.cantunidad,
                  'VentaBotella': i.ventaBotella,
                  'activo': i.activo ? '1' : '0',
                  'Nombre_Linea': i.nombreLinea,
                  'Nombre_Presentacion': i.nombrePresentacion,
                })
            .toList(),
      };
}
