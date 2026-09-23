import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/sync/cobros_outbox_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../data/datasources/cobro_remote_datasource.dart';
import '../../data/models/cobro_local_model.dart';
import 'cobro_crear_screen.dart' show compartirReciboLocal;
import 'cobro_detalle_screen.dart';

/// Historial de cobranza de los clientes del vendedor.
///
/// Lista fusionada, igual que pedidos: arriba las tarjetas LOCALES
/// (pendientes de envío en naranja, rechazadas por el servidor en rojo)
/// y debajo el historial del servidor. Sin conexión se muestran las
/// locales aunque el historial remoto no cargue.
class CobrosScreen extends StatefulWidget {
  const CobrosScreen({super.key});

  @override
  State<CobrosScreen> createState() => _CobrosScreenState();
}

class _CobrosScreenState extends State<CobrosScreen> {
  final _datasource = CobrosRemoteDatasource();
  final _outbox = CobrosOutboxService.instance;
  final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _fecha = DateFormat('dd/MM/yyyy');
  final _fechaHora = DateFormat('dd/MM HH:mm');

  bool _cargando = true;
  String? _error;
  String? _status; // null = todos, 02, 06, 99
  List<Map<String, dynamic>> _cobros = [];
  List<CobroLocal> _locales = [];

  @override
  void initState() {
    super.initState();
    _outbox.addListener(_alCambiarOutbox);
    _cargar();
  }

  @override
  void dispose() {
    _outbox.removeListener(_alCambiarOutbox);
    super.dispose();
  }

  void _alCambiarOutbox() => _cargarLocales();

