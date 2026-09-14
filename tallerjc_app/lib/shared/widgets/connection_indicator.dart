import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Widget reutilizable que muestra el estado de conexión
/// Punto verde = online, punto rojo = offline
class ConnectionIndicator extends StatelessWidget {
  final bool isConnected;

  const ConnectionIndicator({
    super.key,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? AppTheme.accent : AppTheme.error,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isConnected ? 'En línea' : 'Sin conexión',
          style: TextStyle(
            fontSize: 12,
            color: isConnected ? AppTheme.accent : AppTheme.error,
          ),
        ),
      ],
    );
  }
}