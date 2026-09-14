import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gyfsoftware_movil/features/items/presentation/providers/item_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../domain/entities/item.dart';

class ItemDetalleScreen extends StatefulWidget {
  final String coditems;

  const ItemDetalleScreen({super.key, required this.coditems});

  @override
  State<ItemDetalleScreen> createState() => _ItemDetalleScreenState();
}

class _ItemDetalleScreenState extends State<ItemDetalleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ItemsProvider>().cargarDetalle(widget.coditems);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Detalle del Producto'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            context.read<ItemsProvider>().limpiarDetalle();
            Navigator.pop(context);
          },
        ),
      ),
      body: Consumer<ItemsProvider>(
        builder: (context, provider, _) {
          if (provider.estaCargandoDetalle) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (provider.errorDetalle != null) {
            return ErrorDisplay(
              message: provider.errorDetalle!,
              onRetry: () => provider.cargarDetalle(widget.coditems),
            );
          }

          final item = provider.itemDetalle;
          if (item == null) {
            return const ErrorDisplay(message: 'Producto no encontrado');
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeaderCard(item),
                const SizedBox(height: 16),
                _buildPrecioCard(item),
                const SizedBox(height: 16),
                _buildInfoCard(item),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==================== HEADER CARD ====================
  Widget _buildHeaderCard(Item item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.liquor_rounded, color: AppTheme.primary, size: 34),
          ),
          const SizedBox(height: 14),
          Text(
            item.desitems,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'COD: ${item.coditems}',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (item.nombreLinea.isNotEmpty || item.nombrePresentacion.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [item.nombreLinea, item.nombrePresentacion].where((t) => t.isNotEmpty).join(' · '),
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== PRECIO CARD ====================
  Widget _buildPrecioCard(Item item) {
    final tiene = item.dolPre > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PRECIO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          _buildPrecioRow(item.cantunidad > 1 ? 'Por caja (USD)' : 'Por unidad (USD)', item.dolPre, AppTheme.accent),
          if (item.cantunidad > 1) ...[
            _buildPrecioRow('Por botella (USD)', item.precioBotella, AppTheme.primary),
            _buildPrecioRow('Botellas por caja', item.cantunidad, AppTheme.textSecondary, esMoneda: false),
          ],
          if (!tiene)
            const Text('Este producto no tiene precio cargado en el sistema',
                style: TextStyle(fontSize: 12, color: AppTheme.warning)),
        ],
      ),
    );
  }

  Widget _buildPrecioRow(String label, double precio, Color color, {bool esMoneda = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            precio > 0 ? (esMoneda ? '\$${precio.toStringAsFixed(2)}' : precio.toStringAsFixed(0)) : '-',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: precio > 0 ? color : AppTheme.textSecondary.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== INFO CARD ====================
  Widget _buildInfoCard(Item item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INFORMACIÓN',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          if (item.tieneCodBarra)
            _buildInfoRow(Icons.qr_code_rounded, 'Código de barra', item.codBarra),
          _buildInfoRow(
            Icons.liquor_rounded,
            'Venta',
            '${item.vendeEnCaja ? "Caja" : ""}${item.vendeEnCaja && item.vendeEnBotella ? " / " : ""}${item.vendeEnBotella ? "Botella" : ""}',
          ),
          _buildInfoRow(
            Icons.circle,
            'Estado',
            item.activo == '1' ? 'Activo' : 'Inactivo',
            valueColor: item.activo == '1' ? AppTheme.accent : AppTheme.error,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withOpacity(0.7)),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: valueColor ?? AppTheme.textPrimary,
                    fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}