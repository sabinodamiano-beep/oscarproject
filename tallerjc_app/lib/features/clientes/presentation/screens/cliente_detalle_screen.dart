import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gyfsoftware_movil/features/clientes/presentation/providers/cliente_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../domain/entities/cliente.dart';
import '../widgets/cliente_cxc_card.dart';


class ClienteDetalleScreen extends StatefulWidget {
  final int uidCliente;

  const ClienteDetalleScreen({super.key, required this.uidCliente});

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientesProvider>().cargarDetalle(widget.uidCliente);
    });
  }

  @override
  void dispose() {
    // No limpiar aquí para evitar rebuild innecesario
    super.dispose();
  }

  Future<void> _llamar(String telefono) async {
    final uri = Uri.parse('tel:$telefono');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Detalle del Cliente'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            context.read<ClientesProvider>().limpiarDetalle();
            Navigator.pop(context);
          },
        ),
      ),
      body: Consumer<ClientesProvider>(
        builder: (context, provider, _) {
          if (provider.estaCargandoDetalle) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (provider.errorDetalle != null) {
            return ErrorDisplay(
              message: provider.errorDetalle!,
              onRetry: () => provider.cargarDetalle(widget.uidCliente),
            );
          }

          final cliente = provider.clienteDetalle;
          if (cliente == null) {
            return const ErrorDisplay(message: 'Cliente no encontrado');
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeaderCard(cliente),
                const SizedBox(height: 16),
                ClienteCxcCard(
                  uidCliente: widget.uidCliente,
                  nombreCliente: cliente.nombreCompleto,
                ),
                const SizedBox(height: 16),
                _buildTelefonosCard(cliente),
                const SizedBox(height: 16),
                _buildInfoCard(cliente),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==================== HEADER CARD ====================
  Widget _buildHeaderCard(Cliente cliente) {
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
          // Avatar grande
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                _getInitials(cliente),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Nombre
          Text(
            cliente.nombreCompleto,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          // Cédula
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              cliente.cedulaCompleta,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Código
          Text(
            'Código: ${cliente.codigo}',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TELÉFONOS ====================
  Widget _buildTelefonosCard(Cliente cliente) {
    final telefonos = <Map<String, String>>[];

    if (cliente.tieneTelefonoCelular) {
      telefonos.add({'label': 'Celular', 'numero': cliente.telefonoCelular, 'icon': 'cell'});
    }
    if (cliente.tieneTelefonoCasa) {
      telefonos.add({'label': 'Casa', 'numero': cliente.telefonoCasa, 'icon': 'home'});
    }
    if (cliente.tieneTelefonoOficina) {
      telefonos.add({'label': 'Oficina', 'numero': cliente.telefonoOficina, 'icon': 'work'});
    }

    if (telefonos.isEmpty) {
      return const SizedBox.shrink();
    }

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
            'TELÉFONOS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          ...telefonos.map((t) => Padding(
                padding: EdgeInsets.only(bottom: t != telefonos.last ? 12 : 0),
                child: _buildTelefonoRow(t['label']!, t['numero']!, t['icon']!),
              )),
        ],
      ),
    );
  }

  Widget _buildTelefonoRow(String label, String numero, String iconType) {
    IconData icon;
    switch (iconType) {
      case 'home':
        icon = Icons.home_rounded;
        break;
      case 'work':
        icon = Icons.business_rounded;
        break;
      default:
        icon = Icons.phone_android_rounded;
    }

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.accent, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withOpacity(0.7)),
              ),
              Text(
                numero,
                style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        // Botón llamar
        GestureDetector(
          onTap: () => _llamar(numero),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.call_rounded, color: AppTheme.primary, size: 20),
          ),
        ),
      ],
    );
  }

  // ==================== INFO ADICIONAL ====================
  Widget _buildInfoCard(Cliente cliente) {
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
          if (cliente.direccion.isNotEmpty)
            _buildInfoRow(Icons.location_on_outlined, 'Dirección', cliente.direccion),
          if (cliente.email.isNotEmpty)
            _buildInfoRow(Icons.email_outlined, 'Email', cliente.email),
          if (cliente.fechaIngreso != null)
            _buildInfoRow(
              Icons.calendar_today_outlined,
              'Fecha de ingreso',
              DateFormat('dd/MM/yyyy').format(cliente.fechaIngreso!),
            ),
          if (cliente.tieneComentario)
            _buildInfoRow(Icons.comment_outlined, 'Comentario', cliente.comentario),
          if (cliente.direccion.isEmpty &&
              cliente.email.isEmpty &&
              cliente.fechaIngreso == null &&
              !cliente.tieneComentario)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Sin información adicional',
                  style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
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
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(Cliente c) {
    final n = c.nombres.isNotEmpty ? c.nombres[0] : '';
    final a = c.apellidos.isNotEmpty && c.apellidos != '.' ? c.apellidos[0] : '';
    return '$n$a'.toUpperCase();
  }
}