import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/sync/catalog_sync_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cobros/presentation/screens/cobro_crear_screen.dart';
import '../../data/datasources/cliente_remote_datasource.dart';

/// Tarjeta de "Cuenta por cobrar" del cliente.
///
/// Consulta SOLO LECTURA al endpoint /clientes/:id/cxc, que replica la
/// lógica de VIEW_CtasxCobrar del sistema de escritorio: el saldo que ve
/// el vendedor es el mismo que ve la oficina.
///
/// Sin conexión, la tarjeta cae a la última foto de CxC sincronizada por
/// el caché de catálogos (máx. 24 h) y lo dice con claridad: "saldo al
/// {fecha}". Desde ahí también se puede registrar el cobro, que quedará
/// guardado en el teléfono hasta recuperar señal.
class ClienteCxcCard extends StatefulWidget {
  final int uidCliente;
  final String nombreCliente;
  const ClienteCxcCard(
      {super.key, required this.uidCliente, this.nombreCliente = ''});

  @override
  State<ClienteCxcCard> createState() => _ClienteCxcCardState();
}

class _ClienteCxcCardState extends State<ClienteCxcCard> {
  final _datasource = ClientesRemoteDatasource();
  final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _fecha = DateFormat('dd/MM/yyyy');

  bool _cargando = true;
  bool _fallo = false;
  bool _expandido = false;
  Map<String, dynamic>? _data;

