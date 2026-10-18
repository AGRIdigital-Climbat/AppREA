/// El paso final del asistente: fotos y coordenadas.
///
/// Llega después de la conversación, nunca durante. Una foto es una acción de
/// cámara y el micrófono está hablando: pedirla por voz hace que la persona
/// suelte el teléfono a medio llenar. Además las fotos son lo único que la IA
/// no puede inventar, así que tienen que quedar a cargo de una persona.
///
/// El listado sale de [slotsDeFoto], o sea de la [EdanLocalidad] ya traducida:
/// si un ítem no llegó a la ficha, no hay nada que fotografiar.
///
/// La captura usa el mismo camino que el wizard ([EdanBotonSacarFoto]), con su
/// regla de seguridad: primero la coordenada GPS, después la foto.
library;

import 'package:flutter/material.dart';

import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/edan/edan_store.dart';
import '../../../../services/edan_ia/edan_slots_foto.dart';
import 'edan_boton_sacar_foto.dart';

/// Listado de pendientes de foto, agrupado por sección.
class EdanIaPasoFotosScreen extends StatefulWidget {
  /// La localidad ya traducida. Se muta: las coordenadas y las fotos se
  /// escriben acá mismo y las guarda quien la abrió.
  final EdanLocalidad localidad;

  /// Se llama cuando la persona terminó. Recibe la misma localidad.
  final void Function(EdanLocalidad localidad) onListo;

  /// Store V2 para registrar/encolar cada foto al capturarla (Etapa 5). Sin
  /// esto la foto quedaba solo en memoria y nunca subía.
  final EdanStore? store;

  const EdanIaPasoFotosScreen({
    super.key,
    required this.localidad,
    required this.onListo,
    this.store,
  });

  @override
  State<EdanIaPasoFotosScreen> createState() => _EdanIaPasoFotosScreenState();
}

class _EdanIaPasoFotosScreenState extends State<EdanIaPasoFotosScreen> {
  /// Oculta los que ya están completos, para no hacer scrolling infinito.
  bool _soloPendientes = true;

  void _refrescar() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final porSeccion = slotsDeFotoPorSeccion(widget.localidad);
    final resumen = resumenFotos(widget.localidad);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotos y coordenadas'),
        actions: [
          if (resumen.total > 0)
            IconButton(
              tooltip: _soloPendientes ? 'Ver todo' : 'Solo pendientes',
              onPressed: () => setState(() => _soloPendientes = !_soloPendientes),
              icon: Icon(_soloPendientes ? Icons.filter_alt : Icons.filter_alt_off),
            ),
        ],
      ),
      body: resumen.total == 0
          ? const _SinFotos()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _Encabezado(resumen: resumen),
                for (final e in porSeccion.entries) ...[
                  if (_itemsDe(e).isNotEmpty)
                    _Seccion(titulo: kEdanSeccionesConFoto[e.key] ?? e.key),
                  for (final slot in _itemsDe(e))
                    _Tile(slot: slot, onTap: () => _capturar(slot)),
                ],
              ],
            ),
      bottomNavigationBar: _Pie(
        pendientes: resumen.pendientes,
        total: resumen.total,
        onListo: resumen.pendientes == 0
            ? () => widget.onListo(widget.localidad)
            : null,
      ),
    );
  }

  /// Los ítems a pintar según el filtro, ya filtrados por completado.
  List<EdanSlotFoto> _itemsDe(MapEntry<String, List<EdanSlotFoto>> e) =>
      _soloPendientes ? e.value.where((s) => !s.completo).toList() : e.value;

  Future<void> _capturar(EdanSlotFoto slot) async {
    final item = slot.item;
    // Etapa 5: el uuid nace aquí para que la foto quede registrada con su
    // dueña definitiva (el guardado posterior la reutiliza, no duplica).
    final uuid = EdanBotonSacarFoto.asegurarUuidRegistro(item);
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: item.fotos,
      latActual: item.coordenadaLat,
      lonActual: item.coordenadaLon,
      // Etiqueta legible, como en las páginas del wizard. La clave de la
      // sección no se pasa porque la usa el wizard con su propio nombre.
      seccion: slot.titulo,
      idLocal: widget.localidad.idLocal,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        item.coordenadaLat = lat;
        item.coordenadaLon = lon;
      },
      onFotoGuardada: (ruta) => item.fotografia = ruta,
      store: widget.store,
      uuidRegistro: uuid,
      rutaSeccion: slot.seccion,
    );
    if (ok && mounted) _refrescar();
  }
}

class _Encabezado extends StatelessWidget {
  final ({int total, int conFoto, int soloCoordenada, int pendientes}) resumen;

  const _Encabezado({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final listo = resumen.pendientes == 0;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: listo ? const Color(0x1A4CAF50) : const Color(0x1AF59E0B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            listo ? Icons.check_circle : Icons.photo_camera,
            color: listo ? AppColors.aprobado : const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              listo
                  ? 'Todo listo. Las ${resumen.total} fotos están con su coordenada.'
                  : 'Faltan ${resumen.pendientes} de ${resumen.total} fotos. '
                      '${resumen.conFoto} ya tienen foto y '
                      '${resumen.soloCoordenada} solo la coordenada.',
              style: const TextStyle(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  const _Seccion({required this.titulo});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(
          titulo.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Colors.grey.shade600,
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  final EdanSlotFoto slot;
  final VoidCallback onTap;

  const _Tile({required this.slot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: slot.completo ? AppColors.aprobado : AppColors.divider,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          slot.tieneFoto
              ? (slot.tieneCoordenada ? Icons.check_circle : Icons.location_on)
              : Icons.add_a_photo_outlined,
          color: slot.completo
              ? AppColors.aprobado
              : (slot.tieneCoordenada ? const Color(0xFFF59E0B) : Colors.grey),
        ),
        title: Text(slot.etiqueta, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          slot.tieneFoto && slot.tieneCoordenada
              ? 'Foto y coordenada listas'
              : slot.tieneCoordenada
                  ? 'Falta la foto'
                  : slot.tieneFoto
                      ? 'Falta la coordenada'
                      : 'Falta foto y coordenada',
          style: TextStyle(
            color: slot.completo ? AppColors.aprobado : Colors.grey.shade700,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _SinFotos extends StatelessWidget {
  const _SinFotos();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No hay nada que fotografiar',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'La conversación no dejó ningún daño anotado. Si querés '
                'cargar algo, volvé a la conversación y contá qué pasó.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
}

class _Pie extends StatelessWidget {
  final int pendientes;
  final int total;
  final VoidCallback? onListo;

  const _Pie({required this.pendientes, required this.total, this.onListo});

  @override
  Widget build(BuildContext context) {
    final bloqueado = onListo == null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bloqueado && total > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Se puede guardar igual, pero los $pendientes ítems sin foto '
                  'quedan marcados como incompletos.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            FilledButton(
              onPressed: onListo,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.divider,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                pendientes == 0 ? 'Guardar ficha' : 'Guardar igual',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
