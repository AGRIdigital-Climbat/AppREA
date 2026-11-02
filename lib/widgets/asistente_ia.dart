import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../providers/asistente_ia_provider.dart';
import '../services/permission_service.dart';
import 'asistente_ia/asistente_ia_bottom_sheet.dart';

/// FAB pequeño de acceso al asistente IA. Pensado para apilarse sobre el FAB
/// principal (u ocupar su lugar cuando no lo hay): siempre visible y abierto
/// desde cualquier pantalla sin depender del AppBar.
class AsistenteIaFab extends StatelessWidget {
  final Color? fabColor;
  const AsistenteIaFab({super.key, this.fabColor});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      // heroTag único: en resp_screen convive con el FAB «Nuevo reporte»
      // (sin él, ambos heredan el tag default y el HeroController revienta
      // al empujar cualquier ruta).
      heroTag: 'asistente_ia_fab',
      tooltip: 'Asistente con IA',
      backgroundColor: fabColor ?? PaletteScope.of(context).primary,
      foregroundColor: Colors.white,
      onPressed: () => _abrirAsistente(context),
      child: const Icon(Icons.smart_toy),
    );
  }

  Future<void> _abrirAsistente(BuildContext context) async {
    final tienePermiso = await PermissionService.requestMicrophonePermission();
    if (!tienePermiso && context.mounted) {
      PermissionService.showPermissionDeniedDialog(context, 'micrófono');
      return;
    }
    if (!context.mounted) return;

    final provider = AsistenteIAProvider();

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AsistenteIABottomSheet(provider: provider),
      );
    }
  }
}

/// FAB pequeño contextual para el wizard EDAN. Muestra el asistente con
/// contexto de la página/sección actual y filtra por grupo documental.
class AsistenteIaFormFab extends StatelessWidget {
  final String pageTitle;
  final String pageKey;
  final Color? fabColor;

  static const int _grupoId = 2;

  const AsistenteIaFormFab({
    super.key,
    required this.pageTitle,
    required this.pageKey,
    this.fabColor,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'asistente_ia_form_fab',
      tooltip: 'Ayuda con esta sección',
      backgroundColor: fabColor ?? PaletteScope.of(context).primary,
      foregroundColor: Colors.white,
      onPressed: () => _abrirAsistente(context),
      child: const Icon(Icons.smart_toy),
    );
  }

  Future<void> _abrirAsistente(BuildContext context) async {
    final tienePermiso = await PermissionService.requestMicrophonePermission();
    if (!tienePermiso && context.mounted) {
      PermissionService.showPermissionDeniedDialog(context, 'micrófono');
      return;
    }
    if (!context.mounted) return;

    final provider = AsistenteIAProvider(
      grupoId: _grupoId,
      contextoPantalla: pageTitle,
    );

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AsistenteIABottomSheet(provider: provider),
      );
    }
  }
}
