import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import 'edan_dialog_helper.dart';
import 'edan_item_card.dart';

/// Página 10: Impacto en protección (grupos vulnerables por sexo).
class EdanPage10 extends StatefulWidget {
  final EdanLocalidad localidad;

  const EdanPage10({super.key, required this.localidad});

  @override
  State<EdanPage10> createState() => _EdanPage10State();
}

class _EdanPage10State extends State<EdanPage10> {
  Future<void> _editar(EdanGrupoVulnerable g) async {
    final mujeres = TextEditingController(text: g.mujeres > 0 ? '${g.mujeres}' : '');
    final hombres = TextEditingController(text: g.hombres > 0 ? '${g.hombres}' : '');
    var apoyo = g.apoyoPsicologico ?? false;
    var docs = g.reposicionDocumentos ?? false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          title: Text(g.nombreGrupo ?? 'Grupo vulnerable'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: mujeres, keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'N° Mujeres')),
                const SizedBox(height: 8),
                TextField(controller: hombres, keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'N° Hombres')),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: apoyo,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Requiere apoyo psicológico'),
                  onChanged: (x) => setLocal(() => apoyo = x ?? false),
                ),
                CheckboxListTile(
                  value: docs,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Requiere reposición de documentos'),
                  onChanged: (x) => setLocal(() => docs = x ?? false),
                ),
              ],
            ),
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
      g.mujeres = int.tryParse(mujeres.text) ?? 0;
      g.hombres = int.tryParse(hombres.text) ?? 0;
      g.apoyoPsicologico = apoyo;
      g.reposicionDocumentos = docs;
    });
    mujeres.dispose();
    hombres.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grupos = widget.localidad.proteccion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Población vulnerable por grupo y sexo',
          style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        ...grupos.map((g) => EdanItemCard(
              titulo: g.nombreGrupo ?? 'Grupo',
              subtitulo: [
                'Mujeres: ${g.mujeres}',
                'Hombres: ${g.hombres}',
                if (g.apoyoPsicologico == true) 'Apoyo psicológico',
                if (g.reposicionDocumentos == true) 'Reposición docs',
              ].join(' · '),
              icono: Icons.people_outline,
              onEditar: () => _editar(g),
              onEliminar: () async {
                final ok = await confirmarEliminacion(
                  context,
                  titulo: '¿Limpiar registro?',
                  mensaje: 'Se pondrán en cero los datos del grupo "${g.nombreGrupo}".',
                );
                if (!ok || !mounted) return;
                setState(() {
                  g.mujeres = 0;
                  g.hombres = 0;
                  g.apoyoPsicologico = false;
                  g.reposicionDocumentos = false;
                });
              },
            )),
      ],
    );
  }
}
