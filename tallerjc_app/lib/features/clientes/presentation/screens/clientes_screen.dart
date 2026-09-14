import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gyfsoftware_movil/features/clientes/presentation/providers/cliente_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/entities/cliente.dart';
import 'cliente_detalle_screen.dart';
import 'cliente_crear_screen.dart';
import '../../../../shared/widgets/offline_banner.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientesProvider>().cargarClientes();
    });
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<ClientesProvider>().cargarClientes(
            buscar: query.isEmpty ? null : query,
          );
    });
  }

  void _limpiarBusqueda() {
    _searchController.clear();
    context.read<ClientesProvider>().cargarClientes();
  }

  Future<void> _refresh() async {
    final query = _searchController.text.trim();
    await context.read<ClientesProvider>().cargarClientes(
          buscar: query.isEmpty ? null : query,
        );
  }

  void _irADetalle(Cliente cliente) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClienteDetalleScreen(uidCliente: cliente.uidCliente),
      ),
    );
  }

  void _irACrear() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ClienteCrearScreen()),
    );

    // Si se creó un cliente, refrescar la lista
    if (resultado == true && mounted) {
      _limpiarBusqueda();
    }
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
            Expanded(child: _buildClientesList()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_clientes',
        onPressed: _irACrear,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
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
            'Clientes',
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
            child: const Icon(Icons.people_rounded, color: AppTheme.primary, size: 20),
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
          hintText: 'Buscar por nombre, cédula o código...',
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

  // ==================== LISTA ====================
  Widget _buildClientesList() {
    return Consumer<ClientesProvider>(
      builder: (context, provider, _) {
        if (provider.estaCargandoLista && provider.clientes.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        if (provider.errorLista != null && provider.clientes.isEmpty) {
          return ErrorDisplay(
            message: provider.errorLista!,
            onRetry: _refresh,
          );
        }

        if (provider.clientes.isEmpty) {
          return EmptyState(
            message: _searchController.text.isNotEmpty
                ? 'No se encontraron clientes'
                : 'No hay clientes registrados',
            icon: Icons.people_outline,
            actionLabel: 'Crear cliente',
            onAction: _irACrear,
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
            itemCount: provider.clientes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _ClienteCard(
                cliente: provider.clientes[index],
                onTap: () => _irADetalle(provider.clientes[index]),
              );
            },
          ),
        );
      },
    );
  }
}

// ==================== WIDGET: CLIENTE CARD ====================
class _ClienteCard extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback onTap;

  const _ClienteCard({required this.cliente, required this.onTap});

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
            // Avatar con iniciales
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _getInitials(cliente),
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cliente.nombreCompleto,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.badge_outlined, size: 14, color: AppTheme.textSecondary.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Text(
                        cliente.cedulaCompleta,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary.withOpacity(0.8),
                        ),
                      ),
                      if (cliente.tieneTelefonoCelular) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.phone_outlined, size: 14, color: AppTheme.textSecondary.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            cliente.telefonoCelular,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary.withOpacity(0.8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }

  String _getInitials(Cliente c) {
    final n = c.nombres.isNotEmpty ? c.nombres[0] : '';
    final a = c.apellidos.isNotEmpty && c.apellidos != '.' ? c.apellidos[0] : '';
    return '$n$a'.toUpperCase();
  }
}