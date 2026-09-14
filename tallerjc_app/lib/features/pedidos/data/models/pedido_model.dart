import '../../domain/entities/pedido.dart';

class PedidoItemModel extends PedidoItem {
  const PedidoItemModel({
    required super.coditems,
    required super.descripcion,
    required super.cantidad,
    required super.cantidadUnidad,
    required super.unidadTotal,
    required super.precunit,
    required super.total,
    super.dolPre,
    super.dolOfe,
    super.dolMay,
    super.dolDis,
    super.dolEsp,
    super.cantunidad,
    super.ventaBotella,
    super.activo,
    super.nombreLinea,
    super.nombrePresentacion,
  });

  factory PedidoItemModel.fromJson(Map<String, dynamic> json) {
    return PedidoItemModel(
      coditems: json['coditems']?.toString().trim() ?? '',
      descripcion: json['descripcion']?.toString().trim() ?? '',
      cantidad: _d(json['cantidad']),
      cantidadUnidad: _d(json['cantidad_unidad']),
      unidadTotal: _d(json['unidad_total']),
      precunit: _d(json['precunit']),
      total: _d(json['total']),
      dolPre: _d(json['DOLpre']),
      dolOfe: _d(json['DOLofe']),
      dolMay: _d(json['DOLmay']),
      dolDis: _d(json['DOLdis']),
      dolEsp: _d(json['DOLesp']),
      cantunidad: json['cantunidad'] == null ? 1 : _d(json['cantunidad']),
      ventaBotella: json['VentaBotella'] == true || json['VentaBotella'] == 1 || json['VentaBotella'] == '1',
      activo: json['activo'] == null || json['activo'].toString().trim() == '1',
      nombreLinea: json['Nombre_Linea']?.toString().trim() ?? '',
      nombrePresentacion: json['Nombre_Presentacion']?.toString().trim() ?? '',
    );
  }
}

class PedidoModel extends Pedido {
  const PedidoModel({
    required super.uidPedido,
    required super.fechaPedido,
    required super.idStatus,
    required super.status,
    required super.uidCliente,
    required super.clienteNombre,
    required super.clienteDireccion,
    required super.totalItems,
    required super.total,
    required super.observaciones,
    required super.facturado,
    required super.numFactura,
    super.items,
  });

  /// Sirve tanto para GET /pedidos (lista) como GET /pedidos/:id (detalle)
  factory PedidoModel.fromJson(Map<String, dynamic> json) {
    final nombres = json['str_cliente_nombres']?.toString().trim() ?? '';
    final apellidos = json['str_cliente_apellidos']?.toString().trim() ?? '';
    final nombre = apellidos.isEmpty || apellidos == '.'
        ? nombres
        : '$nombres $apellidos';

    final itemsJson = json['items'];
    final items = itemsJson is List
        ? itemsJson.map((e) => PedidoItemModel.fromJson(e)).toList()
        : <PedidoItem>[];

    return PedidoModel(
      uidPedido: json['uid_pedido']?.toString().trim() ?? '',
      fechaPedido: json['fecha_pedido'] != null
          ? DateTime.tryParse(json['fecha_pedido'].toString())
          : null,
      idStatus: json['id_status']?.toString().trim() ?? '',
      status: json['status']?.toString().trim() ?? '',
      uidCliente: json['uid_cliente'] ?? 0,
      clienteNombre: nombre,
      clienteDireccion: json['str_cliente_direccion']?.toString().trim() ?? '',
      totalItems: json['TotalItems'] ?? items.length,
      total: _d(json['total']),
      observaciones: json['observaciones']?.toString().trim() ?? '',
      facturado: json['facturado'] == true || json['facturado'] == 1,
      numFactura: json['numfactu']?.toString().trim() ?? '',
      items: items,
    );
  }

  /// Body para POST /api/pedidos
  static Map<String, dynamic> toCreateJson({
    required int uidCliente,
    String? observaciones,
    required List<Map<String, dynamic>> items,
  }) {
    return {
      'uid_cliente': uidCliente,
      if (observaciones != null && observaciones.isNotEmpty)
        'observaciones': observaciones,
      'items': items,
    };
  }
}

/// Body para PUT /api/pedidos/:id
Map<String, dynamic> pedidoToUpdateJson({
  String? observaciones,
  required List<Map<String, dynamic>> items,
}) {
  return {
    if (observaciones != null) 'observaciones': observaciones,
    'items': items,
  };
}

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim()) ?? 0;
}
