import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import 'edan_boton_sacar_foto.dart';

/// Página 06: Impacto en servicios básicos.
///
/// Checklist de los servicios de catálogo (estilo página 03): toda la fila es
/// clicable para marcar/desmarcar `afectado`; al marcar se expande inline la
/// magnitud de daño, necesidades, observaciones y el respaldo de foto/coords.
class EdanPage06 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage06({super.key, required this.localidad});

  @override
  State<EdanPage06> createState() => _EdanPage06State();
}

class _ServicioControllers {
  final nec = TextEditingController();
  final obs = TextEditingController();
}

class _EdanPage06State extends State<EdanPage06> {
  final Map<String, _ServicioControllers> _controllers = {};

  @override
  void initState() {
    super.initState();
    if (widget.localidad.serviciosBasicos.isEmpty) {
      widget.localidad.serviciosBasicos.addAll([
        EdanServicioBasicoDetalle(tipo: 'energia_electrica'),
        EdanServicioBasicoDetalle(tipo: 'agua_potable'),
        EdanServicioBasicoDetalle(tipo: 'alcantarillado'),
        EdanServicioBasicoDetalle(tipo: 'gas_domiciliario'),
        EdanServicioBasicoDetalle(tipo: 'telecomunicaciones'),
      ]);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.nec.dispose();
      c.obs.dispose();
    }
    super.dispose();
  }

  _ServicioControllers _ctrl(EdanServicioBasicoDetalle s) {
    final c = _controllers.putIfAbsent(s.tipo, _ServicioControllers.new);
    if (s.necesidadesInmediatas.isNotEmpty &&
        c.nec.text != s.necesidadesInmediatas) {
      c.nec.text = s.necesidadesInmediatas;
    }
    if (s.observaciones.isNotEmpty && c.obs.text != s.observaciones) {
      c.obs.text = s.observaciones;
    }
    return c;
  }

  Widget _campoTitulo(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }

