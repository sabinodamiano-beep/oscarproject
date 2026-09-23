import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/sync/catalog_sync_service.dart';
import '../../../../core/sync/cobros_outbox_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/cobro_remote_datasource.dart';
import '../../data/models/cobro_local_model.dart';
import '../utils/cobro_pdf.dart';

/// Registro de un cobro o abono en el sitio, contra los documentos
/// pendientes del cliente (los mismos de la tarjeta de CxC).
///
/// Reglas del negocio (definidas por Sabino):
/// - Pago móvil / tarjeta / efectivo Bs.: pagos en bolívares, exigen la
///   tasa del día. El vendedor ingresa el monto en Bs y la app calcula
///   el equivalente en dólares.
/// - Dólares (divisas): sin banco y sin tasa.
/// - Descuento: el vendedor puede otorgarlo SOLO cuando el cliente paga
///   en dólares. Participa del cuadre (como en el VB6).
/// - El cobro queda EN PROCESO hasta que la oficina lo confirme.
///
/// Desde v1.3.0 el registro funciona SIN CONEXIÓN: el cobro se guarda en
/// el teléfono (CobrosOutboxService) y se envía solo al recuperar señal.
/// Si [saldosDe] viene, los documentos salen del caché local y se muestra
/// de cuándo es esa foto de la deuda.
class CobroCrearScreen extends StatefulWidget {
  final int uidCliente;
  final String nombreCliente;

  /// Documentos con saldo del cliente (del endpoint /clientes/:id/cxc o,
  /// sin conexión, del caché de la última sincronización):
  /// tipodoc, iddoc, Abreviatura, SaldoActual, FechaVencimiento, dias_vencido
  final List<Map<String, dynamic>> documentos;

  /// Fecha de la última sincronización cuando los documentos vienen del
  /// caché local (null = consultados en línea ahora mismo).
  final DateTime? saldosDe;

  const CobroCrearScreen({
    super.key,
    required this.uidCliente,
    required this.nombreCliente,
    required this.documentos,
    this.saldosDe,
  });

  @override
  State<CobroCrearScreen> createState() => _CobroCrearScreenState();
}

class _FormaPago {
  final String codigo;
  final String nombre;
  final double montoUsd;
  final double? tasa;
  final double? montoBs;
  final String? codBancoDestino;
  final String? nombreBancoDestino;
  final String? bancoEmisor; // code del catálogo o texto libre
  final String? nombreBancoEmisor;
  final String? referenciaDigitos;
  final double? descuentoPct; // solo forma 05

  _FormaPago({
    required this.codigo,
    required this.nombre,
    required this.montoUsd,
    this.tasa,
    this.montoBs,
    this.codBancoDestino,
    this.nombreBancoDestino,
    this.bancoEmisor,
    this.nombreBancoEmisor,
    this.referenciaDigitos,
    this.descuentoPct,
  });

  bool get esBolivares => codigo == '01' || codigo == '02' || codigo == '04';
  bool get esDescuento => codigo == '05';
  bool get esDivisas => codigo == '03';
}

class _CobroCrearScreenState extends State<CobroCrearScreen> {
  final _datasource = CobrosRemoteDatasource();
  final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _bs = NumberFormat('#,##0.00', 'es_VE');

  /// UUID fijo de la pantalla: un reintento tras un fallo de red nunca
  /// duplica (es el client_uuid de la idempotencia en la API).
  final String _clientUuid = _generarUuidV4();

  bool _cargandoCatalogos = true;
  bool _falloCatalogos = false;
  bool _catalogosDeCache = false;
  bool _enviando = false;

  List<Map<String, dynamic>> _formasCatalogo = [];
  List<Map<String, dynamic>> _bancosCatalogo = [];

  /// tipodoc-iddoc -> monto a abonar (solo documentos seleccionados)
  final Map<String, double> _seleccionados = {};
  final Map<String, TextEditingController> _montoCtrl = {};

  final List<_FormaPago> _formas = [];
  double? _ultimaTasa; // se recuerda entre formas dentro del mismo cobro

  double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
  double _round2(double v) => (v * 100).roundToDouble() / 100;

  String _llave(Map d) => '${d['tipodoc']}-${d['iddoc']}';

