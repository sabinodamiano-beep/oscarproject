/// Línea de detalle de un pedido (tal como la devuelve la API)
class PedidoItem {
  final String coditems;
  final String descripcion;
  final double cantidad;        // cajas (o unidades si cantunidad = 1)
  final double cantidadUnidad;  // botellas sueltas
  final double unidadTotal;
  final double precunit;
  final double total;
  // Datos actuales del producto (solo vienen en GET /pedidos/:id), para editar
  final double dolPre;
  final double dolOfe;
  final double dolMay;
  final double dolDis;
  final double dolEsp;
  final double cantunidad;
  final bool ventaBotella;
  final bool activo;
  final String nombreLinea;
  final String nombrePresentacion;

  const PedidoItem({
    required this.coditems,
    required this.descripcion,
    required this.cantidad,
    required this.cantidadUnidad,
    required this.unidadTotal,
    required this.precunit,
    required this.total,
    this.dolPre = 0,
    this.dolOfe = 0,
    this.dolMay = 0,
    this.dolDis = 0,
    this.dolEsp = 0,
    this.cantunidad = 1,
    this.ventaBotella = false,
    this.activo = true,
    this.nombreLinea = '',
    this.nombrePresentacion = '',
  });

  /// Deduce qué nivel de precio se usó, comparando el precio grabado en el
  /// pedido contra los precios actuales del producto. Sirve para que al
  /// editar no se le cambie el precio al cliente sin querer.
  String get nivelDetectado {
    const tol = 0.005;
    if ((precunit - dolPre).abs() < tol) return 'pvp';
    if (dolOfe > 0 && (precunit - dolOfe).abs() < tol) return 'ofe';
    if (dolMay > 0 && (precunit - dolMay).abs() < tol) return 'may';
    if (dolDis > 0 && (precunit - dolDis).abs() < tol) return 'dis';
    if (dolEsp > 0 && (precunit - dolEsp).abs() < tol) return 'esp';
    return 'pvp';
  }
}

/// Pedido (cabecera + detalle opcional)
class Pedido {
  final String uidPedido;
  final DateTime? fechaPedido;
  final String idStatus;
  final String status;
  final int uidCliente;
  final String clienteNombre;
  final String clienteDireccion;
  final int totalItems;
  final double total;
  final String observaciones;
  final bool facturado;
  final String numFactura;
  final List<PedidoItem> items;

  const Pedido({
    required this.uidPedido,
    required this.fechaPedido,
    required this.idStatus,
    required this.status,
    required this.uidCliente,
    required this.clienteNombre,
    required this.clienteDireccion,
    required this.totalItems,
    required this.total,
    required this.observaciones,
    required this.facturado,
    required this.numFactura,
    this.items = const [],
  });

  static const String statusEnProceso = '00';
  static const String statusAnulado = '99';

  bool get enProceso => idStatus == statusEnProceso;
  bool get anulado => idStatus == statusAnulado;
  bool get tieneObservaciones =>
      observaciones.isNotEmpty && observaciones != 'SIN COMENTARIOS';
}