  String? _magnitudSeleccion(EdanServicioBasicoDetalle s) {
    if (s.danoParcial) return 'parcial';
    if (s.danoTotal) return 'total';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final servicios = widget.localidad.serviciosBasicos;
    if (servicios.isEmpty) {
      return const Text(
        'No hay servicios básicos registrados.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }
    return Column(
      children: [
        for (final s in servicios) _servicioBlock(s),
      ],
    );
  }

  Widget _servicioBlock(EdanServicioBasicoDetalle s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            activeColor: AppColors.primary,
            secondary:
                Icon(_iconoDe(s.tipo), size: 20, color: AppColors.textSecondary),
            title: Text(
              s.etiqueta,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            value: s.afectado,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  s.afectado = true;
                } else {
                  s.afectado = false;
                  s.danoParcial = false;
                  s.danoTotal = false;
                  s.necesidadesInmediatas = '';
                  s.observaciones = '';
                  final c = _controllers[s.tipo];
                  c?.nec.clear();
                  c?.obs.clear();
                }
              });
            },
          ),
          if (s.afectado)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _camposServicio(s, _ctrl(s)),
            ),
        ],
      ),
    );
  }

  Widget _camposServicio(EdanServicioBasicoDetalle s, _ServicioControllers c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _campoTitulo('Magnitud de daño'),
        const SizedBox(height: 6),
        RadioGroup<String>(
          groupValue: _magnitudSeleccion(s),
          onChanged: (x) => setState(() {
            s.danoParcial = x == 'parcial';
            s.danoTotal = x == 'total';
          }),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RadioServicio(valor: 'parcial', etiqueta: 'Daño parcial'),
              _RadioServicio(valor: 'total', etiqueta: 'Daño total'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _campoTitulo('Necesidades inmediatas'),
        const SizedBox(height: 6),
        TextField(
          controller: c.nec,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Ej: Abastecimiento de agua'),
          onChanged: (v) {
            s.necesidadesInmediatas = v;
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        _campoTitulo('Observaciones'),
        const SizedBox(height: 6),
        TextField(
          controller: c.obs,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Ej: Fugas visibles'),
          onChanged: (v) {
            s.observaciones = v;
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        _bloqueFoto(s),
      ],
    );
  }

  Widget _bloqueFoto(EdanServicioBasicoDetalle s) {
    final fotoLocal = s.fotos.isNotEmpty ? s.fotos.first : null;
    final completo = fotoLocal != null || (s.fotografia?.isNotEmpty ?? false);
    final coordsOk = s.coordenadaLat != 0 || s.coordenadaLon != 0;
    final double prec = s.fotos.isNotEmpty ? s.fotos.first.precision : 0;
    final Color color = completo ? AppColors.completed : AppColors.pending;
    final String textoCoords = coordsOk
        ? '${s.coordenadaLat.toStringAsFixed(6)}, ${s.coordenadaLon.toStringAsFixed(6)}'
        : 'Coordenadas: pendiente';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            if (completo)
              EdanFotoMiniatura(
                foto: fotoLocal,
                fotografia: s.fotografia,
                width: 72,
                height: 72,
                onTap: () => EdanBotonSacarFoto.verFotoCompleta(
                  context,
                  fotos: s.fotos,
                  fotografia: s.fotografia,
                  coordenadaLat: s.coordenadaLat,
                  coordenadaLon: s.coordenadaLon,
                  seccion: 'Servicios básicos',
                  onEliminada: () => setState(() {}),
                ),
              )
            else
              GestureDetector(
                onTap: () => _foto(s),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.6)),
                  ),
                  child: Icon(
                    Icons.photo_camera_outlined,
                    size: 26,
                    color: color,
                  ),
                ),
              ),
            if (!completo)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.pending,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _bannerFoto(
          hasFoto: completo,
          hayCoords: coordsOk,
          coords: textoCoords,
          prec: prec,
          onTap: () => _foto(s),
        ),
      ],
    );
  }

  Widget _bannerFoto({
    required bool hasFoto,
    required bool hayCoords,
    required String coords,
    required double prec,
    required VoidCallback onTap,
  }) {
    final Color color = hasFoto ? AppColors.completed : AppColors.pending;
    final String titulo = hasFoto
        ? 'Foto OK'
        : 'Sin foto — es importante sacar una foto';
    final String subtitulo = hasFoto
        ? (prec > 0 ? '$coords · ±${prec.toStringAsFixed(0)}m' : coords)
        : 'Tocar para capturar coordenadas y tomar la foto';
    return Material(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                hasFoto ? Icons.check_circle_outline : Icons.photo_camera_outlined,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _foto(EdanServicioBasicoDetalle s) async {
    final ok = await EdanBotonSacarFoto.mostrarSheetFoto(
      context,
      fotos: s.fotos,
      latActual: s.coordenadaLat,
      lonActual: s.coordenadaLon,
      seccion: 'Servicios básicos',
      idLocal: widget.localidad.idLocal,
      idSeccion: s.idSeccion,
      idEdanLocalidad: widget.localidad.idServer ?? widget.localidad.idEdan,
      onCoordenadasCapturadas: (lat, lon) {
        s.coordenadaLat = lat;
        s.coordenadaLon = lon;
      },
      onFotoGuardada: (path) => s.fotografia = path,
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  IconData _iconoDe(String tipo) {
    switch (tipo) {
      case 'energia_electrica':
        return Icons.bolt_outlined;
      case 'agua_potable':
        return Icons.water_drop_outlined;
      case 'alcantarillado':
        return Icons.water_outlined;
      case 'gas_domiciliario':
        return Icons.local_fire_department_outlined;
      case 'telecomunicaciones':
        return Icons.wifi_outlined;
      default:
        return Icons.home_work_outlined;
    }
  }
}

/// Fila de radio excluyente (Magnitud de daño) dentro de un RadioGroup.
class _RadioServicio extends StatelessWidget {
  final String valor;
  final String etiqueta;

  const _RadioServicio({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => RadioGroup.maybeOf<String>(context)?.onChanged.call(valor),
      child: Row(
        children: [
          Radio<String>(value: valor, activeColor: AppColors.primary),
          Expanded(
            child: Text(etiqueta,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}