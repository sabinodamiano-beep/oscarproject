import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../core/sync/outbox_sync_service.dart';
import '../../../../shared/widgets/offline_banner.dart';
import '../../data/models/pedido_local_model.dart';
import '../../domain/entities/pedido.dart';
import '../providers/pedido_provider.dart';
import 'pedido_crear_screen.dart';
import 'pedido_detalle_screen.dart';
import 'pedido_local_detalle_screen.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  static const _filtros = <String?, String>{
    null: 'Todos',
    '00': 'En proceso',
    '04': 'Facturados',
    '99': 'Anulados',
  };

  int _ultimoPorAtender = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PedidosProvider>().cargarPedidos();
    });
    OutboxSyncService.instance.addListener(_alCambiarOutbox);
  }

  @override
  void dispose() {
    OutboxSyncService.instance.removeListener(_alCambiarOutbox);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Cuando el outbox envía en segundo plano, la lista se refresca sola.
  void _alCambiarOutbox() {
    final o = OutboxSyncService.instance;
    if (o.procesando) return;
    if (o.porAtender != _ultimoPorAtender) {
      _ultimoPorAtender = o.porAtender;
      if (mounted) context.read<PedidosProvider>().cargarPedidos(mantenerFiltros: true);
    }
  }

  Future<void> _refresh() => context.read<PedidosProvider>().cargarPedidos(mantenerFiltros: true);

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final p = context.read<PedidosProvider>();
      p.cargarPedidos(status: p.filtroStatus, buscar: q.trim().isEmpty ? null : q.trim());
    });
  }

  void _setFiltro(String? status) {
    final p = context.read<PedidosProvider>();
    p.cargarPedidos(status: status, buscar: p.filtroBuscar);
  }

  void _irACrear() async {
    final mensaje = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PedidoCrearScreen()),
    );
    if (mensaje != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    }
  }

  void _irADetalleLocal(PedidoLocal p) async {
    final mensaje = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => PedidoLocalDetalleScreen(pedido: p)),
    );
    if (!mounted) return;
    context.read<PedidosProvider>().cargarPedidos(mantenerFiltros: true);
    if (mensaje != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    }
  }

  void _irADetalle(Pedido p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PedidoDetalleScreen(uidPedido: p.uidPedido)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSearchBar(),
            const OfflineBanner(),
            _buildFiltros(),
            Expanded(child: _buildLista()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_pedidos',
        onPressed: _irACrear,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text('Nuevo pedido', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Pedidos',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          _buildIndicadorOutbox(),
        ],
      ),
    );
  }

  /// Icono de la cabecera: si hay pedidos por enviar muestra el contador y
  /// al tocarlo intenta enviarlos.
  Widget _buildIndicadorOutbox() {
    return ListenableBuilder(
      listenable: OutboxSyncService.instance,
      builder: (context, _) {
        final o = OutboxSyncService.instance;
        final n = o.porAtender;
        final hayFallidos = o.fallidos > 0;
        final color = n == 0 ? AppTheme.primary : (hayFallidos ? AppTheme.error : AppTheme.warning);
        return GestureDetector(
          onTap: n == 0 || o.procesando
              ? null
              : () async {
                  await o.procesar();
                  if (!mounted) return;
                  final m = o.ultimoMensaje;
                  if (m != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                },
          child: Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: n == 0 ? 10 : 12),
            decoration: BoxDecoration(
              color: n == 0 ? AppTheme.surface : color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: n == 0 ? null : Border.all(color: color.withOpacity(0.5), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (o.procesando)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: color, strokeWidth: 2))
                else
                  Icon(n == 0 ? Icons.receipt_long_rounded : Icons.cloud_upload_outlined, color: color, size: 20),
                if (n > 0) ...[
                  const SizedBox(width: 6),
                  Text('$n por enviar',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearch,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Buscar por número o cliente...',
          hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6), fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _onSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    return Consumer<PedidosProvider>(
      builder: (context, p, _) => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: _filtros.entries.map((e) {
            final activo = p.filtroStatus == e.key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: activo,
                onSelected: (_) => _setFiltro(e.key),
                selectedColor: AppTheme.primary.withOpacity(0.25),
                backgroundColor: AppTheme.surface,
                labelStyle: TextStyle(
                  color: activo ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
                side: BorderSide(color: activo ? AppTheme.primary : AppTheme.divider, width: 0.5),
                showCheckmark: false,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLista() {
    return Consumer<PedidosProvider>(
      builder: (context, provider, _) {
        final locales = provider.pedidosLocales;
        final remotos = provider.pedidos;
        final vacio = locales.isEmpty && remotos.isEmpty;

        if (provider.estaCargandoLista && vacio) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (provider.errorLista != null && vacio) {
          return ErrorDisplay(message: provider.errorLista!, onRetry: _refresh);
        }
        if (vacio) {
          final filtrado = provider.filtroStatus != null || (provider.filtroBuscar ?? '').isNotEmpty;
          return EmptyState(
            message: filtrado ? 'No hay pedidos con ese filtro' : 'Aún no has registrado pedidos',
            icon: Icons.receipt_long_outlined,
            actionLabel: filtrado ? null : 'Crear pedido',
            onAction: filtrado ? null : _irACrear,
          );
        }
        // Locales primero (pendientes / con error), luego los del servidor.
        // Si el servidor no respondió pero hay locales, se avisa al pie.
        final avisoRemoto = provider.errorLista != null && remotos.isEmpty ? provider.errorLista : null;
        final total = locales.length + remotos.length + (avisoRemoto != null ? 1 : 0);
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
            itemCount: total,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i < locales.length) {
                return _PedidoLocalCard(pedido: locales[i], onTap: () => _irADetalleLocal(locales[i]));
              }
              final j = i - locales.length;
              if (j < remotos.length) {
                return _PedidoCard(pedido: remotos[j], onTap: () => _irADetalle(remotos[j]));
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(avisoRemoto!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              );
            },
          ),
        );
      },
    );
  }
}

/// Tarjeta de un pedido que todavía vive en el teléfono.
class _PedidoLocalCard extends StatelessWidget {
  final PedidoLocal pedido;
  final VoidCallback onTap;
  const _PedidoLocalCard({required this.pedido, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = pedido.fallido ? AppTheme.error : AppTheme.warning;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.6), width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(pedido.fallido ? Icons.error_outline_rounded : Icons.cloud_upload_outlined,
                          size: 16, color: color),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          pedido.fallido ? 'Con error' : 'Por enviar',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pedido.clienteNombre,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fecha(pedido.fecreg)} · ${pedido.totalItems} ${pedido.totalItems == 1 ? 'producto' : 'productos'}'
                    '${pedido.fallido && pedido.ultimoError != null ? ' · ${pedido.ultimoError}' : ''}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withOpacity(0.7)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              '\$${pedido.total.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }

  String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _PedidoCard extends StatelessWidget {
  final Pedido pedido;
  final VoidCallback onTap;
  const _PedidoCard({required this.pedido, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${pedido.uidPedido}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(idStatus: pedido.idStatus, label: pedido.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pedido.clienteNombre,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fecha(pedido.fechaPedido)} · ${pedido.totalItems} ${pedido.totalItems == 1 ? 'producto' : 'productos'}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            Text(
              '\$${pedido.total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accent),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }

  String _fecha(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

/// Chip de estado reutilizado por lista y detalle
class StatusChip extends StatelessWidget {
  final String idStatus;
  final String label;
  const StatusChip({super.key, required this.idStatus, required this.label});

  Color get _color {
    switch (idStatus) {
      case '00':
        return AppTheme.statusEnProceso;
      case '02':
      case '03':
        return AppTheme.statusEmitido;
      case '04':
      case '06':
        return AppTheme.statusFacturado;
      case '99':
        return AppTheme.statusAnulado;
      default:
        return AppTheme.statusPendiente;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.isEmpty ? idStatus : label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _color),
      ),
    );
  }
}
