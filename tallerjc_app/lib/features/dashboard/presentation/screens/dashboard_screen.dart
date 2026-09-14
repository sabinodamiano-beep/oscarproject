import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/home_screen.dart';
import '../providers/dashboard_provider.dart';
import '../../../../core/sync/connection_monitor.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().cargarDashboard();
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    final connected = await ConnectionMonitor.instance.verificar();
    if (mounted) {
      setState(() => _isConnected = connected);
    }
  }

  Future<void> _refresh() async {
    await context.read<DashboardProvider>().cargarDashboard();
    await _checkConnection();
  }

  void _navegarATab(int index) {
    context.findAncestorStateOfType<HomeScreenState>()?.cambiarTab(index);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final vendedor = authProvider.vendedor;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer<DashboardProvider>(
          builder: (context, dashProvider, _) {
            return RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildHeader(vendedor?.nombre ?? 'Vendedor'),
                    const SizedBox(height: 24),
                    _buildStatsGrid(dashProvider),
                    const SizedBox(height: 28),
                    _buildQuickActions(),
                    const SizedBox(height: 28),
                    _buildRecentInfo(dashProvider),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader(String nombre) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_rounded, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, $nombre',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isConnected ? AppTheme.accent : AppTheme.error,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isConnected ? 'En Línea' : 'Sin Conexión',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isConnected ? AppTheme.accent : AppTheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.notifications_outlined, color: AppTheme.textSecondary, size: 20),
        ),
      ],
    );
  }

  // ==================== GRID DE STATS ====================
  Widget _buildStatsGrid(DashboardProvider dashProvider) {
    if (dashProvider.estaCargando && dashProvider.data == null) {
      return _buildStatsGridLoading();
    }

    if (dashProvider.error != null && dashProvider.data == null) {
      return ErrorDisplay(
        message: dashProvider.error!,
        onRetry: _refresh,
      );
    }

    final data = dashProvider.data;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.receipt_long_outlined,
                label: 'Pedidos del Día',
                value: '${data?.pedidosDia ?? 0}',
                color: AppTheme.primary,
                iconBgColor: AppTheme.primary.withOpacity(0.15),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.pending_actions_outlined,
                label: 'Pedidos Pendientes',
                value: '${data?.pedidosPendientes ?? 0}',
                color: AppTheme.warning,
                iconBgColor: AppTheme.warning.withOpacity(0.15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.people_outline,
                label: 'Total Clientes',
                value: _formatNumber(data?.totalClientes ?? 0),
                color: AppTheme.accent,
                iconBgColor: AppTheme.accent.withOpacity(0.15),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.liquor_outlined,
                label: 'Productos Activos',
                value: '${data?.totalProductos ?? 0}',
                color: AppTheme.statusFacturado,
                iconBgColor: AppTheme.statusFacturado.withOpacity(0.15),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsGridLoading() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildShimmerCard()),
            const SizedBox(width: 12),
            Expanded(child: _buildShimmerCard()),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildShimmerCard()),
            const SizedBox(width: 12),
            Expanded(child: _buildShimmerCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
        ),
      ),
    );
  }

  // ==================== ACCIONES RÁPIDAS ====================
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ACCIONES RÁPIDAS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            // Nuevo Pedido
            Expanded(
              child: _QuickActionButton(
                icon: Icons.add_shopping_cart_rounded,
                label: 'Nuevo\nPedido',
                color: AppTheme.primary,
                enabled: true,
                onTap: () => _navegarATab(1),
              ),
            ),
            const SizedBox(width: 12),
            // Mis Clientes
            Expanded(
              child: _QuickActionButton(
                icon: Icons.people_rounded,
                label: 'Mis\nClientes',
                color: AppTheme.accent,
                enabled: true,
                onTap: () => _navegarATab(2),
              ),
            ),
            const SizedBox(width: 12),
            // Ver Productos
            Expanded(
              child: _QuickActionButton(
                icon: Icons.liquor_rounded,
                label: 'Buscar\nProducto',
                color: AppTheme.warning,
                enabled: true,
                onTap: () => _navegarATab(3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== INFO RECIENTE ====================
  Widget _buildRecentInfo(DashboardProvider dashProvider) {
    final data = dashProvider.data;
    final ultima = dashProvider.ultimaActualizacion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RESUMEN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            if (ultima != null)
              Text(
                'Actualizado ${DateFormat('HH:mm').format(ultima)}',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary.withOpacity(0.6),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider, width: 0.5),
          ),
          child: Column(
            children: [
              _buildResumenRow(
                'Pedidos del día',
                '${data?.pedidosDia ?? 0}',
                Icons.today_rounded,
                AppTheme.primary,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: AppTheme.divider, height: 1),
              ),
              _buildResumenRow(
                'Pedidos pendientes',
                '${data?.pedidosPendientes ?? 0}',
                Icons.pending_actions_rounded,
                AppTheme.warning,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: AppTheme.divider, height: 1),
              ),
              _buildResumenRow(
                'Clientes registrados',
                _formatNumber(data?.totalClientes ?? 0),
                Icons.group_rounded,
                AppTheme.accent,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: AppTheme.divider, height: 1),
              ),
              _buildResumenRow(
                'Productos activos',
                '${data?.totalProductos ?? 0}',
                Icons.liquor_rounded,
                AppTheme.statusFacturado,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResumenRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return NumberFormat('#,###').format(number);
    }
    return '$number';
  }
}

// ==================== WIDGET: STAT CARD ====================
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color iconBgColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.iconBgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== WIDGET: QUICK ACTION BUTTON ====================
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = enabled ? 1.0 : 0.4;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withOpacity(enabled ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withOpacity(enabled ? 0.3 : 0.1),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                Icon(icon, color: color.withOpacity(opacity), size: 28),
                if (!enabled)
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.lock, size: 10, color: AppTheme.textSecondary.withOpacity(0.6)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary.withOpacity(opacity),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}