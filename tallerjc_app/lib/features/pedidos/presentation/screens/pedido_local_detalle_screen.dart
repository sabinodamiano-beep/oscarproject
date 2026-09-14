import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/local_database.dart';
import '../../../../core/sync/connection_monitor.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/pedido_local_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../items/domain/entities/item.dart';
import '../providers/pedido_provider.dart';
import '../utils/pedido_compartir.dart';
import '../utils/pedido_pdf.dart';
import 'pedido_crear_screen.dart';

/// Detalle de un pedido que todavía vive en el teléfono (pendiente de envío o
/// rechazado por el servidor). Permite reenviar, editar y descartar.
class PedidoLocalDetalleScreen extends StatefulWidget {
  final PedidoLocal pedido;
  const PedidoLocalDetalleScreen({super.key, required this.pedido});

  @override
  State<PedidoLocalDetalleScreen> createState() => _PedidoLocalDetalleScreenState();
}

class _PedidoLocalDetalleScreenState extends State<PedidoLocalDetalleScreen> {
  late PedidoLocal _pedido = widget.pedido;
  bool _trabajando = false;

  Future<void> _reintentar() async {
    setState(() => _trabajando = true);
    final uid = await context.read<PedidosProvider>().reintentarLocal(_pedido.uuid);
    if (!mounted) return;
    setState(() => _trabajando = false);
    if (uid != null) {
      Navigator.pop(context, 'Pedido #$uid creado');
      return;
    }
    // Sigue local: refrescar estado/error
    final actualizado = context.read<PedidosProvider>().pedidosLocales
        .where((p) => p.uuid == _pedido.uuid)
        .toList();
    if (actualizado.isNotEmpty) setState(() => _pedido = actualizado.first);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_pedido.fallido
          ? (_pedido.ultimoError ?? 'El servidor rechazó el pedido')
          : 'Sin conexión: se enviará al recuperar señal'),
      backgroundColor: _pedido.fallido ? AppTheme.error : AppTheme.warning,
    ));
  }

  List<LineaCompartir> _lineasDe(PedidoLocal p) => p.lineas
      .map((l) => LineaCompartir(
            descripcion: l.descripcion,
            presentacion: l.nombrePresentacion,
            cajas: l.cajas,
            botellas: l.botellas,
            precioUnit: l.dolPre,
            total: l.total,
          ))
      .toList();

  /// Menú: PDF (documento adjunto) o texto plano por WhatsApp.
  Future<void> _compartir() async {
    final p = _pedido;

    final opcion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.error),
              title: const Text('Compartir PDF'),
              subtitle: const Text('Nota de pedido con membrete',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: AppTheme.accent),
              title: const Text('Texto por WhatsApp'),
              onTap: () => Navigator.pop(context, 'texto'),
            ),
          ],
        ),
      ),
    );
    if (opcion == null || !mounted) return;

    bool ok;
    if (opcion == 'pdf') {
      final auth = context.read<AuthProvider>();
      final empresaNombre = await auth.getEmpresaNombre();
      // Dirección desde la caché local de clientes (el pedido local no la trae)
      String direccion = '';
      try {
        final c = await LocalDatabase.instance.getCliente(p.uidCliente);
        direccion = c?['str_cliente_direccion']?.toString().trim() ?? '';
      } catch (_) {}
      ok = await PedidoPdf.compartir(
        empresaNombre: empresaNombre,
        numeroPedido: 'PENDIENTE',
        fecha: _fecha(p.fecreg),
        vendedorNombre: auth.vendedor?.nombreCompleto ?? '',
        clienteNombre: p.clienteNombre,
        clienteDireccion: direccion,
        lineas: _lineasDe(p),
        total: p.total,
        observaciones: p.observaciones,
        estado: 'PENDIENTE DE ENVIO - total sujeto a confirmacion del servidor',
      );
    } else {
      final texto = PedidoCompartir.textoPedido(
        titulo: 'Pedido (pendiente de envío)',
        fecha: _fecha(p.fecreg),
        clienteNombre: p.clienteNombre,
        lineas: _lineasDe(p),
        total: p.total,
        observaciones: p.observaciones,
      );
      ok = await PedidoCompartir.porWhatsApp(texto);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo compartir'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _editar() async {
    final provider = context.read<PedidosProvider>();
    provider.cargarLocalEnCarrito(_pedido);
    final resultado = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PedidoCrearScreen()),
    );
    if (!mounted) return;
    if (resultado != null) {
      Navigator.pop(context, resultado);
    } else {
      provider.limpiarCarrito();
    }
  }

  Future<void> _descartar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('¿Descartar este pedido?'),
        content: const Text('Se borrará del teléfono. Nunca llegó al servidor, así que no queda rastro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, minimumSize: const Size(0, 40)),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<PedidosProvider>().descartarLocal(_pedido.uuid);
    if (mounted) Navigator.pop(context, 'Pedido descartado');
  }

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    final color = p.fallido ? AppTheme.error : AppTheme.warning;
    final online = ConnectionMonitor.instance.intentarRemoto;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Pedido guardado'),
        actions: [
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.share_rounded),
            onPressed: _compartir,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Estado
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.4), width: 0.5),
            ),
            child: Row(
              children: [
                Icon(p.fallido ? Icons.error_outline_rounded : Icons.cloud_upload_outlined, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.fallido ? 'Rechazado por el servidor' : 'Pendiente de envío',
                        style: TextStyle(fontWeight: FontWeight.w600, color: color),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.fallido
                            ? (p.ultimoError ?? 'Error desconocido')
                            : 'Se enviará automáticamente al recuperar señal'
                                '${p.intentos > 0 ? ' · ${p.intentos} ${p.intentos == 1 ? 'intento' : 'intentos'}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cliente
          _Seccion('Cliente'),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.clienteNombre,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text('Guardado el ${_fecha(p.fecreg)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Productos
          _Seccion('Productos (${p.totalItems})'),
          _Card(
            child: Column(
              children: [
                for (var i = 0; i < p.lineas.length; i++) ...[
                  if (i > 0) const Divider(color: AppTheme.divider, height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.lineas[i].descripcion,
                                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                              '${_num(p.lineas[i].cajas)} ${p.lineas[i].cajas == 1 ? 'caja' : 'cajas'}'
                              '${p.lineas[i].botellas > 0 ? ' + ${_num(p.lineas[i].botellas)} bot.' : ''}'
                              ' · \$${p.lineas[i].dolPre.toStringAsFixed(2)} c/u'
                              '${p.lineas[i].precioNivel == 'pvp' ? '' : ' (${Item.nombresNivel[p.lineas[i].precioNivel]})'}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Text('\$${p.lineas[i].total.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    ],
                  ),
                ],
                const Divider(color: AppTheme.divider, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total (precios de la última sincronización)',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text('\$${p.total.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                  ],
                ),
              ],
            ),
          ),

          if (p.tieneObservaciones) ...[
            const SizedBox(height: 16),
            _Seccion('Observaciones'),
            _Card(child: Text(p.observaciones, style: const TextStyle(color: AppTheme.textPrimary))),
          ],

          const SizedBox(height: 24),

          // Acciones
          ElevatedButton.icon(
            onPressed: _trabajando ? null : _reintentar,
            icon: _trabajando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(_trabajando ? 'Enviando...' : (online ? 'Enviar ahora' : 'Intentar enviar')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _trabajando ? null : _editar,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _trabajando ? null : _descartar,
            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
            label: const Text('Descartar', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  static String _fecha(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }

  static String _num(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
}

class _Seccion extends StatelessWidget {
  final String texto;
  const _Seccion(this.texto);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 1.2)),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider, width: 0.5),
        ),
        child: child,
      );
}
