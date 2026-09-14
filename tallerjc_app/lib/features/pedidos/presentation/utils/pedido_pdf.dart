import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pedido_compartir.dart' show LineaCompartir;

/// Genera la "Nota de Pedido" en PDF y la comparte por el menú del
/// sistema (WhatsApp, correo, etc.). Reutiliza [LineaCompartir] para que
/// sirva tanto para pedidos sincronizados como para pedidos locales.
///
/// Usa las fuentes Helvetica incluidas en el paquete `pdf` (soportan
/// acentos y ñ), por lo que funciona 100% offline: no descarga nada.
class PedidoPdf {
  PedidoPdf._();

  // Colores corporativos (mismos azules del tema de la app)
  static const _azul = PdfColor.fromInt(0xFF1565C0);
  static const _azulOscuro = PdfColor.fromInt(0xFF0D1B2A);
  static const _grisTexto = PdfColor.fromInt(0xFF455A64);
  static const _grisFondo = PdfColor.fromInt(0xFFECEFF1);
  static const _grisLinea = PdfColor.fromInt(0xFFCFD8DC);

  static String _num(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

  static String _money(double n) => '\$${n.toStringAsFixed(2)}';

  static String _cantidadTexto(LineaCompartir l) {
    final b = StringBuffer();
    if (l.cajas > 0) {
      b.write('${_num(l.cajas)} ${l.cajas == 1 ? 'caja' : 'cajas'}');
    }
    if (l.botellas > 0) {
      if (b.isNotEmpty) b.write(' + ');
      b.write('${_num(l.botellas)} bot.');
    }
    if (b.isEmpty) b.write(_num(l.cajas));
    return b.toString();
  }

  /// Construye el documento y devuelve los bytes del PDF.
  static Future<Uint8List> generar({
    required String empresaNombre,
    required String numeroPedido, // p. ej. '9000012' o 'PENDIENTE DE ENVIO'
    required String fecha,
    required String vendedorNombre,
    required String clienteNombre,
    required String clienteDireccion,
    required List<LineaCompartir> lineas,
    required double total,
    String observaciones = '',
    String estado = '',
  }) async {
    final doc = pw.Document();

    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    final generado =
        '${dos(ahora.day)}/${dos(ahora.month)}/${ahora.year} ${dos(ahora.hour)}:${dos(ahora.minute)}';

    final obs = observaciones.trim();
    final tieneObs = obs.isNotEmpty && obs.toUpperCase() != 'SIN COMENTARIOS';

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
          // Marca de agua: nombre de la licorería en diagonal, muy tenue,
          // detrás del contenido en todas las páginas.
          buildBackground: (ctx) => pw.Watermark.text(
            empresaNombre.toUpperCase(),
            style: pw.TextStyle(
              color: const PdfColor.fromInt(0xFFE4EAF0),
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        footer: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Divider(color: _grisLinea, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'GyfSoftware Movil  -  generado el $generado',
                  style: const pw.TextStyle(fontSize: 8, color: _grisTexto),
                ),
                pw.Text(
                  'Pag. ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: _grisTexto),
                ),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          // ---------------------------------------------------- encabezado
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: const pw.BoxDecoration(
              color: _azulOscuro,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      empresaNombre.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'NOTA DE PEDIDO',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColor.fromInt(0xFF90CAF9),
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'N. $numeroPedido',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Fecha: $fecha',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (estado.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                'Estado: $estado',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _grisTexto,
                ),
              ),
            ),
          pw.SizedBox(height: 12),

          // ------------------------------------------- vendedor / cliente
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _grisFondo,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _dato('Vendedor', vendedorNombre),
                pw.SizedBox(height: 4),
                _dato('Cliente', clienteNombre),
                if (clienteDireccion.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  _dato('Direccion', clienteDireccion.trim()),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ------------------------------------------------------ detalle
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Descripcion', 'Cantidad', 'P. Unit', 'Total'],
            data: [
              for (var i = 0; i < lineas.length; i++)
                [
                  '${i + 1}',
                  // Descripción + presentación (segunda línea, más pequeña)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(lineas[i].descripcion,
                          style: const pw.TextStyle(fontSize: 9)),
                      if (lineas[i].presentacion.trim().isNotEmpty)
                        pw.Text(
                          lineas[i].presentacion.trim(),
                          style: const pw.TextStyle(
                              fontSize: 7, color: _grisTexto),
                        ),
                    ],
                  ),
                  _cantidadTexto(lineas[i]),
                  _money(lineas[i].precioUnit),
                  _money(lineas[i].total),
                ],
            ],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: _azul),
            cellStyle: const pw.TextStyle(fontSize: 9),
            oddRowDecoration: const pw.BoxDecoration(color: _grisFondo),
            border: null,
            cellPadding:
                const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(20),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(1.6),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
            },
          ),
          pw.SizedBox(height: 8),

          // -------------------------------------------------------- total
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    vertical: 6, horizontal: 14),
                decoration: const pw.BoxDecoration(
                  color: _azulOscuro,
                  borderRadius:
                      pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  'TOTAL: ${_money(total)}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
            ],
          ),

          // ------------------------------------------------ observaciones
          if (tieneObs) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Observaciones',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _grisTexto,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(obs, style: const pw.TextStyle(fontSize: 9)),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _dato(String etiqueta, String valor) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            '$etiqueta:',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _grisTexto,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(valor, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    );
  }

  /// Genera el PDF y abre el menú de compartir del sistema.
  /// El vendedor elige WhatsApp y el contacto; el PDF va adjunto.
  /// Devuelve false si algo falló.
  static Future<bool> compartir({
    required String empresaNombre,
    required String numeroPedido,
    required String fecha,
    required String vendedorNombre,
    required String clienteNombre,
    required String clienteDireccion,
    required List<LineaCompartir> lineas,
    required double total,
    String observaciones = '',
    String estado = '',
  }) async {
    try {
      final bytes = await generar(
        empresaNombre: empresaNombre,
        numeroPedido: numeroPedido,
        fecha: fecha,
        vendedorNombre: vendedorNombre,
        clienteNombre: clienteNombre,
        clienteDireccion: clienteDireccion,
        lineas: lineas,
        total: total,
        observaciones: observaciones,
        estado: estado,
      );
      final nombreArchivo =
          'pedido_${numeroPedido.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
      return true;
    } catch (_) {
      return false;
    }
  }
}
