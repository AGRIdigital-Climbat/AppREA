import 'package:flutter/material.dart';

/// Estado de guardado/envío de una sección individual del EDAN.
///
/// Cada sección del formulario (01, 02, ..., 13) se guarda y envíta de forma
/// independiente. Esta clase rastrea si los datos están guardados localmente,
/// pendientes de envío o ya enviados al servidor.
class EdanSeccionEstado {
  final String seccionId;
  final bool guardadaLocal;
  final bool enviadaServidor;
  final bool pendienteEnvio;
  final String? errorEnvio;
  final DateTime? fechaGuardado;
  final DateTime? fechaEnvio;

  const EdanSeccionEstado({
    required this.seccionId,
    this.guardadaLocal = false,
    this.enviadaServidor = false,
    this.pendienteEnvio = false,
    this.errorEnvio,
    this.fechaGuardado,
    this.fechaEnvio,
  });

  EdanSeccionEstado copyWith({
    bool? guardadaLocal,
    bool? enviadaServidor,
    bool? pendienteEnvio,
    String? errorEnvio,
    DateTime? fechaGuardado,
    DateTime? fechaEnvio,
  }) {
    return EdanSeccionEstado(
      seccionId: seccionId,
      guardadaLocal: guardadaLocal ?? this.guardadaLocal,
      enviadaServidor: enviadaServidor ?? this.enviadaServidor,
      pendienteEnvio: pendienteEnvio ?? this.pendienteEnvio,
      errorEnvio: errorEnvio ?? this.errorEnvio,
      fechaGuardado: fechaGuardado ?? this.fechaGuardado,
      fechaEnvio: fechaEnvio ?? this.fechaEnvio,
    );
  }

  IconData get icono {
    if (enviadaServidor) return Icons.cloud_done;
    if (pendienteEnvio) return Icons.cloud_upload;
    if (guardadaLocal) return Icons.check_circle;
    return Icons.remove_circle_outline;
  }

  Color get color {
    if (enviadaServidor) return const Color(0xFF4CAF50);
    if (pendienteEnvio) return const Color(0xFF2196F3);
    if (guardadaLocal) return const Color(0xFF4CAF50);
    return const Color(0xFF9E9E9E);
  }

  String get etiqueta {
    if (enviadaServidor) return 'Enviada';
    if (pendienteEnvio) return 'Pendiente envío';
    if (guardadaLocal) return 'Guardada';
    return 'Pendiente';
  }
}
