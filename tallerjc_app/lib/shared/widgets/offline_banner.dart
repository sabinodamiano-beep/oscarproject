import 'package:flutter/material.dart';

import '../../core/sync/catalog_sync_service.dart';
import '../../core/sync/connection_monitor.dart';
import '../../core/theme/app_theme.dart';

/// Franja fina bajo el buscador de las listas. Solo aparece cuando NO hay
/// conexión con el servidor. Indica de cuándo son los datos que se muestran
/// y, si ya vencieron (>24 h), lo avisa en rojo. Tocarla vuelve a probar la
/// conexión.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ConnectionMonitor.instance, CatalogSyncService.instance]),
      builder: (context, _) {
        final monitor = ConnectionMonitor.instance;
        final sync = CatalogSyncService.instance;

        if (monitor.online || monitor.estado == EstadoConexion.desconocido) {
          return const SizedBox.shrink();
        }

        final vencido = !sync.cacheVigente;
        final color = vencido ? AppTheme.error : AppTheme.warning;
        final texto = !sync.hayCache
            ? 'Sin conexión · sin datos guardados'
            : vencido
                ? 'Sin conexión · datos de más de 24 h'
                : 'Sin conexión · datos del ${_fecha(sync.ultimaSync!)}';

        return GestureDetector(
          onTap: monitor.verificando ? null : () => monitor.verificar(),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.4), width: 0.5),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    texto,
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                  ),
                ),
                if (monitor.verificando)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(color: color, strokeWidth: 1.5),
                  )
                else
                  Icon(Icons.refresh_rounded, size: 16, color: color),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fecha(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)} ${dos(d.hour)}:${dos(d.minute)}';
  }
}
