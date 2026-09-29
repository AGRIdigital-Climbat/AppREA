import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../../config/theme.dart';
import '../../../providers/asistente_ia_provider.dart';
import '../../../widgets/asistente_ia/asistente_ia_bottom_sheet.dart';

class RespGuiaTab extends StatefulWidget {
  const RespGuiaTab({super.key});

  @override
  State<RespGuiaTab> createState() => _RespGuiaTabState();
}

class _RespGuiaTabState extends State<RespGuiaTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primary = PaletteScope.of(context).primary;
    return AnimationLimiter(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHero(primary),
          const SizedBox(height: 16),
          _buildCiclo(primary),
          const SizedBox(height: 16),
          _buildFotos(primary),
          const SizedBox(height: 16),
          _buildAsistenteTeaser(primary),
        ],
      ),
    );
  }

  Widget _buildHero(Color primary) {
    final accent = Palettes.rea.accent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.menu_book, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Guía del EDAN',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cada comunidad llena su EDAN; el UGR lo aprueba y '
            'consolida a niveles superiores.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCiclo(Color primary) {
    const pasos = [
      _Paso(
        titulo: 'Recopilar evidencia',
        detalle:
            'Visita la comunidad, habla con autoridades locales y recopila '
            'fotos georreferenciadas, coordenadas GPS y datos de familias '
            'afectadas.',
        icon: Icons.photo_camera,
        color: AppColors.enviado,
      ),
      _Paso(
        titulo: 'Llenar el EDAN',
        detalle:
            'Cada comunidad llena su propio EDAN con la información '
            'recopilada. El código se genera automáticamente.',
        icon: Icons.edit_document,
        color: AppColors.completed,
      ),
      _Paso(
        titulo: 'Revisar y enviar al UGR',
        detalle:
            'Revisa la vista previa, completa los campos faltantes y presiona '
            '"Confirmar y Enviar" para remitirlo al UGR.',
        icon: Icons.send,
        color: AppColors.rechazado,
      ),
      _Paso(
        titulo: 'Aprobación del UGR',
        detalle:
            'El UGR revisa tu reporte y lo aprueba o rechaza con observaciones.',
        icon: Icons.fact_check,
        color: AppColors.cerrado,
      ),
      _Paso(
        titulo: 'Consolidación',
        detalle:
            'Con los EDAN aprobados, el UGR consolida la información y la '
            'reporta a los niveles superiores.',
        icon: Icons.account_tree,
        color: AppColors.primaryDark,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Titulo('El ciclo del EDAN', primary),
        const SizedBox(height: 4),
        const Text(
          'Así viaja tu reporte hasta llegar a los niveles superiores.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < pasos.length; i++) ...[
          _buildPaso(pasos[i], i + 1),
          if (i < pasos.length - 1) _buildConexion(pasos[i].color),
        ],
      ],
    );
  }

  Widget _buildPaso(_Paso paso, int numero) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: paso.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: paso.color,
            child: Text(
              '$numero',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paso.titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  paso.detalle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Icon(paso.icon, color: paso.color, size: 20),
        ],
      ),
    );
  }

  Widget _buildConexion(Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 33),
      child: Container(
        height: 10,
        width: 2,
        color: color.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildFotos(Color primary) {
    const tips = [
      'Fotografía los daños del evento: viviendas, vías y cultivos.',
      'Activa el GPS: cada foto guarda su ubicación.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Titulo('Fotos georreferenciadas', primary),
        const SizedBox(height: 4),
        const Text(
          'Prueba principal del reporte',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.pending.withValues(alpha: 0.08),
                AppColors.pending.withValues(alpha: 0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.pending.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.photo_camera, color: AppColors.pending, size: 22),
                  SizedBox(width: 8),
                  Icon(
                    Icons.add_location_alt,
                    color: AppColors.pending,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Es un evento extremo: las fotos son la prueba. '
                      'El formulario guarda una foto por fila, con su '
                      'ubicación automática.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < tips.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: AppColors.pending,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tips[i],
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (i < tips.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAsistenteTeaser(Color primary) {
    final accent = Palettes.rea.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Dudas con tu reporte?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Pregúntale al asistente IA en cualquier pantalla.',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              final provider = AsistenteIAProvider();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AsistenteIABottomSheet(provider: provider),
              );
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: primary,
            ),
            icon: const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    );
  }
}

class _Paso {
  final String titulo;
  final String detalle;
  final IconData icon;
  final Color color;

  const _Paso({
    required this.titulo,
    required this.detalle,
    required this.icon,
    required this.color,
  });
}

class _Titulo extends StatelessWidget {
  final String texto;
  final Color color;

  const _Titulo(this.texto, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          texto,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
