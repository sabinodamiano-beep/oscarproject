import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/sync/catalog_sync_service.dart';
import '../../../../core/sync/outbox_sync_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  bool _isConnected = true;
  bool _verificandoConexion = false;
  DateTime? _ultimaConsulta;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarConexion();
    });
  }

  Future<void> _verificarConexion() async {
    setState(() => _verificandoConexion = true);

    final connected = await ApiClient().testConnection();

    if (mounted) {
      setState(() {
        _isConnected = connected;
        _verificandoConexion = false;
        if (connected) _ultimaConsulta = DateTime.now();
      });
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Cerrar sesión?',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Tendrás que iniciar sesión nuevamente para acceder a la app.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.error.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Cerrar sesión', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final vendedor = authProvider.vendedor;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              _buildHeader(),
              const SizedBox(height: 24),
              _buildVendedorCard(vendedor),
              const SizedBox(height: 16),
              _buildConexionCard(),
              const SizedBox(height: 16),
              _buildCacheCard(),
              const SizedBox(height: 16),
              _buildAppInfoCard(),
              const SizedBox(height: 28),
              _buildCerrarSesionButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Perfil',
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
          child: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary, size: 20),
        ),
      ],
    );
  }

  // ==================== VENDEDOR CARD ====================
  Widget _buildVendedorCard(vendedor) {
    if (vendedor == null) return const SizedBox.shrink();

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
          // Avatar
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                _getInitials(vendedor.nombre, vendedor.apellido),
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
            vendedor.nombreCompleto,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Vendedor / Técnico',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 16),
          // Datos
          _buildDatoRow(Icons.badge_outlined, 'Cédula', vendedor.cedula),
          const SizedBox(height: 12),
          _buildDatoRow(Icons.tag, 'Código', vendedor.uidVendedor),
        ],
      ),
    );
  }

  Widget _buildDatoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.textSecondary, size: 18),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withOpacity(0.7)),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== CONEXIÓN CARD ====================
  Widget _buildConexionCard() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CONEXIÓN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              // Botón verificar
              GestureDetector(
                onTap: _verificandoConexion ? null : _verificarConexion,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_verificandoConexion)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 1.5),
                        )
                      else
                        const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _verificandoConexion ? 'Verificando...' : 'Verificar',
                        style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Estado del servidor
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (_isConnected ? AppTheme.accent : AppTheme.error).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: _isConnected ? AppTheme.accent : AppTheme.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isConnected ? 'Conectado al servidor' : 'Sin conexión al servidor',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _isConnected ? AppTheme.accent : AppTheme.error,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isConnected
                          ? 'Datos sincronizados correctamente'
                          : 'Verifica tu conexión a internet',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_ultimaConsulta != null) ...[
            const SizedBox(height: 12),
            const Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 16, color: AppTheme.textSecondary.withOpacity(0.6)),
                const SizedBox(width: 6),
                Text(
                  'Última verificación: ${_formatTime(_ultimaConsulta!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // === TARJETA DE DATOS SIN CONEXIÓN (caché local) ===
  Widget _buildCacheCard() {
    return ListenableBuilder(
      listenable: Listenable.merge([CatalogSyncService.instance, OutboxSyncService.instance]),
      builder: (context, _) {
        final sync = CatalogSyncService.instance;
        final outbox = OutboxSyncService.instance;
        final vigente = sync.cacheVigente;
        final color = !sync.hayCache
            ? AppTheme.textSecondary
            : vigente
                ? AppTheme.accent
                : AppTheme.error;
        final titulo = !sync.hayCache
            ? 'Sin datos guardados'
            : vigente
                ? 'Datos listos para trabajar sin señal'
                : 'Datos vencidos (más de 24 h)';
        final detalle = sync.ultimaSync == null
            ? 'Sincroniza con conexión para poder consultar clientes y productos sin señal.'
            : 'Última sincronización: ${_fechaHora(sync.ultimaSync!)}\n'
                '${sync.totalClientes} clientes · ${sync.totalItems} productos';

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DATOS SIN CONEXIÓN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  GestureDetector(
                    onTap: sync.sincronizando ? null : () => _sincronizarCatalogos(sync),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (sync.sincronizando)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 1.5),
                            )
                          else
                            const Icon(Icons.sync_rounded, color: AppTheme.primary, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            sync.sincronizando ? 'Sincronizando...' : 'Sincronizar',
                            style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      sync.hayCache ? Icons.storage_rounded : Icons.cloud_download_outlined,
                      color: color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detalle,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (sync.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  sync.error!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.error),
                ),
              ],
              if (outbox.porAtender > 0) ...[
                const SizedBox(height: 12),
                const Divider(color: AppTheme.divider, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      outbox.fallidos > 0 ? Icons.error_outline_rounded : Icons.cloud_upload_outlined,
                      size: 18,
                      color: outbox.fallidos > 0 ? AppTheme.error : AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${outbox.pendientes} ${outbox.pendientes == 1 ? 'pedido por enviar' : 'pedidos por enviar'}'
                        '${outbox.fallidos > 0 ? ' · ${outbox.fallidos} con error' : ''}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: outbox.procesando ? null : () => outbox.procesar(),
                      child: Text(outbox.procesando ? 'Enviando...' : 'Enviar ahora',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _sincronizarCatalogos(CatalogSyncService sync) async {
    final ok = await sync.sincronizar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Catálogos actualizados: ${sync.totalClientes} clientes, ${sync.totalItems} productos'
            : (sync.error ?? 'No se pudo sincronizar')),
        backgroundColor: ok ? AppTheme.accent : AppTheme.error,
      ),
    );
  }

  static String _fechaHora(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }

  // === TARJETA DE INFORMACIÓN DE LA APP ===
  Widget _buildAppInfoCard() {
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
            'APLICACIÓN',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          _buildAppInfoRow(Icons.apps_rounded, 'Nombre', ApiConstants.appName),
          const SizedBox(height: 12),
          _buildAppInfoRow(Icons.info_outline, 'Versión', 'v${ApiConstants.appVersion}'),
          const SizedBox(height: 12),
          _buildAppInfoRow(Icons.dns_outlined, 'Servidor', _getServerDisplay()),
          const SizedBox(height: 12),
          _buildAppInfoRow(Icons.architecture_rounded, 'Arquitectura', 'Clean Architecture + Provider'),
        ],
      ),
    );
  }

  Widget _buildAppInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.textSecondary.withOpacity(0.6), size: 18),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary.withOpacity(0.7)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ==================== CERRAR SESIÓN ====================
  Widget _buildCerrarSesionButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _cerrarSesion,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 20),
            SizedBox(width: 10),
            Text(
              'Cerrar Sesión',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================
  String _getInitials(String nombre, String apellido) {
    final n = nombre.isNotEmpty ? nombre[0] : '';
    final a = apellido.isNotEmpty && apellido != '.' ? apellido[0] : '';
    return '$n$a'.toUpperCase();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year} $h:$m';
  }

  String _getServerDisplay() {
    final url = ApiConstants.baseUrl;
    // Extraer solo host:port
    final uri = Uri.tryParse(url);
    if (uri != null) {
      return '${uri.host}:${uri.port}';
    }
    return url;
  }
}