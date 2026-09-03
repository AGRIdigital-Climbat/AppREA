import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/edan/edan_documento_sync_service.dart';
import '../../../../widgets/custom_text_field.dart';

/// Muestra un diálogo de confirmación antes de eliminar un ítem.
/// Devuelve `true` si el usuario confirma la eliminación.
Future<bool> confirmarEliminacion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Confirma la eliminación, luego borra de SQLite y de la cola offline.
/// Si hay internet, llama a la API DELETE directamente.
/// Si no hay internet, guarda en `pendientes_eliminar` para el próximo sync.
/// Muestra SnackBar con el resultado.
Future<bool> eliminarItemSeccion(
  BuildContext context, {
  required EdanLocalidad localidad,
  required String? idSeccion,
  required String rutaV2,
  required String tablaSqlite,
  required String titulo,
  required String mensaje,
}) async {
  if (idSeccion == null || idSeccion.isEmpty) return false;
  final ok = await confirmarEliminacion(context, titulo: titulo, mensaje: mensaje);
  if (!ok) return false;

  final db = DatabaseHelper.instance;
  final idLocal = localidad.idLocal;

  // 1. SQLite DELETE — siempre (el item desaparece de la UI de inmediato)
  if (idLocal != null) {
    try {
      await db.eliminarFilaSeccion(tablaSqlite, idSeccion);
    } catch (e) {
      debugPrint('[Eliminar] Error SQLite DELETE $idSeccion: $e');
    }
  }

  // 2. Mover el borrado a la cola offline de seguridad y, si hay conexión,
  //    ejecutarlo en el momento. La cola (procesarColaDeletes) ya distingue
  //    un 404 (item inexistente en el servidor) y lo descarta como resuelto.
  if (idLocal != null) {
    try {
      await db.agregarPendienteEliminar(
        idLocal: idLocal,
        idServer: localidad.idServer,
        idSeccion: idSeccion,
        rutaV2: rutaV2,
        tablaSqlite: tablaSqlite,
        insertadaEnServer: true,
      );
    } catch (e) {
      debugPrint('[Eliminar] Error guardando pendiente $idSeccion: $e');
    }
  }

  // 3. Si hay internet, procesar en el momento los deletes en cola
  //    (incluido este). Un 404 se descarta como ya resuelto.
  final conectado = await ConnectivityService().checkNow();
  if (conectado && idLocal != null) {
    await EdanDocumentoSyncService().procesarColaDeletes();
  }

  // 4. SnackBar de feedback
  if (context.mounted) {
    final texto = conectado
        ? 'Eliminado exitoso'
        : 'Eliminado (se sincronizará al conectar)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  return true;
}
/// [campos] define los campos del formulario; al confirmar devuelve un mapa
/// con los valores introducidos.
Future<Map<String, String>?> showEdanItemDialog({
  required BuildContext context,
  required String titulo,
  required List<EdanDialogCampo> campos,
  Map<String, String>? valoresIniciales,
}) async {
  final controllers = <String, TextEditingController>{};
  for (final c in campos) {
    controllers[c.clave] = TextEditingController(
      text: valoresIniciales?[c.clave] ?? '',
    );
  }

  final resultado = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in campos) ...[
                CustomTextField(
                  label: '${c.numerico ? 'N° ' : ''}${c.label}',
                  controller: controllers[c.clave],
                  hint: c.hint,
                  maxLines: c.multiline ? 3 : 1,
                  keyboardType: c.numerico ? TextInputType.number : null,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final mapa = <String, String>{};
              for (final c in campos) {
                mapa[c.clave] = controllers[c.clave]!.text.trim();
              }
              Navigator.pop(ctx, mapa);
            },
            child: const Text('Guardar'),
          ),
        ],
      );
    },
  );

  for (final c in controllers.values) {
    c.dispose();
  }
  return resultado;
}

class EdanDialogCampo {
  final String clave;
  final String label;
  final String? hint;
  final bool numerico;
  final bool multiline;

  const EdanDialogCampo({
    required this.clave,
    required this.label,
    this.hint,
    this.numerico = false,
    this.multiline = false,
  });
}

/// Checkbox en tarjeta blanca clickeable (aplica el patrón de page01/page03).
/// Toda la tarjeta es tocable para marcar/desmarcar y se resalta al marcarse.
class EdanCheckTarjeta extends StatelessWidget {
  final String label;
  final IconData? icono;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;

  const EdanCheckTarjeta({
    super.key,
    required this.label,
    this.icono,
    required this.value,
    required this.onChanged,
    this.color = const Color(0xFFC0392B),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: value ? color : const Color(0xFFE2E8F0),
              width: value ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: color,
                ),
                const SizedBox(width: 12),
                if (icono != null) ...[
                  Icon(icono, size: 20, color: color),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Checkbox estilo sí/no con etiqueta.
class EdanCheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const EdanCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// Campo numérico compacto para dialogs/inserciones.
class EdanNumBuild extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;

  const EdanNumBuild({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return CustomTextField(
      label: 'N° $label',
      controller: controller,
      hint: hint,
      keyboardType: TextInputType.number,
    );
  }
}
