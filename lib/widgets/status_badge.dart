import 'package:flutter/material.dart';
import '../config/theme.dart';

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class SyncIndicator extends StatelessWidget {
  final bool isSynced;
  final int? errorCount;

  const SyncIndicator({
    super.key,
    required this.isSynced,
    this.errorCount,
  });

  @override
  Widget build(BuildContext context) {
    if (isSynced) {
      return const Icon(
        Icons.cloud_done,
        size: 20,
        color: AppColors.completed,
      );
    }

    if (errorCount != null && errorCount! >= 3) {
      return const Icon(
        Icons.cloud_off,
        size: 20,
        color: AppColors.error,
      );
    }

    return const Icon(
      Icons.cloud_upload,
      size: 20,
      color: AppColors.pending,
    );
  }
}

class ConnectionBanner extends StatelessWidget {
  final bool isConnected;

  const ConnectionBanner({
    super.key,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    if (isConnected) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.pending,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off,
            size: 16,
            color: Colors.white,
          ),
          SizedBox(width: 8),
          Text(
            'Sin conexión - Los reportes se guardarán localmente',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
