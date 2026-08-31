import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import 'edan_boton_sacar_foto.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';

/// Página 06: Impacto en servicios básicos.
class EdanPage06 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage06({super.key, required this.localidad});

  @override
  State<EdanPage06> createState() => _EdanPage06State();
}

class _EdanPage06State extends State<EdanPage06> {
  final _nec = TextEditingController();
  bool _parcial = false;
  bool _total = false;

  @override
  void dispose() {
    _nec.dispose();
    super.dispose();
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
      children: servicios.map((s) {
        return EdanItemCard(
          titulo: s.etiqueta,
          subtitulo: [
            if (s.danoParcial) 'Daño parcial',
            if (s.danoTotal) 'Daño total',
          ].join(' · '),
          icono: _iconoDe(s.tipo),
          onEditar: () => _editar(s),
          onEliminar: () => _eliminar(s),
          onRespaldar: () => _capturarRespaldo(s),
          respaldo: s,
          seccionRespaldo: 'Servicios básicos',
          onFotoEliminada: () => setState(() {}),
        );
      }).toList(),
    );
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

  Future<void> _editar(EdanServicioBasicoDetalle s) async {
    _parcial = s.danoParcial;
    _total = s.danoTotal;
    _nec.text = s.necesidadesInmediatas;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: Text('Servicio: ${s.etiqueta}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EdanCheckRow(label: 'Daño parcial', value: _parcial,
                  onChanged: (x) => setLocal(() => _parcial = x)),
              EdanCheckRow(label: 'Daño total', value: _total,
                  onChanged: (x) => setLocal(() => _total = x)),
              const SizedBox(height: 8),
              TextField(controller: _nec, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Necesidades inmediatas')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (!mounted) return;

    setState(() {
      s.danoParcial = _parcial;
      s.danoTotal = _total;
      s.afectado = _parcial || _total;
      s.necesidadesInmediatas = _nec.text;
    });
  }

  Future<void> _capturarRespaldo(EdanServicioBasicoDetalle s) async {
    final ok = await EdanBotonSacarFoto.capturarRespaldo(
      context,
      fotos: s.fotos,
      latActual: s.coordenadaLat,
      lonActual: s.coordenadaLon,
      onCoordenadasCapturadas: (lat, lon) {
        s.coordenadaLat = lat;
        s.coordenadaLon = lon;
      },
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _eliminar(EdanServicioBasicoDetalle s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar servicio?'),
        content: Text('Se eliminará el registro de ${s.etiqueta}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => widget.localidad.serviciosBasicos.remove(s));
    }
  }
}
