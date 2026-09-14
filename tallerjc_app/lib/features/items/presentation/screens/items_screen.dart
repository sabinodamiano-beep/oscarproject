import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gyfsoftware_movil/features/items/presentation/providers/item_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/entities/item.dart';
import 'item_detalle_screen.dart';
import '../../../../shared/widgets/offline_banner.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ItemsProvider>();
      provider.cargarItems();
      provider.cargarLineas();
    });
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<ItemsProvider>().cargarItems(
            buscar: query.isEmpty ? null : query,
          );
    });
  }

  void _limpiarBusqueda() {
    _searchController.clear();
    context.read<ItemsProvider>().cargarItems();
  }

  Future<void> _refresh() async {
    final query = _searchController.text.trim();
    await context.read<ItemsProvider>().cargarItems(
          buscar: query.isEmpty ? null : query,
        );
  }

  void _irADetalle(Item item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetalleScreen(coditems: item.coditems),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
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
            _buildLineas(),
            Expanded(child: _buildItemsList()),
          ],
        ),
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Productos',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.liquor_rounded, color: AppTheme.primary, size: 20),
          ),
        ],
      ),
    );
  }

  // ==================== SEARCH BAR ====================
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearch,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o código...',
          hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6), fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 20),
                  onPressed: _limpiarBusqueda,
                )
              : null,
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ==================== FILTRO POR LÍNEA ====================
  Widget _buildLineas() {
    return Consumer<ItemsProvider>(
      builder: (context, provider, _) {
        if (provider.lineas.isEmpty) return const SizedBox.shrink();
        final opciones = <String?>[null, ...provider.lineas];
        return SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            itemCount: opciones.length,
            itemBuilder: (context, i) {
              final linea = opciones[i];
              final activo = provider.filtroLinea == linea;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(linea ?? 'Todas'),
                  selected: activo,
                  showCheckmark: false,
                  onSelected: (_) {
                    final q = _searchController.text.trim();
                    provider.filtrarPorLinea(linea, buscar: q.isEmpty ? null : q);
                  },
                  selectedColor: AppTheme.primary.withOpacity(0.25),
                  backgroundColor: AppTheme.surface,
                  side: BorderSide(color: activo ? AppTheme.primary : AppTheme.divider, width: 0.5),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: activo ? AppTheme.primary : AppTheme.textSecondary,
                    fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ==================== LISTA ====================
  Widget _buildItemsList() {
    return Consumer<ItemsProvider>(
      builder: (context, provider, _) {
        if (provider.estaCargandoLista && provider.items.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        if (provider.errorLista != null && provider.items.isEmpty) {
          return ErrorDisplay(
            message: provider.errorLista!,
            onRetry: _refresh,
          );
        }

        if (provider.items.isEmpty) {
          return EmptyState(
            message: _searchController.text.isNotEmpty
                ? 'No se encontraron productos'
                : 'No hay productos registrados',
            icon: Icons.liquor_outlined,
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: provider.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _ItemCard(
                item: provider.items[index],
                onTap: () => _irADetalle(provider.items[index]),
              );
            },
          ),
        );
      },
    );
  }
}

// ==================== WIDGET: ITEM CARD ====================
class _ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;

  const _ItemCard({required this.item, required this.onTap});

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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.desitems,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'COD: ${item.coditems}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (item.nombreLinea.isNotEmpty)
                        Flexible(
                          child: Text(
                            item.nombreLinea,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.primary.withOpacity(0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const Spacer(),
                      _buildPrecioBadge(),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildPrecioBadge() {
    final tiene = item.dolPre > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (tiene ? AppTheme.accent : AppTheme.textSecondary).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tiene
            ? '\$${item.dolPre.toStringAsFixed(2)}${item.cantunidad > 1 ? ' / caja' : ''}'
            : 'Sin precio',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tiene ? AppTheme.accent : AppTheme.textSecondary,
        ),
      ),
    );
  }
}