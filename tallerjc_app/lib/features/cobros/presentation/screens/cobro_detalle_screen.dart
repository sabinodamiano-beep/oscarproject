import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/cobro_remote_datasource.dart';
import '../utils/cobro_pdf.dart';

/// Detalle de un cobro: documentos abonados y formas de pago.
/// Los cobros de la app EN PROCESO se pueden anular desde aquí.
class CobroDetalleScreen extends StatefulWidget {
  final String numpago;
  const CobroDetalleScreen({super.key, required this.numpago});

  @override
  State<CobroDetalleScreen> createState() => _CobroDetalleScreenState();
}

class _CobroDetalleScreenState extends State<CobroDetalleScreen> {
  final _datasource = CobrosRemoteDatasource();
  final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _bs = NumberFormat('#,##0.00', 'es_VE');
  final _fecha = DateFormat('dd/MM/yyyy');

  bool _cargando = true;
  bool _anulando = false;
  bool _compartiendo = false;
  bool _huboCambios = false;
  String? _error;
  Map<String, dynamic>? _cobro;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await _datasource.getCobroDetalle(widget.numpago);
      if (!mounted) return;
      setState(() {
        _cobro = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

  String _fechaTexto(dynamic iso) {
    final f = DateTime.tryParse('${iso ?? ''}');
    return f == null ? '' : _fecha.format(f);
  }

  Color _colorStatus(String status) {
    switch (status) {
      case '02':
        return AppTheme.warning;
      case '06':
        return AppTheme.accent;
      case '99':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  bool get _puedeAnular {
    final c = _cobro;
    if (c == null) return false;
    return '${c['status']}' == '02' &&
        '${c['workstation'] ?? ''}'.trim() == 'APP-MOVIL';
  }

  Future<void> _compartirRecibo() async {
    final c = _cobro;
    if (c == null || _compartiendo) return;
    setState(() => _compartiendo = true);
    try {
      final auth = context.read<AuthProvider>();
      final empresaNombre = await auth.getEmpresaNombre();
      final docs = ((c['documentos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final formas = ((c['formas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final ok = await CobroPdf.compartir(
        empresaNombre: empresaNombre,
        numeroCobro: '${c['numpago']}',
        fecha: _fechaTexto(c['fecha']),
        status: '${c['status']}',
        vendedorNombre: auth.vendedor?.nombreCompleto ?? '',
        clienteNombre: '${c['str_cliente_nombres'] ?? ''}'.trim(),
        clienteDireccion: '${c['str_cliente_direccion'] ?? ''}'.trim(),
        documentos: docs,
        formas: formas,
        total: _d(c['monto']),
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo generar el recibo'),
          backgroundColor: AppTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  Future<void> _anular() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Anular cobro',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: const Text(
          '¿Seguro que desea anular este cobro? Esta acción no se puede deshacer.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Anular', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _anulando = true);
    try {
      await _datasource.anularCobro(widget.numpago,
          motivo: 'Anulado por el vendedor desde la app');
      _huboCambios = true;
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cobro anulado'),
        backgroundColor: AppTheme.surface,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppTheme.error,
      ));
    } finally {
      if (mounted) setState(() => _anulando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _huboCambios);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          title: Text('Cobro ${widget.numpago}'),
          actions: [
            if (_cobro != null && '${_cobro!['status']}' != '99')
              IconButton(
                tooltip: 'Compartir recibo',
                icon: _compartiendo
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primary))
                    : const Icon(Icons.share_rounded),
                onPressed: _compartiendo ? null : _compartirRecibo,
              ),
          ],
        ),
        body: _cargando
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary))
            : _error != null
                ? ErrorDisplay(message: _error!, onRetry: _cargar)
                : _detalle(),
      ),
    );
  }

  Widget _detalle() {
    final c = _cobro!;
    final status = '${c['status']}';
    final color = _colorStatus(status);
    final docs = ((c['documentos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final formas = ((c['formas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- Encabezado ----------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${c['str_cliente_nombres'] ?? ''}'.trim(),
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${c['status_desc'] ?? status}',
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(_money.format(_d(c['monto'])),
                    style: TextStyle(
                        color: color,
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Fecha: ${_fechaTexto(c['fecha'])}'
                  '${'${c['status']}' == '06' && c['fecha_cierre'] != null ? '  ·  Confirmado: ${_fechaTexto(c['fecha_cierre'])}' : ''}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
                if (status == '02') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Pendiente de verificación en la oficina',
                    style: TextStyle(color: AppTheme.warning, fontSize: 12),
                  ),
                ],
                if (status == '99' && c['desanul'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Motivo: ${c['desanul']}',
                      style: const TextStyle(
                          color: AppTheme.error, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---------- Documentos ----------
          _titulo('DOCUMENTOS ABONADOS'),
          const SizedBox(height: 8),
          ...docs.map((d) => _filaDoc(d)),
          const SizedBox(height: 16),

          // ---------- Formas de pago ----------
          _titulo('FORMAS DE PAGO'),
          const SizedBox(height: 8),
          ...formas.map((f) => _filaForma(f)),

          if (_puedeAnular) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _anulando ? null : _anular,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _anulando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.error))
                    : const Icon(Icons.cancel_outlined, size: 20),
                label: const Text('Anular cobro'),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _titulo(String texto) => Text(
        texto,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
          letterSpacing: 1,
        ),
      );

  Widget _filaDoc(Map<String, dynamic> d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d['Abreviatura'] ?? d['tipodoc']} ${d['iddoc']}',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (d['FechaEmision'] != null)
                  Text('Emitido ${_fechaTexto(d['FechaEmision'])}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(_money.format(_d(d['monto'])),
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _filaForma(Map<String, dynamic> f) {
    final detalles = <String>[];
    if (f['banco'] != null) detalles.add('${f['banco']}');
    if (f['referencia'] != null) detalles.add('${f['referencia']}');
    final tieneBs = _d(f['montobs']) > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined,
              color: AppTheme.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${f['forma_pago'] ?? f['codformapago']}',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (detalles.isNotEmpty)
                  Text(detalles.join('  ·  '),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                if (tieneBs)
                  Text(
                      'Bs. ${_bs.format(_d(f['montobs']))} @ ${_bs.format(_d(f['cambio']))}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(_money.format(_d(f['monto'])),
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
