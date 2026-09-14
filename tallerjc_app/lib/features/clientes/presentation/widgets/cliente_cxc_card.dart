import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/cliente_remote_datasource.dart';

/// Tarjeta de "Cuenta por cobrar" del cliente.
///
/// Consulta SOLO LECTURA al endpoint /clientes/:id/cxc, que replica la
/// lógica de VIEW_CtasxCobrar del sistema de escritorio: el saldo que ve
/// el vendedor es el mismo que ve la oficina.
///
/// Si no hay conexión o el endpoint falla, la tarjeta se oculta sin
/// romper el resto del detalle del cliente (la app sigue siendo offline
/// first: la deuda simplemente no se muestra).
class ClienteCxcCard extends StatefulWidget {
  final int uidCliente;
  const ClienteCxcCard({super.key, required this.uidCliente});

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

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = false;
    });
    try {
      final data = await _datasource.getCuentasPorCobrar(widget.uidCliente);
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _fallo = true;
      });
    }
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
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Sin deuda pendiente',
                      style: TextStyle(
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
