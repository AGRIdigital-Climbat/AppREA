import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../config/theme.dart';
import '../../../../providers/edan_ia_borrador_provider.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/edan/edan_store_v2.dart';
import '../../ugr/ugr_route.dart';
import 'edan_form_wizard.dart';
import 'edan_ia_asistente_screen.dart';
import '../../../../services/app_logger_ui.dart';

/// Diálogo de elección al apretar el FAB de `+`.
///
/// Antes el FAB abría directo al wizard. Ahora deja decidir cómo se llena la
/// ficha: el formulario paso a paso o el asistente conversacional con IA.
///
/// Se resuelve por [Navigator.pop] con el valor, no abre pantallas por su
/// cuenta, para que cada pantalla mantenga su propio `refresh()` de la lista.
enum EdanModoCreacion { wizard, asistenteIa }

/// Muestra el diálogo. Devuelve el modo elegido, o `null` si se cancela.
///
/// [hayInternet] fija el veredicto de red y evita el chequeo real. Sin él, la
/// opción de hablar solo aparece si hay conexión, porque sin internet el
/// asistente no puede entender nada.
Future<EdanModoCreacion?> pedirModoCreacionEdan(
  BuildContext context, {
  @visibleForTesting bool? hayInternet,
}) {
  return showDialog<EdanModoCreacion>(
    context: context,
    builder: (ctx) => _DialogoModoCreacion(hayInternetFijado: hayInternet),
  );
}

class _DialogoModoCreacion extends StatefulWidget {
  final bool? hayInternetFijado;

  const _DialogoModoCreacion({this.hayInternetFijado});

  @override
  State<_DialogoModoCreacion> createState() => _DialogoModoCreacionState();
}

class _DialogoModoCreacionState extends State<_DialogoModoCreacion> {
  final _conectividad = ConnectivityService();

  /// `null` = todavía no llegó el veredicto. Se siembra con el estado global
  /// (que `main` ya mantiene al día) para no hacer aparecer y desaparecer la
  /// opción, y se corrige con un chequeo real apenas abre el diálogo.
  bool? _hayInternet;
  StreamSubscription<bool>? _suscripcion;

  @override
  void initState() {
    super.initState();
    final fijado = widget.hayInternetFijado;
    if (fijado != null) {
      // Veredicto dado: no se consulta nada, así el test no toca la plataforma.
      _hayInternet = fijado;
      return;
    }
    if (_conectividad.chequeoCompletado) {
      _hayInternet = _conectividad.isConnected;
    }
    // El diálogo está abierto: si se cae la red mientras se elige, la opción
    // que no va a funcionar tiene que desaparecer sola.
    _suscripcion = _conectividad.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
    // `checkNow` y no solo el valor cacheado: es lo que usa el resto de la app
    // como puerta fiable antes de una operación de red.
    _conectividad.checkNow().then((v) {
      if (mounted) setState(() => _hayInternet = v);
    });
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Antes de la primera respuesta del chequeo se ofrece: la comprobación
    // tarda y el formulario siempre está. Si el chequeo dice que no hay red,
    // el asistente no aparece.
    final hayInternet = _hayInternet ?? true;
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: const Text(
        'Nueva ficha EDAN',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Opcion(
              clave: 'edan_opcion_wizard',
              icono: Icons.edit_note_rounded,
              titulo: 'Usar el formulario',
              onTap: () => Navigator.of(context).pop(EdanModoCreacion.wizard),
            ),
            // El asistente necesita el puente: sin internet no puede entender
            // nada, y ofrecerlo es prometer algo que no va a pasar. El
            // formulario, que es local, siempre está.
            if (hayInternet) ...[
              const SizedBox(height: 8),
              _Opcion(
                clave: 'edan_opcion_asistente_ia',
                icono: Icons.mic_none_rounded,
                titulo: 'Llenar hablando',
                onTap: () => Navigator.of(context)
                    .pop(EdanModoCreacion.asistenteIa),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _Opcion extends StatelessWidget {
  final String clave;
  final IconData icono;
  final String titulo;
  final VoidCallback onTap;

  const _Opcion({
    required this.clave,
    required this.icono,
    required this.titulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key(clave),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(icono, color: AppColors.textSecondary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre la creación de una ficha según el modo elegido en el diálogo.
///
/// Devuelve `true` si la ficha quedó guardada, para que quien llama refresque
/// la lista. La pantalla de IA guarda en SQLite y además muestra el paso
/// extra de fotos y coordenadas.
Future<bool> abrirCreacionEdan(
  BuildContext context,
  EdanModoCreacion modo,
) async {
  switch (modo) {
    case EdanModoCreacion.wizard:
      final creado = await Navigator.of(context).push<bool>(
        ugrRoute(
          EdanFormWizard(storeV2: EdanStoreV2.instance),
          palette: Palettes.rea,
        ),
      );
      return creado == true;

    case EdanModoCreacion.asistenteIa:
      // El diálogo ya esconde la opción sin red. Esto cubre la red que se cae
      // entre elegir y abrir, y cualquier otro llamador: entrar a una pantalla
      // de chat que no puede entender lo que se le dice es peor que no entrar.
      final conectado = await ConnectivityService().checkNow();
      if (!conectado) {
        if (context.mounted) {
          _avisar(
            context,
            'Necesitás internet para llenar la ficha hablando.',
          );
        }
        return false;
      }
      final userId = AuthService.instance.userId;
      if (userId == null) {
        if (context.mounted) {
          _avisar(
            context,
            'No se pudo obtener tu usuario. Volvé a iniciar sesión.',
          );
        }
        return false;
      }
      if (!context.mounted) return false;
      final guardado = await Navigator.of(context).push<bool>(
        ugrRoute(
          EdanIaAsistenteScreen(
            provider: EdanIaBorradorProvider(),
            usuarioId: userId,
          ),
          palette: Palettes.rea,
        ),
      );
      return guardado == true;
  }
}

void _avisar(BuildContext context, String mensaje) {
  showAppSnackBar(context, 
    SnackBar(content: Text(mensaje), backgroundColor: AppColors.error),
  );
}
