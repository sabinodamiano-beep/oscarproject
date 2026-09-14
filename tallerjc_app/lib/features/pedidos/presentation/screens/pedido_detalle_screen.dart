import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../domain/entities/pedido.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/pedido_provider.dart';
import '../utils/pedido_compartir.dart';
import '../utils/pedido_pdf.dart';
import 'pedido_crear_screen.dart';
import 'pedidos_screen.dart' show StatusChip;

class PedidoDetalleScreen extends StatefulWidget {
  final String uidPedido;
  const PedidoDetalleScreen({super.key, required this.uidPedido});

  @override
  State<PedidoDetalleScreen> createState() => _PedidoDetalleScreenState();
}

class _PedidoDetalleScreenState extends State<PedidoDetalleScreen> {
  late final PedidosProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<PedidosProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.cargarDetalle(widget.uidPedido);
    });
  }

  @override
  void dispose() {
    _provider.limpiarDetalle();
    super.dispose();
  }

  Future<void> _anular() async {
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Anular pedido #${widget.uidPedido}'),
        content: TextField(
          controller: motivoCtrl,
          maxLength: 300,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Motivo (opcional)', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anular', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final motivo = motivoCtrl.text.trim();
    final ok = await context.read<PedidosProvider>().anularPedido(
          widget.uidPedido,
          motivo: motivo.isEmpty ? null : motivo,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Pedido anulado' : (context.read<PedidosProvider>().errorDetalle ?? 'No se pudo anular')),
        backgroundColor: ok ? AppTheme.surface : AppTheme.error,
      ),
    );
  }

  static String _fechaTexto(DateTime? d) {
    if (d == null) return '-';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year}';
  }

  List<LineaCompartir> _lineasDe(Pedido p) => p.items
      .map((it) => LineaCompartir(
            descripcion: it.descripcion,
            presentacion: it.nombrePresentacion,
            cajas: it.cantidad,
            botellas: it.cantidadUnidad,
            precioUnit: it.precunit,
            total: it.total,
          ))
      .toList();

  /// Menú: PDF (documento adjunto) o texto plano por WhatsApp.
  Future<void> _compartir() async {
    final p = _provider.pedidoDetalle;
    if (p == null) return;

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
      ok = await PedidoPdf.compartir(
        empresaNombre: empresaNombre,
        numeroPedido: p.uidPedido,
        fecha: _fechaTexto(p.fechaPedido),
        vendedorNombre: auth.vendedor?.nombreCompleto ?? '',
        clienteNombre: p.clienteNombre,
        clienteDireccion: p.clienteDireccion,
        lineas: _lineasDe(p),
        total: p.total,
        observaciones: p.observaciones,
        estado: p.anulado ? 'ANULADO' : '',
      );
    } else {
      final texto = PedidoCompartir.textoPedido(
        titulo: 'Pedido #${p.uidPedido}',
        fecha: _fechaTexto(p.fechaPedido),
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

  Future<void> _editar(Pedido pedido) async {
    _provider.cargarEnCarrito(pedido);
    final uid = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PedidoCrearScreen()),
    );
    if (!mounted) return;
    if (uid != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido actualizado')));
    } else {
      // Si canceló la edición, limpiar por si quedó algo
      _provider.limpiarCarrito();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Pedido #${widget.uidPedido}'),
        actions: [
          Consumer<PedidosProvider>(
            builder: (context, provider, _) => provider.pedidoDetalle == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Compartir',
                    icon: const Icon(Icons.share_rounded),
                    onPressed: _compartir,
                  ),
          ),
        ],
      ),
      body: Consumer<PedidosProvider>(
        builder: (context, provider, _) {
          if (provider.estaCargandoDetalle) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final p = provider.pedidoDetalle;
          if (p == null) {
            return ErrorDisplay(
              message: provider.errorDetalle ?? 'Pedido no encontrado',
              onRetry: () => provider.cargarDetalle(widget.uidPedido),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _Cabecera(pedido: p),
                    const SizedBox(height: 20),
                    Text(
                      'Productos (${p.items.length})',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    ...p.items.map((it) => _ItemRow(item: it)),
                    if (p.tieneObservaciones) ...[
                      const SizedBox(height: 20),
                      const Text('Observaciones',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
                        child: Text(p.observaciones, style: const TextStyle(color: AppTheme.textPrimary)),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        Text('\$${p.total.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.accent, fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Spacer(),
                    if (p.enProceso) ...[
                      OutlinedButton.icon(
                        onPressed: provider.estaAnulando ? null : _anular,
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: Text(provider.estaAnulando ? 'Anulando...' : 'Anular'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: provider.estaAnulando ? null : () => _editar(p),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Editar'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final Pedido pedido;
  const _Cabecera({required this.pedido});

  String _fecha(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(idStatus: pedido.idStatus, label: pedido.status),
              const Spacer(),
              Text(_fecha(pedido.fechaPedido), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Text(pedido.clienteNombre,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          if (pedido.clienteDireccion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(pedido.clienteDireccion, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
          if (pedido.facturado && pedido.numFactura.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Factura: ${pedido.numFactura}',
                style: const TextStyle(color: AppTheme.statusFacturado, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final PedidoItem item;
  const _ItemRow({required this.item});

  String _cant(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final detalle = item.cantidadUnidad > 0
        ? '${_cant(item.cantidad)} caja(s) + ${_cant(item.cantidadUnidad)} bot. · \$${item.precunit.toStringAsFixed(2)} c/u'
        : '${_cant(item.cantidad)} × \$${item.precunit.toStringAsFixed(2)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.descripcion,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${item.coditems} · $detalle', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('\$${item.total.toStringAsFixed(2)}',
              style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}