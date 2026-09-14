import 'package:url_launcher/url_launcher.dart';

/// Línea genérica para el texto compartido (sirve tanto para pedidos
/// sincronizados como para pedidos locales pendientes).
class LineaCompartir {
  final String descripcion;
  final String presentacion; // p. ej. 'CAJA 12X0.75' (solo la usa el PDF)
  final double cajas;
  final double botellas;
  final double precioUnit;
  final double total;

  const LineaCompartir({
    required this.descripcion,
    this.presentacion = '',
    required this.cajas,
    required this.botellas,
    required this.precioUnit,
    required this.total,
  });
}

/// Arma el texto del pedido y lo abre en WhatsApp para que el vendedor
/// elija el contacto. No requiere número de teléfono.
class PedidoCompartir {
  PedidoCompartir._();

  static String _num(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

  static String _money(double n) => '\$${n.toStringAsFixed(2)}';

  /// Construye el mensaje. Usa *asteriscos* para negritas de WhatsApp.
  static String textoPedido({
    required String titulo,
    required String fecha,
    required String clienteNombre,
    required List<LineaCompartir> lineas,
    required double total,
    String observaciones = '',
  }) {
    final b = StringBuffer();
    b.writeln('🧾 *$titulo*');
    b.writeln('Fecha: $fecha');
    b.writeln('Cliente: $clienteNombre');
    b.writeln('');
    for (final l in lineas) {
      final cant = StringBuffer();
      if (l.cajas > 0) {
        cant.write('${_num(l.cajas)} ${l.cajas == 1 ? 'caja' : 'cajas'}');
      }
      if (l.botellas > 0) {
        if (cant.isNotEmpty) cant.write(' + ');
        cant.write('${_num(l.botellas)} bot.');
      }
      if (cant.isEmpty) cant.write(_num(l.cajas));
      b.writeln('• ${l.descripcion}');
      b.writeln('   $cant × ${_money(l.precioUnit)} = ${_money(l.total)}');
    }
    b.writeln('');
    b.writeln('*Total: ${_money(total)}*');
    if (observaciones.trim().isNotEmpty &&
        observaciones.trim().toUpperCase() != 'SIN COMENTARIOS') {
      b.writeln('');
      b.writeln('Obs: ${observaciones.trim()}');
    }
    return b.toString();
  }

  /// Abre WhatsApp con el texto prellenado. Devuelve false si no se pudo
  /// abrir (p. ej. WhatsApp no instalado y sin navegador disponible).
  static Future<bool> porWhatsApp(String texto) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}