  double get _totalDocumentos =>
      _round2(_seleccionados.values.fold(0.0, (s, m) => s + m));
  double get _totalFormas =>
      _round2(_formas.fold(0.0, (s, f) => s + f.montoUsd));
  double get _diferencia => _round2(_totalDocumentos - _totalFormas);
  bool get _cuadra =>
      _totalDocumentos > 0 && _diferencia.abs() < 0.01 && _formas.isNotEmpty;

  bool get _hayDivisas => _formas.any((f) => f.esDivisas && f.montoUsd > 0);
  bool get _todasMarcadas =>
      widget.documentos.isNotEmpty &&
      _seleccionados.length == widget.documentos.length;

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
  }

  @override
  void dispose() {
    for (final c in _montoCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Catálogos de formas de pago y bancos: primero en línea; si no hay
  /// señal, la última copia guardada por el sync de catálogos. Solo si
  /// tampoco hay copia local se bloquea el registro.
  Future<void> _cargarCatalogos() async {
    setState(() {
      _cargandoCatalogos = true;
      _falloCatalogos = false;
      _catalogosDeCache = false;
    });
    Map<String, dynamic>? data;
    var deCache = false;
    try {
      data = await _datasource.getCatalogos();
    } catch (_) {
      data = await CatalogSyncService.instance.catalogosCobrosLocales();
      deCache = data != null;
    }
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _cargandoCatalogos = false;
        _falloCatalogos = true;
      });
      return;
    }
    final cat = data;
    setState(() {
      _formasCatalogo = ((cat['formas_pago'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _bancosCatalogo = ((cat['bancos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _catalogosDeCache = deCache;
      _cargandoCatalogos = false;
    });
  }

  // ==================== DOCUMENTOS ====================

  void _toggleDocumento(Map<String, dynamic> d, bool marcar) {
    final llave = _llave(d);
    final saldo = _round2(_d(d['SaldoActual']));
    setState(() {
      if (marcar) {
        _seleccionados[llave] = saldo;
        _montoCtrl[llave] ??= TextEditingController();
        _montoCtrl[llave]!.text = saldo.toStringAsFixed(2);
      } else {
        _seleccionados.remove(llave);
      }
    });
  }

  /// "Marcar todas": el caso normal es que el cliente pague todo lo
  /// pendiente, así que un toque selecciona (o limpia) todos los
  /// documentos con su saldo completo.
  void _marcarTodas(bool marcar) {
    setState(() {
      if (!marcar) {
        _seleccionados.clear();
        return;
      }
      for (final d in widget.documentos) {
        final llave = _llave(d);
        final saldo = _round2(_d(d['SaldoActual']));
        _seleccionados[llave] = saldo;
        _montoCtrl[llave] ??= TextEditingController();
        _montoCtrl[llave]!.text = saldo.toStringAsFixed(2);
      }
    });
  }

  void _cambiarMonto(Map<String, dynamic> d, String texto) {
    final llave = _llave(d);
    if (!_seleccionados.containsKey(llave)) return;
    final saldo = _round2(_d(d['SaldoActual']));
    var monto = _round2(double.tryParse(texto.replaceAll(',', '.')) ?? 0);
    if (monto > saldo) monto = saldo;
    setState(() => _seleccionados[llave] = monto);
  }

  // ==================== ENVÍO ====================

  /// Documentos seleccionados como los espera la API, junto con los datos
  /// que el recibo local necesita (Abreviatura, FechaEmision).
  List<Map<String, dynamic>> _docsSeleccionados() {
    final docs = <Map<String, dynamic>>[];
    for (final d in widget.documentos) {
      final monto = _seleccionados[_llave(d)];
      if (monto == null || monto <= 0) continue;
      docs.add({
        'tipodoc': '${d['tipodoc']}',
        'iddoc': '${d['iddoc']}',
        'monto': monto,
        'Abreviatura': '${d['Abreviatura'] ?? d['tipodoc']}',
        'FechaEmision': '${d['FechaEmision'] ?? ''}',
      });
    }
    return docs;
  }

  Future<void> _enviar() async {
    if (_enviando || !_cuadra) return;

    final docs = _docsSeleccionados();
    if (docs.isEmpty) return;
    final primerIddoc = '${docs.first['iddoc']}';

    // --- Body exacto de POST /cobros
    final formasApi = _formas.map((f) {
      final m = <String, dynamic>{'codformapago': f.codigo};
      if (f.esBolivares) {
        m['montobs'] = f.montoBs;
        m['cambio'] = f.tasa;
        if (f.codBancoDestino != null) m['codbanco'] = f.codBancoDestino;
        if (f.codigo == '02') {
          m['banco_emisor'] = f.bancoEmisor;
          m['referencia_digitos'] = f.referenciaDigitos;
        }
      } else {
        m['monto'] = f.montoUsd;
        if (f.esDescuento && f.descuentoPct != null && f.descuentoPct! > 0) {
          m['descuento_pct'] = f.descuentoPct;
        }
      }
      return m;
    }).toList();

    final payload = {
      'uid_cliente': widget.uidCliente,
      'client_uuid': _clientUuid,
      'documentos': docs
          .map((d) => {
                'tipodoc': d['tipodoc'],
                'iddoc': d['iddoc'],
                'monto': d['monto'],
              })
          .toList(),
      'formas': formasApi,
    };

    // --- Resumen para la tarjeta local y el recibo sin conexión, con las
    // MISMAS llaves que devuelve GET /cobros/:id (así CobroPdf sirve igual).
    final resumen = {
      'documentos': docs,
      'formas': _formas
          .map((f) => {
                'codformapago': f.codigo,
                'forma_pago': f.nombre,
                'monto': f.montoUsd,
                'cambio': f.tasa,
                'montobs': f.montoBs,
                'banco': f.codigo == '02'
                    ? (f.nombreBancoEmisor ?? f.bancoEmisor)
                    : f.nombreBancoDestino,
                'referencia': _referenciaDisplay(f, primerIddoc),
              })
          .toList(),
    };

    final cobro = CobroLocal(
      uuid: _clientUuid,
      uidVendedor:
          context.read<AuthProvider>().vendedor?.uidVendedor ?? '',
      uidCliente: widget.uidCliente,
      clienteNombre: widget.nombreCliente,
      payload: payload,
      resumen: resumen,
      total: _totalDocumentos,
      fecreg: DateTime.now(),
      fecmod: DateTime.now(),
    );

    setState(() => _enviando = true);
    try {
      final r = await CobrosOutboxService.instance.encolar(cobro);
      if (!mounted) return;
      if (r.enviado) {
        await _dialogoEnviado(r.cobro);
      } else {
        await _dialogoPendiente(r.cobro);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ServerException catch (e) {
      // La API rechazó el cobro con el vendedor en pantalla: corrige y reenvía.
      _error(e.message);
    } catch (e) {
      _error(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _referenciaDisplay(_FormaPago f, String primerIddoc) {
    if (f.codigo == '02') {
      return 'PM ${f.nombreBancoDestino ?? ''} ${f.referenciaDigitos ?? ''}'
          .trim();
    }
    if (f.esDescuento) {
      final pct = f.descuentoPct;
      return pct != null && pct > 0
          ? 'DSCTO.% ${_sinCerosFinales(pct)} # $primerIddoc'
          : 'DSCTO. # $primerIddoc';
    }
    return '';
  }

  Future<void> _dialogoEnviado(CobroLocal c) async {
    final compartir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.accent),
            SizedBox(width: 10),
            Text('Cobro registrado',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
          ],
        ),
        content: Text(
          'Cobro Nro. ${c.numpago} por ${_money.format(c.total)}.\n\n'
          'Quedó EN PROCESO: la oficina verificará el pago y lo confirmará.',
          style:
              const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Listo',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.share_rounded,
                color: AppTheme.primary, size: 18),
            label: const Text('Enviar recibo',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
    if (compartir == true && mounted) {
      await _compartirReciboServidor('${c.numpago}', c);
    }
  }

  Future<void> _dialogoPendiente(CobroLocal c) async {
    final compartir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: AppTheme.warning),
            SizedBox(width: 10),
            Expanded(
              child: Text('Cobro guardado',
                  style:
                      TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
            ),
          ],
        ),
        content: Text(
          'No hay señal. El cobro por ${_money.format(c.total)} quedó '
          'guardado en el teléfono y se enviará solo al recuperar '
          'conexión.\n\nPuede seguirlo en Cobranza (tarjeta naranja).',
          style:
              const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Listo',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.share_rounded,
                color: AppTheme.primary, size: 18),
            label: const Text('Enviar recibo',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
    if (compartir == true && mounted) {
      await compartirReciboLocal(context, c);
    }
  }

  /// Recibo con los datos del servidor (nombres de banco/forma resueltos).
  Future<void> _compartirReciboServidor(String numpago, CobroLocal local) async {
    try {
      final c = await _datasource.getCobroDetalle(numpago);
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final empresaNombre = await auth.getEmpresaNombre();
      final f = DateFormat('dd/MM/yyyy');
      final fechaC = DateTime.tryParse('${c['fecha'] ?? ''}');
      await CobroPdf.compartir(
        empresaNombre: empresaNombre,
        numeroCobro: numpago,
        fecha: fechaC == null ? '' : f.format(fechaC),
        status: '${c['status']}',
        vendedorNombre: auth.vendedor?.nombreCompleto ?? '',
        clienteNombre: widget.nombreCliente,
        clienteDireccion: '${c['str_cliente_direccion'] ?? ''}'.trim(),
        documentos: ((c['documentos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        formas: ((c['formas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        total: _d(c['monto']),
      );
    } catch (_) {
      // Se registró pero la red volvió a caer: el recibo local sirve igual.
      if (!mounted) return;
      await compartirReciboLocal(context, local, numpago: numpago);
    }
  }

  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.error,
    ));
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Registrar cobro'),
      ),
      body: _cargandoCatalogos
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _falloCatalogos
              ? _errorCatalogos()
              : _formulario(),
      bottomNavigationBar: (!_cargandoCatalogos && !_falloCatalogos)
          ? _barraEnviar()
          : null,
    );
  }

  Widget _errorCatalogos() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppTheme.textSecondary, size: 48),
          const SizedBox(height: 12),
          const Text('Sin conexión y sin datos guardados',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
                'Conéctese al menos una vez para sincronizar las formas de '
                'pago; después podrá cobrar sin señal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _cargarCatalogos,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _formulario() {
    final offline = widget.saldosDe != null || _catalogosDeCache;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (offline) ...[
          _bannerOffline(),
          const SizedBox(height: 12),
        ],
        _tarjetaCliente(),
        const SizedBox(height: 16),
        Row(
          children: [
            _seccionTitulo(_seleccionados.isEmpty
                ? 'DOCUMENTOS A COBRAR'
                : 'DOCUMENTOS A COBRAR (${_seleccionados.length}/${widget.documentos.length})'),
            const Spacer(),
            if (widget.documentos.length > 1)
              TextButton(
                onPressed: () => _marcarTodas(!_todasMarcadas),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  _todasMarcadas ? 'Desmarcar todas' : 'Marcar todas',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...widget.documentos.map(_filaDocumento),
        const SizedBox(height: 16),
        _seccionTitulo('FORMAS DE PAGO'),
        const SizedBox(height: 8),
        ..._formas.asMap().entries.map((e) => _filaForma(e.key, e.value)),
        _botonAgregarForma(),
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _bannerOffline() {
    final f = DateFormat('dd/MM HH:mm');
    final texto = widget.saldosDe != null
        ? 'Sin conexión. Saldos del ${f.format(widget.saldosDe!)}: '
            'verifíquelos con el cliente. El cobro se enviará al recuperar señal.'
        : 'Sin conexión. El cobro se guardará en el teléfono y se enviará '
            'al recuperar señal.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppTheme.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                  color: AppTheme.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCliente() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded,
              color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.nombreCliente,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionTitulo(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppTheme.textSecondary,
        letterSpacing: 1,
      ),
    );
  }

  Widget _filaDocumento(Map<String, dynamic> d) {
    final llave = _llave(d);
    final marcado = _seleccionados.containsKey(llave);
    final saldo = _round2(_d(d['SaldoActual']));
    final dias = (d['dias_vencido'] as num?)?.toInt() ?? 0;
    final vencido = dias > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: marcado
            ? Border.all(color: AppTheme.primary.withOpacity(0.6))
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: marcado,
                activeColor: AppTheme.primary,
                onChanged: (v) => _toggleDocumento(d, v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${d['Abreviatura'] ?? d['tipodoc']} ${d['iddoc']}',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    if (vencido)
                      Text('Vencido hace $dias días',
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 11)),
                  ],
                ),
              ),
              Text(
                _money.format(saldo),
                style: TextStyle(
                    color: vencido ? AppTheme.error : AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (marcado)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Monto a abonar (USD)',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _montoCtrl[llave],
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14),
                      decoration: _inputDeco(prefix: '\$ '),
                      onChanged: (t) => _cambiarMonto(d, t),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaForma(int idx, _FormaPago f) {
    final subtitulo = <String>[];
    if (f.codigo == '02') {
      subtitulo.add(
          '${f.nombreBancoEmisor ?? f.bancoEmisor} → ${f.nombreBancoDestino}');
      subtitulo.add('Ref. ${f.referenciaDigitos}');
    } else if (f.codigo == '01' && f.nombreBancoDestino != null) {
      subtitulo.add(f.nombreBancoDestino!);
    }
    if (f.esBolivares) {
      subtitulo.add('Bs. ${_bs.format(f.montoBs)} @ ${_bs.format(f.tasa)}');
    }
    if (f.esDescuento && f.descuentoPct != null && f.descuentoPct! > 0) {
      subtitulo.add('${_sinCerosFinales(f.descuentoPct!)}%');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(_iconoForma(f.codigo), color: AppTheme.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.nombre,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (subtitulo.isNotEmpty)
                  Text(subtitulo.join('  ·  '),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(_money.format(f.montoUsd),
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppTheme.textSecondary, size: 18),
            onPressed: () => setState(() {
              _formas.removeAt(idx);
              // Si el descuento se quedó sin la forma Dólares, se retira
              // también (la regla es descuento solo si paga en dólares).
              if (!_hayDivisas) {
                _formas.removeWhere((x) => x.esDescuento);
              }
            }),
          ),
        ],
      ),
    );
  }

  IconData _iconoForma(String codigo) {
    switch (codigo) {
      case '01':
        return Icons.credit_card_rounded;
      case '02':
        return Icons.phone_android_rounded;
      case '03':
        return Icons.attach_money_rounded;
      case '04':
        return Icons.payments_rounded;
      case '05':
        return Icons.percent_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  Widget _botonAgregarForma() {
    return OutlinedButton.icon(
      onPressed: _totalDocumentos > 0 ? _abrirSheetForma : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        side: const BorderSide(color: AppTheme.primary),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.add_rounded),
      label: Text(_totalDocumentos > 0
          ? 'Agregar forma de pago'
          : 'Seleccione primero los documentos'),
    );
  }

  Widget _barraEnviar() {
    final dif = _diferencia;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                  _seleccionados.length > 1
                      ? 'A cobrar (${_seleccionados.length} docs):'
                      : 'A cobrar:',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(width: 6),
              Text(_money.format(_totalDocumentos),
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_totalDocumentos > 0 && dif.abs() >= 0.01)
                Text(
                  dif > 0
                      ? 'Falta ${_money.format(dif)}'
                      : 'Sobra ${_money.format(dif.abs())}',
                  style: const TextStyle(
                      color: AppTheme.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _cuadra && !_enviando ? _enviar : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                disabledBackgroundColor: AppTheme.surfaceLight,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Registrar cobro',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SHEET DE FORMA DE PAGO ====================

  Future<void> _abrirSheetForma() async {
    final restante = _diferencia > 0 ? _diferencia : 0.0;
    final forma = await showModalBottomSheet<_FormaPago>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FormaPagoSheet(
        formas: _formasCatalogo,
        bancos: _bancosCatalogo,
        montoSugeridoUsd: restante,
        tasaSugerida: _ultimaTasa,
        hayDivisas: _hayDivisas,
        totalDocumentos: _totalDocumentos,
      ),
    );
    if (forma != null) {
      setState(() {
        _formas.add(forma);
        if (forma.tasa != null) _ultimaTasa = forma.tasa;
      });
    }
  }

  InputDecoration _inputDeco({String? prefix}) => InputDecoration(
        prefixText: prefix,
        prefixStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: AppTheme.surfaceLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}

/// Comparte el recibo de un cobro que aún vive solo en el teléfono
/// (pendiente de envío). Franja gris "PENDIENTE DE ENVIO" y sin numpago
/// hasta que el servidor lo asigne. También lo usa la pantalla de Cobranza.
Future<void> compartirReciboLocal(BuildContext context, CobroLocal c,
    {String? numpago}) async {
  final auth = context.read<AuthProvider>();
  final empresaNombre = await auth.getEmpresaNombre();
  final f = DateFormat('dd/MM/yyyy');
  await CobroPdf.compartir(
    empresaNombre: empresaNombre,
    numeroCobro: numpago ?? 'PENDIENTE',
    fecha: f.format(c.fecreg),
    status: numpago == null ? 'LOCAL' : '02',
    vendedorNombre: auth.vendedor?.nombreCompleto ?? '',
    clienteNombre: c.clienteNombre,
    clienteDireccion: '',
    documentos: c.documentosResumen,
    formas: c.formasResumen,
    total: c.total,
  );
}

String _sinCerosFinales(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceAll(RegExp(r'\.?0+$'), '');
}

// =====================================================================
// Bottom sheet: captura de una forma de pago
// =====================================================================
class _FormaPagoSheet extends StatefulWidget {
  final List<Map<String, dynamic>> formas;
  final List<Map<String, dynamic>> bancos;
  final double montoSugeridoUsd;
  final double? tasaSugerida;

  /// El descuento (05) solo se ofrece cuando ya hay una forma Dólares en
  /// el cobro (regla de Sabino: descuento si el cliente paga en dólares).
  final bool hayDivisas;
  final double totalDocumentos;

  const _FormaPagoSheet({
    required this.formas,
    required this.bancos,
    required this.montoSugeridoUsd,
    this.tasaSugerida,
    this.hayDivisas = false,
    this.totalDocumentos = 0,
  });

  @override
  State<_FormaPagoSheet> createState() => _FormaPagoSheetState();
}

class _FormaPagoSheetState extends State<_FormaPagoSheet> {
  final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  String? _codigo;
  String? _bancoDestino;
  String? _bancoEmisor;
  final _refCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController();
  final _montoBsCtrl = TextEditingController();
  final _montoUsdCtrl = TextEditingController();
  final _pctCtrl = TextEditingController();

  bool get _esBolivares =>
      _codigo == '01' || _codigo == '02' || _codigo == '04';
  bool get _esDescuento => _codigo == '05';

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
  double _round2(double v) => (v * 100).roundToDouble() / 100;

  double get _usdCalculado {
    if (!_esBolivares) return _round2(_num(_montoUsdCtrl));
    final tasa = _num(_tasaCtrl);
    final bs = _num(_montoBsCtrl);
    if (tasa <= 0 || bs <= 0) return 0;
    return _round2(bs / tasa);
  }

  bool get _valido {
    if (_codigo == null) return false;
    if (_esBolivares) {
      if (_num(_tasaCtrl) <= 0 || _num(_montoBsCtrl) <= 0) return false;
      if (_codigo == '02') {
        if (_bancoDestino == null || _bancoEmisor == null) return false;
        final ref = _refCtrl.text.trim();
        if (!RegExp(r'^\d{4,8}$').hasMatch(ref)) return false;
      }
      if (_codigo == '01' && _bancoDestino == null) return false;
      return true;
    }
    return _num(_montoUsdCtrl) > 0;
  }

  @override
  void initState() {
    super.initState();
    if (widget.tasaSugerida != null && widget.tasaSugerida! > 0) {
      _tasaCtrl.text = widget.tasaSugerida!.toStringAsFixed(2);
    }
    if (widget.montoSugeridoUsd > 0) {
      _montoUsdCtrl.text = widget.montoSugeridoUsd.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _tasaCtrl.dispose();
    _montoBsCtrl.dispose();
    _montoUsdCtrl.dispose();
    _pctCtrl.dispose();
    super.dispose();
  }

  String _nombreBanco(String? code) {
    if (code == null) return '';
    final b = widget.bancos.firstWhere((x) => x['code'] == code,
        orElse: () => const {});
    return (b['name'] ?? code).toString();
  }

  /// % de descuento -> monto sobre el total de documentos seleccionados
  /// (mismo cálculo que hace la oficina: 10% del documento). El monto se
  /// puede corregir a mano después.
  void _alCambiarPct(String _) {
    final pct = _num(_pctCtrl);
    if (pct > 0 && widget.totalDocumentos > 0) {
      _montoUsdCtrl.text =
          _round2(widget.totalDocumentos * pct / 100).toStringAsFixed(2);
    }
    setState(() {});
  }

  void _confirmar() {
    final nombreForma = widget.formas
        .firstWhere((f) => f['code'] == _codigo)['name']
        .toString();
    final usd = _usdCalculado;
    if (usd <= 0) return;

    Navigator.pop(
      context,
      _FormaPago(
        codigo: _codigo!,
        nombre: nombreForma,
        montoUsd: usd,
        tasa: _esBolivares ? _round2(_num(_tasaCtrl)) : null,
        montoBs: _esBolivares ? _round2(_num(_montoBsCtrl)) : null,
        codBancoDestino:
            (_codigo == '02' || _codigo == '01') ? _bancoDestino : null,
        nombreBancoDestino: (_codigo == '02' || _codigo == '01')
            ? _nombreBanco(_bancoDestino)
            : null,
        bancoEmisor: _codigo == '02' ? _bancoEmisor : null,
        nombreBancoEmisor:
            _codigo == '02' ? _nombreBanco(_bancoEmisor) : null,
        referenciaDigitos: _codigo == '02' ? _refCtrl.text.trim() : null,
        descuentoPct: _esDescuento && _num(_pctCtrl) > 0
            ? _round2(_num(_pctCtrl))
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // El descuento solo aparece cuando ya hay una forma Dólares en el cobro.
    final formasVisibles = widget.formas
        .where((f) => f['code'] != '05' || widget.hayDivisas)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
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
            const Text('Forma de pago',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _dropdown<String>(
              hint: '¿Cómo pagó el cliente?',
              value: _codigo,
              items: formasVisibles
                  .map((f) => DropdownMenuItem(
                      value: f['code'].toString(),
                      child: Text(f['name'].toString())))
                  .toList(),
              onChanged: (v) => setState(() => _codigo = v),
            ),
            if (_codigo == '02') ...[
              const SizedBox(height: 10),
              _dropdown<String>(
                hint: 'Banco que recibió el pago',
                value: _bancoDestino,
                items: _itemsBancos(),
                onChanged: (v) => setState(() => _bancoDestino = v),
              ),
              const SizedBox(height: 10),
              _dropdown<String>(
                hint: 'Banco desde el que pagó el cliente',
                value: _bancoEmisor,
                items: _itemsBancos(),
                onChanged: (v) => setState(() => _bancoEmisor = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _refCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration:
                    _deco('Últimos dígitos de la referencia (4 a 8)'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_codigo == '01') ...[
              const SizedBox(height: 10),
              _dropdown<String>(
                hint: 'Banco del punto de venta',
                value: _bancoDestino,
                items: _itemsBancos(),
                onChanged: (v) => setState(() => _bancoDestino = v),
              ),
            ],
            if (_esBolivares) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tasaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _deco('Tasa del día (Bs/\$)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _montoBsCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _deco('Monto en Bs.'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Equivale a ${_money.format(_usdCalculado)}',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
            if (_codigo == '03') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _montoUsdCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _deco('Monto en dólares'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_esDescuento) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pctCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _deco('% de descuento'),
                      onChanged: _alCambiarPct,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _montoUsdCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: _deco('Monto (USD)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'El descuento aplica cuando el cliente paga en dólares. '
                'La oficina lo verá igual que los suyos: "DSCTO.% ..."',
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _valido ? _confirmar : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  disabledBackgroundColor: AppTheme.surfaceLight,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Agregar',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _itemsBancos() => widget.bancos
      .map((b) => DropdownMenuItem(
          value: b['code'].toString(),
          child: Text(b['name'].toString(),
              overflow: TextOverflow.ellipsis)))
      .toList();

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      dropdownColor: AppTheme.surfaceLight,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      decoration: _deco(hint),
      items: items,
      onChanged: onChanged,
    );
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppTheme.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}

/// UUID v4 con Random.secure (mismo helper que pedidos, sin dependencia externa).
String _generarUuidV4() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
