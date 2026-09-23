import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Genera el "Recibo de Cobro" en PDF y lo comparte por el menú del
/// sistema (WhatsApp, correo, etc.). Mismo estilo de la Nota de Pedido.
///
/// El recibo de un cobro EN PROCESO lleva una franja naranja bien visible
/// de "SUJETO A CONFIRMACIÓN": es la constancia que el vendedor le deja
/// al cliente mientras la oficina verifica que el pago llegó. No es un
/// documento fiscal y así lo dice al pie.
class CobroPdf {
  CobroPdf._();

  // Colores corporativos (mismos de la Nota de Pedido)
  static const _azul = PdfColor.fromInt(0xFF1565C0);
  static const _azulOscuro = PdfColor.fromInt(0xFF0D1B2A);
  static const _grisTexto = PdfColor.fromInt(0xFF455A64);
  static const _grisFondo = PdfColor.fromInt(0xFFECEFF1);
  static const _grisLinea = PdfColor.fromInt(0xFFCFD8DC);
  static const _naranja = PdfColor.fromInt(0xFFE65100);
  static const _naranjaFondo = PdfColor.fromInt(0xFFFFF3E0);
  static const _verde = PdfColor.fromInt(0xFF2E7D32);
  static const _verdeFondo = PdfColor.fromInt(0xFFE8F5E9);
  static const _rojo = PdfColor.fromInt(0xFFC62828);
  static const _rojoFondo = PdfColor.fromInt(0xFFFFEBEE);

  static String _money(double n) => '\$${n.toStringAsFixed(2)}';