  Future<void> _cargarLocales() async {
    final locales = await _outbox.listarVisibles();
    if (!mounted) return;
    setState(() => _locales = locales);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    await _cargarLocales();
    try {
      final lista = await _datasource.getCobros(status: _status);
      if (!mounted) return;
      setState(() {
        _cobros = lista;
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

  void _cambiarFiltro(String? status) {
    if (_status == status) return;
    setState(() => _status = status);
    _cargar();
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

  /// Locales visibles según el filtro: pendientes van con "Todos" y
  /// "En proceso"; rechazadas siempre en "Todos" (exigen atención).
  List<CobroLocal> get _localesFiltradas {
    if (_status == null) return _locales;
    if (_status == '02') return _locales.where((c) => c.pendiente).toList();
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Cobranza'),
      ),
      body: Column(
        children: [
          _filtros(),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _filtros() {
    Widget chip(String label, String? value) {
      final activo = _status == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: activo,
          onSelected: (_) => _cambiarFiltro(value),
          selectedColor: AppTheme.primary.withOpacity(0.25),
          backgroundColor: AppTheme.surface,
          labelStyle: TextStyle(
            color: activo ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
              color: activo ? AppTheme.primary : AppTheme.divider),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          chip('Todos', null),
          chip('En proceso', '02'),
          chip('Confirmados', '06'),
          chip('Anulados', '99'),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final locales = _localesFiltradas;

    // Falló el remoto pero hay tarjetas locales: se muestran igual, con un
    // aviso arriba para reintentar la carga del historial.
    if (_error != null && locales.isEmpty) {
      return ErrorDisplay(message: _error!, onRetry: _cargar);
    }
    if (_error == null && _cobros.isEmpty && locales.isEmpty) {
      return const EmptyState(
        icon: Icons.request_quote_outlined,
        message: 'No hay cobros registrados con este filtro',
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) _avisoRemoto(),
          ...locales.map(_tarjetaLocal),
          ..._cobros.map(_tarjeta),
        ],
      ),
    );
  }

  Widget _avisoRemoto() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Sin conexión: mostrando solo los cobros del teléfono',
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
          TextButton(
            onPressed: _cargar,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Reintentar',
                style: TextStyle(color: AppTheme.primary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ tarjeta LOCAL

  Widget _tarjetaLocal(CobroLocal c) {
    final color = c.rechazado ? AppTheme.error : AppTheme.warning;
    final etiqueta = c.rechazado ? 'RECHAZADO' : 'POR ENVIAR';

    return GestureDetector(
      onTap: () => _abrirLocal(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          c.rechazado
                              ? Icons.error_outline_rounded
                              : Icons.schedule_send_rounded,
                          color: color,
                          size: 15),
                      const SizedBox(width: 6),
                      Text('Cobro en el teléfono',
                          style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(c.clienteNombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(_fechaHora.format(c.fecreg),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                  if (c.rechazado && (c.ultimoError ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(c.ultimoError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: color, fontSize: 11)),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_money.format(c.total),
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(etiqueta,
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirLocal(CobroLocal c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CobroLocalSheet(
        cobro: c,
        onReintentar: c.rechazado
            ? () async {
                Navigator.pop(context);
                await _outbox.reintentar(c.uuid);
              }
            : null,
        onDescartar: () async {
          Navigator.pop(context);
          final ok = await _confirmarDescarte(c);
          if (ok == true) await _outbox.descartar(c.uuid);
        },
        onCompartir: c.rechazado
            ? null
            : () async {
                Navigator.pop(context);
                await compartirReciboLocal(context, c);
              },
      ),
    );
    _cargarLocales();
  }

  Future<bool?> _confirmarDescarte(CobroLocal c) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Descartar cobro',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: Text(
          c.rechazado
              ? 'Este cobro fue RECHAZADO por el servidor pero el dinero ya '
                  'se recibió del cliente. Al descartarlo, debe resolverlo '
                  'directamente con la oficina.\n\n¿Descartar de todas formas?'
              : 'El cobro aún no se ha enviado al servidor. Si lo descarta, '
                  'se pierde y no quedará registrado.\n\n¿Descartar?',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------- tarjeta SERVIDOR

  Widget _tarjeta(Map<String, dynamic> c) {
    final status = '${c['status'] ?? ''}';
    final color = _colorStatus(status);
    final esApp = '${c['workstation'] ?? ''}'.trim() == 'APP-MOVIL';
    final nombre = '${c['str_cliente_nombres'] ?? ''}'.trim();

    return GestureDetector(
      onTap: () async {
        final cambio = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => CobroDetalleScreen(numpago: '${c['numpago']}'),
          ),
        );
        if (cambio == true) _cargar();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: status == '02'
              ? Border.all(color: color.withOpacity(0.5))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Nro. ${c['numpago']}',
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      if (esApp) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.smartphone_rounded,
                            color: AppTheme.primary, size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(_fechaTexto(c['fecha']),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_money.format(_d(c['monto'])),
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${c['status_desc'] ?? status}',
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Detalle de un cobro local (bottom sheet)
// =====================================================================
class _CobroLocalSheet extends StatelessWidget {
  final CobroLocal cobro;
  final Future<void> Function()? onReintentar;
  final Future<void> Function() onDescartar;
  final Future<void> Function()? onCompartir;

  const _CobroLocalSheet({
    required this.cobro,
    required this.onDescartar,
    this.onReintentar,
    this.onCompartir,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final color = cobro.rechazado ? AppTheme.error : AppTheme.warning;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                  cobro.rechazado
                      ? Icons.error_outline_rounded
                      : Icons.schedule_send_rounded,
                  color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cobro.rechazado
                      ? 'Cobro rechazado por el servidor'
                      : 'Cobro pendiente de envío',
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Text(money.format(cobro.total),
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(cobro.clienteNombre,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          if (cobro.rechazado && (cobro.ultimoError ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Motivo: ${cobro.ultimoError}\n\n'
                'El dinero ya se recibió del cliente. Revise la deuda '
                'actualizada y reintente, o resuélvalo con la oficina.',
                style: const TextStyle(color: AppTheme.error, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 10),
          ...cobro.documentosResumen.map((d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${d['Abreviatura'] ?? d['tipodoc']} ${d['iddoc']}',
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13)),
                    ),
                    Text(
                        money.format(
                            double.tryParse('${d['monto'] ?? 0}') ?? 0),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13)),
                  ],
                ),
              )),
          const SizedBox(height: 6),
          ...cobro.formasResumen.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          [
                            '${f['forma_pago'] ?? f['codformapago']}',
                            if ('${f['referencia'] ?? ''}'.isNotEmpty)
                              '${f['referencia']}',
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ),
                    Text(
                        money.format(
                            double.tryParse('${f['monto'] ?? 0}') ?? 0),
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          Row(
            children: [
              if (onReintentar != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onReintentar!(),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Reintentar'),
                  ),
                ),
              if (onCompartir != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onCompartir!(),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Enviar recibo'),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onDescartar(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Descartar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
