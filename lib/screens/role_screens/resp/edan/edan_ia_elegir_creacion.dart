import 'package:flutter/material.dart';

import '../../../../config/theme.dart';
import '../../../../providers/edan_ia_borrador_provider.dart';
import '../../../../services/auth_service.dart';
import '../../ugr/ugr_route.dart';
import 'edan_form_wizard.dart';
import 'edan_ia_asistente_screen.dart';

/// Diálogo de elección al apretar el FAB de `+`.
///
/// Antes el FAB abría directo al wizard. Ahora deja decidir cómo se llena la
/// ficha: el formulario paso a paso o el asistente conversacional con IA.
///
/// Se resuelve por [Navigator.pop] con el valor, no abre pantallas por su
/// cuenta, para que cada pantalla mantenga su propio `refresh()` de la lista.
enum EdanModoCreacion { wizard, asistenteIa }

/// Muestra el diálogo. Devuelve el modo elegido, o `null` si se cancela.
Future<EdanModoCreacion?> pedirModoCreacionEdan(BuildContext context) {
  return showDialog<EdanModoCreacion>(
    context: context,
    builder: (ctx) => const _DialogoModoCreacion(),
  );
}

class _DialogoModoCreacion extends StatelessWidget {
  const _DialogoModoCreacion();

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nueva ficha EDAN',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 2),
          Text(
            'Elegí cómo querés completarla',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      // Con `shrinkWrap` y scroll propio: en pantallas bajas el diálogo no
      // desborda ni tira los avisos de layout que se vieron en la prueba de
      // campo.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Opcion(
              clave: 'edan_opcion_asistente_ia',
              icono: Icons.mic_none_rounded,
              titulo: 'Llenar hablando',
              descripcion:
                  'Contá lo que pasó por chat y la ficha se arma sola. '
                  'Queda guardada en el celular.',
              colorPrimario: primary,
              destacada: true,
              insignia: 'Recomendado',
              onTap: () =>
                  Navigator.of(context).pop(EdanModoCreacion.asistenteIa),
            ),
            const SizedBox(height: 10),
            _Opcion(
              clave: 'edan_opcion_wizard',
              icono: Icons.edit_note_rounded,
              titulo: 'Usar el formulario',
              descripcion:
                  'Recorré las secciones una por una y completá los datos vos.',
              colorPrimario: primary,
              onTap: () => Navigator.of(context).pop(EdanModoCreacion.wizard),
            ),
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
  final String descripcion;
  final Color colorPrimario;

  /// `true` para la opción recomendada: fondo tintado, borde del color de la
  /// paleta y texto en alto contraste. La jerarquía dice cuál es el camino
  /// sugerido sin tener que leer.
  final bool destacada;
  final String? insignia;
  final VoidCallback onTap;

  const _Opcion({
    required this.clave,
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.colorPrimario,
    required this.onTap,
    this.destacada = false,
    this.insignia,
  });

  @override
  Widget build(BuildContext context) {
    final fondo = destacada
        ? colorPrimario.withValues(alpha: 0.08)
        : AppColors.surface;
    final borde = destacada ? colorPrimario : AppColors.divider;

    return Semantics(
      button: true,
      selected: false,
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key(clave),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borde,
                width: destacada ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Icono(icono: icono, color: colorPrimario, destacado: destacada),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // `Wrap` y no `Row`: en un celular angosto (o con fuente
                        // grande por accesibilidad) la insignia baja de línea en
                        // vez de empujar el título fuera de la tarjeta, que era
                        // el desbordamiento que se veía en la prueba de campo.
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              titulo,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (insignia != null)
                              _Insignia(texto: insignia!, color: colorPrimario),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          descripcion,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, top: 10),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cuadro redondeado del ícono: en línea con las tarjetas del app, no con un
/// `CircleAvatar` que se ve de otra librería.
class _Icono extends StatelessWidget {
  final IconData icono;
  final Color color;
  final bool destacado;

  const _Icono({
    required this.icono,
    required this.color,
    required this.destacado,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: destacado ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icono, color: color, size: 22),
    );
  }
}

class _Insignia extends StatelessWidget {
  final String texto;
  final Color color;

  const _Insignia({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Colors.white,
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
        ugrRoute(const EdanFormWizard(), palette: Palettes.rea),
      );
      return creado == true;

    case EdanModoCreacion.asistenteIa:
      final userId = AuthService.instance.userId;
      if (userId == null) {
        _avisar(
          context,
          'No se pudo obtener tu usuario. Volvé a iniciar sesión.',
        );
        return false;
      }
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
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(mensaje), backgroundColor: AppColors.error),
  );
}