  static String _bs(double n) {
    // 101680.5 -> "101.680,50" (formato venezolano, sin depender de intl)
    final partes = n.toStringAsFixed(2).split('.');
    final entero = partes[0];
    final b = StringBuffer();
    for (var i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) b.write('.');
      b.write(entero[i]);
    }
    return 'Bs. $b,${partes[1]}';
  }

  static double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

  /// Construye el documento y devuelve los bytes del PDF.
  ///
  /// [status]: '02' en proceso, '06' confirmado, '99' anulado.
  /// [documentos]: mapas del detalle del cobro (Abreviatura, iddoc, monto,
  /// FechaEmision opcional). [formas]: mapas (forma_pago, banco, referencia,
  /// cambio, montobs, monto).
  static Future<Uint8List> generar({
    required String empresaNombre,
    required String numeroCobro,
    required String fecha,
    required String status,
    required String vendedorNombre,
    required String clienteNombre,
    required String clienteDireccion,
    required List<Map<String, dynamic>> documentos,
    required List<Map<String, dynamic>> formas,
    required double total,
  }) async {
    final doc = pw.Document();

    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    final generado =
        '${dos(ahora.day)}/${dos(ahora.month)}/${ahora.year} ${dos(ahora.hour)}:${dos(ahora.minute)}';

    // Franja de estado
    final PdfColor colorEstado;
    final PdfColor fondoEstado;
    final String textoEstado;
    switch (status) {
      case 'LOCAL':
        colorEstado = _naranja;
        fondoEstado = _naranjaFondo;
        textoEstado = 'PENDIENTE DE ENVIO - SIN CONEXION';
        break;
      case '06':
        colorEstado = _verde;
        fondoEstado = _verdeFondo;
        textoEstado = 'COBRO CONFIRMADO';
        break;
      case '99':
        colorEstado = _rojo;
        fondoEstado = _rojoFondo;
        textoEstado = 'COBRO ANULADO';
        break;
      default:
        colorEstado = _naranja;
        fondoEstado = _naranjaFondo;
        textoEstado = 'EN PROCESO - SUJETO A CONFIRMACION';
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
          buildBackground: (ctx) => pw.Watermark.text(
            status == 'LOCAL'
                ? 'PENDIENTE'
                : status == '02'
                    ? 'EN PROCESO'
                    : empresaNombre.toUpperCase(),
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
            pw.Text(
              'Este recibo no es un documento fiscal. Constancia de cobro '
              'registrada por el vendedor; el comprobante definitivo lo emite la oficina.',
              style: const pw.TextStyle(fontSize: 7, color: _grisTexto),
            ),
            pw.SizedBox(height: 2),
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
            padding:
                const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
                      'RECIBO DE COBRO',
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
                      'N. $numeroCobro',
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
          pw.SizedBox(height: 8),

          // ----------------------------------------------- franja de estado
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 12),
            decoration: pw.BoxDecoration(
              color: fondoEstado,
              border: pw.Border.all(color: colorEstado, width: 1),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              textoEstado,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: colorEstado,
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

          // ------------------------------------------ documentos abonados
          pw.Text(
            'DOCUMENTOS ABONADOS',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _grisTexto,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Documento', 'Emision', 'Abono'],
            data: [
              for (final d in documentos)
                [
                  '${d['Abreviatura'] ?? d['tipodoc']} ${d['iddoc']}',
                  _fechaCorta(d['FechaEmision']),
                  _money(_d(d['monto'])),
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
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(2.4),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(1.2),
            },
          ),
          pw.SizedBox(height: 12),

          // ---------------------------------------------- formas de pago
          pw.Text(
            'FORMAS DE PAGO',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _grisTexto,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Forma', 'Detalle', 'Monto'],
            data: [
              for (final f in formas)
                [
                  '${f['forma_pago'] ?? f['codformapago']}',
                  _detalleForma(f),
                  _money(_d(f['monto'])),
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
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(1.6),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.1),
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
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  'TOTAL COBRADO: ${_money(total)}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
            ],
          ),

          if (status == '02') ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'La oficina verificara la recepcion del pago. Una vez '
              'confirmado, este cobro sera aplicado a la cuenta del cliente.',
              style: const pw.TextStyle(fontSize: 8, color: _grisTexto),
            ),
          ],
          if (status == 'LOCAL') ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Cobro registrado sin conexion: se enviara al sistema al '
              'recuperar la senal y recibira su numero. Luego la oficina '
              'verificara la recepcion del pago para confirmarlo.',
              style: const pw.TextStyle(fontSize: 8, color: _grisTexto),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static String _fechaCorta(dynamic iso) {
    final f = DateTime.tryParse('${iso ?? ''}');
    if (f == null) return '';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year}';
  }

  /// "BANCO PROVINCIAL - PM BANESCO 123456 - Bs. 32.800,00 @ 820,00"
  static String _detalleForma(Map<String, dynamic> f) {
    final partes = <String>[];
    if (f['banco'] != null) partes.add('${f['banco']}');
    if (f['referencia'] != null) partes.add('${f['referencia']}');
    final bs = _d(f['montobs']);
    final tasa = _d(f['cambio']);
    if (bs > 0 && tasa > 0) {
      partes.add('${_bs(bs)} @ ${tasa.toStringAsFixed(2)}');
    }
    return partes.isEmpty ? '-' : partes.join('  -  ');
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
  /// Devuelve false si algo falló.
  static Future<bool> compartir({
    required String empresaNombre,
    required String numeroCobro,
    required String fecha,
    required String status,
    required String vendedorNombre,
    required String clienteNombre,
    required String clienteDireccion,
    required List<Map<String, dynamic>> documentos,
    required List<Map<String, dynamic>> formas,
    required double total,
  }) async {
    try {
      final bytes = await generar(
        empresaNombre: empresaNombre,
        numeroCobro: numeroCobro,
        fecha: fecha,
        status: status,
        vendedorNombre: vendedorNombre,
        clienteNombre: clienteNombre,
        clienteDireccion: clienteDireccion,
        documentos: documentos,
        formas: formas,
        total: total,
      );
      final nombreArchivo =
          'recibo_${numeroCobro.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
      return true;
    } catch (_) {
      return false;
    }
  }
}
