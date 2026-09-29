import 'package:flutter/material.dart';

import '../../providers/asistente_ia_provider.dart';
import '../../services/permission_service.dart';
import 'asistente_ia_bottom_sheet.dart';

class AsistenteIABoton extends StatefulWidget {
  const AsistenteIABoton({super.key});

  @override
  State<AsistenteIABoton> createState() => _AsistenteIABotonState();
}

class _AsistenteIABotonState extends State<AsistenteIABoton> {
  AsistenteIAProvider? _provider;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'asistente_ia',
      onPressed: () => _abrirAsistente(context),
      backgroundColor: const Color(0xFF2563EB),
      tooltip: 'Asistente Jurídico',
      child: const Icon(Icons.smart_toy, color: Colors.white),
    );
  }

  Future<void> _abrirAsistente(BuildContext context) async {
    final tienePermiso = await PermissionService.requestMicrophonePermission();
    if (!tienePermiso && context.mounted) {
      PermissionService.showPermissionDeniedDialog(context, 'micrófono');
      return;
    }
    if (!context.mounted) return;

    _provider = AsistenteIAProvider();

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AsistenteIABottomSheet(provider: _provider!),
      );
    }
  }
}