  /// true cuando los datos vienen del caché local (sin conexión).
  bool _deCache = false;
  DateTime? _fechaCache;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = false;
      _deCache = false;
    });
    try {
      final data = await _datasource.getCuentasPorCobrar(widget.uidCliente);
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
      });
    } catch (_) {
      // Sin conexión: última foto de CxC del sync de catálogos (máx. 24 h).
      final sync = CatalogSyncService.instance;
      if (sync.cxcVigente) {
        try {
          final docs = await sync.cxcLocalCliente(widget.uidCliente);
          if (!mounted) return;
          setState(() {
            _data = _armarDesdeCache(docs);
            _deCache = true;
            _fechaCache = sync.ultimaSyncCxc;
            _cargando = false;
          });
          return;
        } catch (_) {/* cae al fallo normal */}
      }
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _fallo = true;
      });
    }
  }

  /// Reconstruye la misma respuesta de /clientes/:id/cxc a partir de las
  /// filas cacheadas (mismas llaves; sin historial de pagados).
  Map<String, dynamic> _armarDesdeCache(List<Map<String, dynamic>> docs) {
    double total = 0;
    var vencidos = 0;
    double montoVencido = 0;
    for (final d in docs) {
      final signo = _d(d['ValorCxC']);
      final saldo = _d(d['SaldoActual']);
      total += saldo * (signo < 0 ? -1 : 1);
      final dias = (d['dias_vencido'] as num?)?.toInt() ?? 0;
      if (signo > 0 && dias > 0) {
        vencidos++;
        montoVencido += saldo;
      }
    }
    double r2(double v) => (v * 100).roundToDouble() / 100;
    return {
      'uid_cliente': widget.uidCliente,
      'total_deuda': r2(total),
      'total_documentos': docs.length,
      'documentos_vencidos': vencidos,
      'monto_vencido': r2(montoVencido),
      'documentos': docs,
      'ultimos_pagados': const [],
    };
  }

  double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

  String _fechaTexto(dynamic iso) {
    if (iso == null) return '';
    final f = DateTime.tryParse(iso.toString());
    return f == null ? '' : _fecha.format(f);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return _contenedor(
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primary),
            ),
            SizedBox(width: 12),
            Text('Consultando cuenta por cobrar...',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    // Sin conexión o error: no mostramos nada para no confundir al vendedor
    // con una deuda "en cero" que en realidad no se pudo consultar.
    if (_fallo) {
      return _contenedor(
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppTheme.textSecondary, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('No se pudo consultar la deuda',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
            TextButton(
              onPressed: _cargar,
              child: const Text('Reintentar',
                  style: TextStyle(color: AppTheme.primary, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    final total = _d(data['total_deuda']);
    final docs = (data['documentos'] as List?) ?? const [];
    final vencidos = (data['documentos_vencidos'] as num?)?.toInt() ?? 0;
    final montoVencido = _d(data['monto_vencido']);

    // Cliente solvente: check verde + historial de pagos desplegable
    if (docs.isEmpty || total <= 0) {
      final pagados = (data['ultimos_pagados'] as List?) ?? const [];
      return _contenedor(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_deCache) ...[_bannerCache(), const SizedBox(height: 8)],
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      _deCache
                          ? 'Sin deuda pendiente (al último saldo sincronizado)'
                          : 'Sin deuda pendiente',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
                if (total < 0)
                  Text('Saldo a favor ${_money.format(total.abs())}',
                      style: const TextStyle(
                          color: AppTheme.accent, fontSize: 12)),
              ],
            ),
            if (pagados.isNotEmpty) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => setState(() => _expandido = !_expandido),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(
                        _expandido
                            ? 'Ocultar pagos'
                            : 'Ver últimos pagos (${pagados.length})',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      Icon(
                        _expandido
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expandido) ...[
                const Divider(color: AppTheme.divider, height: 12),
                ...pagados.map((d) => _filaPagado(d as Map)),
              ],
            ],
          ],
        ),
      );
    }

    final hayVencidos = vencidos > 0;
    final color = hayVencidos ? AppTheme.error : AppTheme.warning;

    return _contenedor(
      borde: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_deCache) ...[_bannerCache(), const SizedBox(height: 10)],
          Row(
            children: [
              const Text(
                'CUENTA POR COBRAR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.refresh_rounded,
                    size: 18, color: AppTheme.textSecondary),
                onPressed: _cargar,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money.format(total),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${docs.length} ${docs.length == 1 ? 'documento' : 'documentos'}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          if (hayVencidos) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.error, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '$vencidos ${vencidos == 1 ? 'vencido' : 'vencidos'} - ${_money.format(montoVencido)}',
                    style: const TextStyle(
                        color: AppTheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    _expandido ? 'Ocultar detalle' : 'Ver detalle',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  Icon(
                    _expandido
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expandido) ...[
            const Divider(color: AppTheme.divider, height: 12),
            ...docs.map((d) => _fila(d as Map)),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => _abrirCobro(docs),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.point_of_sale_rounded, size: 18),
              label: const Text('Registrar cobro',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre el registro de cobro con los documentos que el vendedor puede
  /// cobrar: solo los que suman deuda (ValorCxC > 0) y tienen saldo.
  Future<void> _abrirCobro(List docs) async {
    final cobrables = docs
        .map((d) => Map<String, dynamic>.from(d as Map))
        .where((d) => _d(d['ValorCxC']) > 0 && _d(d['SaldoActual']) > 0)
        .toList();
    if (cobrables.isEmpty) return;

    final registrado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CobroCrearScreen(
          uidCliente: widget.uidCliente,
          nombreCliente: widget.nombreCliente,
          documentos: cobrables,
          saldosDe: _deCache ? _fechaCache : null,
        ),
      ),
    );
    if (registrado == true) _cargar();
  }

  Widget _bannerCache() {
    final f = DateFormat('dd/MM HH:mm');
    final fecha = _fechaCache == null ? '' : f.format(_fechaCache!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppTheme.warning, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Sin conexión — saldo al $fecha',
              style: const TextStyle(
                  color: AppTheme.warning,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(Map d) {
    final saldo = _d(d['SaldoActual']);
    final signo = _d(d['ValorCxC']);
    final dias = (d['dias_vencido'] as num?)?.toInt() ?? 0;
    final vencido = signo > 0 && dias > 0;
    final abonado = _d(d['MontoAbonado']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d['Abreviatura'] ?? ''} ${d['iddoc'] ?? ''}'.trim(),
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Emitido ${_fechaTexto(d['FechaEmision'])}'
                  '${_fechaTexto(d['FechaVencimiento']).isEmpty ? '' : ' - vence ${_fechaTexto(d['FechaVencimiento'])}'}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
                if (vencido)
                  Text(
                    'Vencido hace $dias ${dias == 1 ? 'día' : 'días'}',
                    style: const TextStyle(
                        color: AppTheme.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                if (abonado > 0)
                  Text(
                    'Abonado ${_money.format(abonado)}',
                    style: const TextStyle(
                        color: AppTheme.accent, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money.format(saldo * (signo < 0 ? -1 : 1)),
            style: TextStyle(
              color: signo < 0
                  ? AppTheme.accent
                  : (vencido ? AppTheme.error : AppTheme.textPrimary),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaPagado(Map d) {
    final monto = _d(d['MontoAbonado']) > 0
        ? _d(d['MontoAbonado'])
        : _d(d['MontoOriginal']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d['Abreviatura'] ?? ''} ${d['iddoc'] ?? ''}'.trim(),
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Emitido ${_fechaTexto(d['FechaEmision'])}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money.format(monto),
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Pagado',
                style: TextStyle(color: AppTheme.accent, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contenedor({required Widget child, Color? borde}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borde ?? AppTheme.divider,
          width: borde == null ? 0.5 : 1,
        ),
      ),
      child: child,
    );
  }
}
