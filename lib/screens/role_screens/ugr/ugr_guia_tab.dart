import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../config/theme.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/motor_ia_service.dart';
import '../../../widgets/asistente_ia.dart';

class UgrGuiaTab extends StatefulWidget {
  const UgrGuiaTab({super.key});

  @override
  State<UgrGuiaTab> createState() => _UgrGuiaTabState();
}

class _UgrGuiaTabState extends State<UgrGuiaTab>
    with AutomaticKeepAliveClientMixin {
  static const _pasos = <_Paso>[
    _Paso(
      titulo: 'Recibir reporte',
      detalle:
          'Los líderes locales crean y envían localidades '
          'con los daños de su zona.',
      icon: Icons.receipt_long,
      color: AppColors.enviado,
    ),
    _Paso(
      titulo: 'Esperar envío',
      detalle:
          'Las localidades llegan cuando el líder presiona Enviar. '
          'Aparecen en tu pestaña Localidades.',
      icon: Icons.hourglass_top,
      color: AppColors.pending,
    ),
    _Paso(
      titulo: 'Revisar y contrastar',
      detalle:
          'Al abrir una localidad enviada, cambia a "En revisión" '
          'automáticamente. Verifica fotos, coordenadas y datos. '
          'Aprueba o rechaza.',
      icon: Icons.fact_check_outlined,
      color: AppColors.primary,
    ),
    _Paso(
      titulo: 'Consolidar',
      detalle:
          'Agrupa localidades aprobadas del mismo tipo de evento '
          'en un EDAN. Selecciona el alcalde.',
      icon: Icons.layers,
      color: AppColors.completed,
    ),
    _Paso(
      titulo: 'Enviar EDAN',
      detalle:
          'Revisa el EDAN en la pestaña EDAN y envíalo. '
          'Es declaración jurada — verifica antes de enviar.',
      icon: Icons.send,
      color: AppColors.rechazado,
    ),
  ];

  static const _checkCampo = <String>[
    'Verificar fotos con GPS activado',
    'Confirmar coordenadas del lugar afectado',
    'Validar listado de familias afectadas',
    'Revisar estado de viviendas (afectada/destruida)',
    'Verificar daños en salud, educación, servicios',
    'Confirmar situación agropecuaria',
  ];

  static const _checkRemoto = <String>[
    'Confirmar datos con el alcalde / autoridad local',
    'Contrastar con reportes previos del municipio',
    'Validar con instituciones (salud, educación, agua)',
    'Revisar el mapa de reportes del municipio',
    'Verificar que las localidades tengan responsable',
  ];

  static const _secciones = <_GuiaSeccion>[
    _GuiaSeccion(
      numero: '01',
      titulo: 'Datos generales',
      subtitulo: 'Ubicación, alcalde, fechas y localidades',
      queLlenar: 'Identifica el lugar y el responsable del municipio para la '
          'coordinación de la respuesta.',
      pasos: [
        'Departamento, provincia y municipio',
        'N° de localidades afectadas (comunidades, distritos, barrios)',
        'Nombre del alcalde y teléfono de contacto',
        'Fecha de llenado, fecha del evento y hora (0-24h)',
      ],
      consejo: 'La fecha de llenado es distinta a la fecha del evento. '
          'La fecha del evento se obtiene preguntando a quienes estuvieron en '
          'el lugar.',
      ejemplo: 'Cochabamba · Villa Tunari · Alcalde: Asterio Romero · '
          'Llenado: 02-feb-2019 · Evento: 01-feb-2019, 10:00',
      obligatorio: true,
      icon: Icons.location_city,
      color: AppColors.primary,
    ),
    _GuiaSeccion(
      numero: '02',
      titulo: 'Población afectada y damnificada',
      subtitulo: 'Totales de personas y familias',
      queLlenar: 'Cuantifica a la población afectada por el evento.',
      pasos: [
        'Total de población afectada (personas)',
        'Total de familias afectadas',
        'Total de familias damnificadas',
      ],
      consejo: 'Este es uno de los datos MÁS IMPORTANTES del EDAN. '
          'Todos los campos son obligatorios. '
          'Afectado = daños o pérdidas indirectas. Damnificado = daños '
          'directos, su vivienda quedó inhabitable. Lleva el listado de '
          'familias con el nº de integrantes para respaldar la ayuda.',
      ejemplo: 'Población afectada: 100 · Familias afectadas: 20 · '
          'Familias damnificadas: 5',
      obligatorio: true,
      icon: Icons.groups,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '03',
      titulo: 'Impacto en la población',
      subtitulo: 'Fallecidos, heridos, desaparecidos y primera respuesta',
      queLlenar: 'Detalla el impacto humano del evento.',
      pasos: [
        'Marca el tipo de evento de mayor impacto',
        'Fallecidos, heridos y desaparecidos por grupo etario',
        'Necesidades de primera respuesta: búsqueda, salvamento/rescate, '
            'evacuación',
      ],
      consejo: 'Si hubo varios eventos, registra el que causó mayor daño. '
          'Grupos etarios: niño 0-5, escolar 6-18, adulto 19-60, adulto mayor '
          '60+.',
      ejemplo: 'Inundación · Fallecidos: 5 · Evacuación: 30 familias '
          'requieren evacuar por aumento de caudal',
      obligatorio: true,
      icon: Icons.warning_amber_rounded,
      color: AppColors.rechazado,
    ),
    _GuiaSeccion(
      numero: '04',
      titulo: 'Impacto en la salud',
      subtitulo: 'Establecimientos de salud afectados',
      queLlenar: 'Registra el daño en servicios de salud y la atención '
          'necesaria.',
      pasos: [
        'Nombre del establecimiento, localidad y nivel de atención (1°, 2° o '
            '3°)',
        'Daño parcial o total',
        'Personal de salud afectado (médicos, enfermeras, otros)',
        'Necesidades: botiquín (incendio/inundación/sequía) y otras',
      ],
      consejo: 'Daño parcial: con refacciones sigue funcionando. Daño total: '
          'no puede funcionar. Anota en observaciones medicación específica '
          'para tratamientos crónicos.',
      ejemplo: 'Centro de Salud Villa Tunari · Daño parcial · 2 médicos, '
          '3 enfermeras · Botiquín inundación: 45 personas requieren atención',
      obligatorio: true,
      icon: Icons.local_hospital,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '05',
      titulo: 'Impacto en infraestructuras',
      subtitulo: 'Vías, puentes y estructuras públicas',
      queLlenar: 'Registra daños en vías, puentes e infraestructura pública.',
      pasos: [
        'Vía o puente dañado y su ubicación',
        'Estructura pública afectada (tipo y estado)',
      ],
      consejo: 'Adjunta fotos de cada estructura dañada para respaldar el '
          'EDAN.',
      ejemplo: 'Puente sobre el río Colorado · Colapso total · Comunidad '
          'Villa Nueva',
      obligatorio: true,
      icon: Icons.construction,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '06',
      titulo: 'Impacto en servicios básicos',
      subtitulo: 'Agua, luz, saneamiento y comunicaciones',
      queLlenar: 'Marca qué servicios se interrumpieron y en qué localidades.',
      pasos: [
        'Agua potable',
        'Energía eléctrica',
        'Saneamiento / alcantarillado',
        'Comunicaciones',
      ],
      consejo: 'Registra por localidad si cada servicio está afectado.',
      ejemplo: 'Comunidad Villa Nueva: sin agua potable y sin energía '
          'eléctrica',
      obligatorio: true,
      icon: Icons.water_drop,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '07',
      titulo: 'Impacto en educación',
      subtitulo: 'Unidades educativas afectadas',
      queLlenar: 'Registra daños en unidades educativas.',
      pasos: [
        'Nombre de la unidad educativa',
        'Estudiantes y profesores afectados',
        'Estado del establecimiento',
      ],
      consejo: 'Verifica si las clases fueron suspendidas y cuántos estudiantes '
          'quedaron sin atención.',
      ejemplo: 'Unidad Educativa 6 de Agosto · 120 estudiantes · '
          'Infraestructura dañada',
      obligatorio: true,
      icon: Icons.school,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '08',
      titulo: 'Impacto en viviendas',
      subtitulo: 'Viviendas afectadas y destruidas',
      queLlenar: 'Registra el estado de las viviendas por localidad.',
      pasos: [
        'N° de viviendas afectadas',
        'N° de viviendas destruidas',
      ],
      consejo: 'Confirma con la autoridad local y el listado de familias '
          'damnificadas.',
      ejemplo: '8 viviendas afectadas · 3 destruidas en el barrio El Puente',
      obligatorio: true,
      icon: Icons.home,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '09',
      titulo: 'Impacto agropecuario',
      subtitulo: 'Cultivos, especies e infraestructura agro',
      queLlenar: 'Registra pérdidas en la producción y medios de vida.',
      pasos: [
        'Cultivos afectados (tipo y extensión)',
        'Animales (especie y cantidad)',
        'Infraestructura agropecuaria dañada',
      ],
      consejo: 'Esto es clave para los planes de rehabilitación y '
          'reconstrucción.',
      ejemplo: '5 ha de maíz afectadas · 20 cabezas de ganado perdidas',
      obligatorio: true,
      icon: Icons.agriculture,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '10',
      titulo: 'Impacto en protección',
      subtitulo: 'Grupos vulnerables afectados',
      queLlenar: 'Registra grupos que necesitan atención prioritaria.',
      pasos: [
        'Niñas y niños, adolescentes',
        'Mujeres lactantes y embarazadas',
        'Adultos mayores',
        'Personas con discapacidad y con enfermedades crónicas',
      ],
      consejo: 'Identifica cuántos hay y dónde para priorizar la respuesta.',
      ejemplo: '10 niñas/os · 3 adultos mayores · 2 personas con discapacidad',
      obligatorio: true,
      icon: Icons.family_restroom,
      color: AppColors.enviado,
    ),
    _GuiaSeccion(
      numero: '11',
      titulo: 'Necesidades humanitarias',
      subtitulo: 'Prioridades de atención',
      queLlenar: 'Prioriza lo que necesita la población damnificada.',
      pasos: [
        'Primera respuesta (rescate, evacuación)',
        'Alimentos, agua, refugio',
        'Salud, protección y otros',
      ],
      consejo: 'Ordena por prioridad para facilitar la toma de decisiones.',
      ejemplo: '1) Evacuación  2) Agua potable  3) Carpas y frazadas',
      obligatorio: true,
      icon: Icons.volunteer_activism,
      color: AppColors.completed,
    ),
    _GuiaSeccion(
      numero: '13',
      titulo: 'Responsable del formulario',
      subtitulo: 'Quién llena y respalda el EDAN',
      queLlenar: 'Identifica al responsable que respalda la información.',
      pasos: [
        'Nombre del responsable',
        'Teléfono de contacto',
      ],
      consejo: 'El cargo ya no bloquea el envío; basta con el nombre. Es quien '
          'responde por la veracidad de los datos.',
      ejemplo: 'Nombre: Juan Pérez · Teléfono: 71234567',
      obligatorio: true,
      icon: Icons.assignment_ind,
      color: AppColors.completed,
    ),
  ];

  static const _guiaLocalidades = <_GuiaSeccion>[
    _GuiaSeccion(
      numero: 'L1',
      titulo: 'Ver localidades',
      subtitulo: 'Pestaña Localidades — Vista por defecto: Sin consolidar',
      queLlenar: 'Observa todas las localidades reportadas por los líderes '
          'de tu municipio, agrupadas por tipo de evento.',
      pasos: [
        'En la pestaña Localidades ves las localidades "Sin consolidar"',
        'Cada grupo tiene un header con icono del evento y conteo',
        'Toca el chip "Consolidadas" para ver las ya agrupadas en un EDAN',
        'Usa la barra de búsqueda para filtrar por nombre, tipo o responsable',
      ],
      consejo: 'Las localidades se ordenan por fecha más reciente primero. '
          'Cada tarjeta muestra el estado con un badge de color.',
      ejemplo: 'Inundación (3) → Comunidad X (Borrador) · Barrio Y (Enviado) · Zona Z (Aprobado)',
      obligatorio: false,
      icon: Icons.location_on_outlined,
      color: AppColors.pending,
    ),
    _GuiaSeccion(
      numero: 'L2',
      titulo: 'Revisar y cambiar estado',
      subtitulo: 'Flujo: Enviado → En revisión (auto) → Aprobado/Rechazado',
      queLlenar: 'Revisa la información de cada localidad y cambia su estado.',
      pasos: [
        'Toca una localidad para ver la vista previa completa',
        'Al abrir una enviada, el estado cambia a "En revisión" automáticamente',
        'Si está "En revisión", aprueba o rechaza con los botones',
        'Las aprobadas quedan listas para consolidar',
      ],
      consejo: 'Solo puedes cambiar estado desde estados específicos. '
          'El badge de color te indica el estado actual.',
      ejemplo: 'Enviado UGR → En revisión (automático) → Aprobado UGR → Lista para consolidar',
      obligatorio: false,
      icon: Icons.how_to_reg,
      color: AppColors.primary,
    ),
    _GuiaSeccion(
      numero: 'L3',
      titulo: 'Consolidar localidades',
      subtitulo: 'Agrupa localidades aprobadas en un EDAN municipal',
      queLlenar: 'Selecciona localidades del mismo tipo de evento '
          'y consolídalas en un solo EDAN.',
      pasos: [
        'Presiona el ícono de capas en la vista "Sin consolidar"',
        'Selecciona las localidades que quieres agrupar',
        'Deben ser del mismo tipo de evento y estado aprobado',
        'Confirma → se crea el EDAN con código automático',
      ],
      consejo: 'Las localidades consolidadas pasan a la vista "Consolidadas". '
          'El EDAN se crea con código formato: municipio/año/secuencia.',
      ejemplo: '3 localidades aprobadas de Inundación → EDAN 70101/2026/001',
      obligatorio: false,
      icon: Icons.layers,
      color: AppColors.completed,
    ),
  ];

  int? _pasoActivo;

  final TextEditingController _busquedaCtrl = TextEditingController();

  List<MotorTipo> _tipos = const [];
  int? _tipoSeleccionado;
  List<MotorDoc> _documentos = const [];
  bool _docsCargando = true;
  String? _docsError;
  final Set<int> _descargando = <int>{};
  final Map<int, String> _rutasDescargados = <int, String>{};

  static const _prefsKey = 'motor_ia_descargados';

  @override
  void initState() {
    super.initState();
    _cargarTipos();
    _cargarDocumentos();
    _cargarDescargados();
  }

  Future<void> _cargarDescargados() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rutas = prefs.getStringList(_prefsKey) ?? const <String>[];
      for (final r in rutas) {
        if (!File(r).existsSync()) continue;
        final id = int.tryParse(r.split(RegExp(r'[\\/]')).last.split('_').first);
        if (id == null || !mounted) continue;
        setState(() => _rutasDescargados[id] = r);
      }
    } catch (_) {}
  }

  Future<void> _guardarDescargados() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsKey,
        _rutasDescargados.values.toList(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTipos() async {
    if (!ConnectivityService().isConnected) return;
    try {
      final tipos = await MotorIA.instance.listarTipos();
      if (mounted) setState(() => _tipos = tipos);
    } catch (_) {}
  }

  Future<void> _cargarDocumentos() async {
    setState(() {
      _docsCargando = true;
      _docsError = null;
    });
    if (!ConnectivityService().isConnected) {
      if (mounted) {
        setState(() {
          _docsCargando = false;
          _docsError = 'Sin conexión a internet. Verifica tu red y reintenta.';
        });
      }
      return;
    }
    try {
      final docs = await MotorIA.instance
          .listarDocumentos(tipoId: _tipoSeleccionado, q: _busquedaCtrl.text);
      if (mounted) {
        setState(() {
          _documentos = docs;
          _docsCargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _docsCargando = false;
          _docsError = 'No se pudieron cargar los documentos.';
        });
      }
    }
  }

  Future<void> _descargarYAbir(MotorDoc doc) async {
    if (_descargando.contains(doc.id)) return;
    if (!ConnectivityService().isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin conexión. Verifica tu red y reintenta.'),
            backgroundColor: AppColors.pending,
          ),
        );
      }
      return;
    }
    setState(() => _descargando.add(doc.id));
    try {
      final path = await MotorIA.instance
          .descargarDocumento(doc.id, titulo: doc.titulo);
      if (!mounted) return;
      setState(() => _rutasDescargados[doc.id] = path);
      _guardarDescargados();
      final res = await OpenFilex.open(path);
      if (res.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el PDF.'),
            backgroundColor: AppColors.rechazado,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al descargar el documento.'),
            backgroundColor: AppColors.rechazado,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _descargando.remove(doc.id));
    }
  }

  Future<void> _abrirDocumento(MotorDoc doc) async {
    final path = _rutasDescargados[doc.id];
    if (path == null) return;
    final res = await OpenFilex.open(path);
    if (res.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el PDF.'),
          backgroundColor: AppColors.rechazado,
        ),
      );
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primary = PaletteScope.of(context).primary;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _buildTabBar(primary),
          Expanded(
            child: TabBarView(
              children: [
                _buildGuiaList(primary),
                _buildBiblioteca(primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          labelColor: primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(
              height: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_outlined, size: 18),
                  SizedBox(width: 6),
                  Text('Guía de pasos'),
                ],
              ),
            ),
            Tab(
              height: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_books_outlined, size: 18),
                  SizedBox(width: 6),
                  Text('Biblioteca'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuiaList(Color primary) {
    return AnimationLimiter(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _animado(0, _buildHero(primary)),
          const SizedBox(height: 14),
          _animado(1, _buildNotaResponsabilidad(primary)),
          const SizedBox(height: 14),
          _animado(2, _buildProceso(primary)),
          const SizedBox(height: 14),
          _animado(3, _buildChecklist(primary)),
          const SizedBox(height: 16),
          _animado(4, _Titulo('Guía por sección del EDAN', primary)),
          const SizedBox(height: 8),
          _animado(5, _buildNotaSecciones(primary)),
          for (var i = 0; i < _secciones.length; i++)
            _animado(6 + i, _buildSeccionCard(_secciones[i])),
          const SizedBox(height: 16),
          _animado(6 + _secciones.length, _Titulo('Gestión de Localidades', primary)),
          const SizedBox(height: 8),
          for (var i = 0; i < _guiaLocalidades.length; i++)
            _animado(7 + _secciones.length + i, _buildSeccionCard(_guiaLocalidades[i])),
          const SizedBox(height: 6),
          _animado(7 + _secciones.length + _guiaLocalidades.length, _buildAsistenteTeaser(primary)),
        ],
      ),
    );
  }

  Widget _animado(int index, Widget child) {
    return AnimationConfiguration.staggeredList(
      position: index,
      duration: const Duration(milliseconds: 450),
      child: SlideAnimation(
        verticalOffset: 40,
        child: FadeInAnimation(child: child),
      ),
    );
  }

  Widget _buildHero(Color primary) {
    final accent = Palettes.edan.accent;
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
                'Guía del UGR',
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
            'Revisa, aprueba y consolida localidades en un EDAN municipal.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProceso(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Titulo('Proceso del UGR', primary),
        const SizedBox(height: 8),
        for (var i = 0; i < _pasos.length; i++) ...[
          _buildPaso(i, _pasos[i]),
          if (i < _pasos.length - 1) _buildConexion(_pasos[i].color),
        ],
      ],
    );
  }

  Widget _buildNotaResponsabilidad(Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rechazado.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.rechazado.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel, size: 18, color: AppColors.rechazado),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Declaración jurada: Como UGR, la responsabilidad de la '
              'información recae en ti. Verifica cada dato '
              'antes de aprobar o consolidar.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.rechazado.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
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

  Widget _buildPaso(int i, _Paso paso) {
    final activo = _pasoActivo == i;
    return InkWell(
      onTap: () => setState(() => _pasoActivo = activo ? null : i),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: activo
              ? paso.color.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: activo ? paso.color : AppColors.divider,
            width: activo ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: paso.color,
                  child: Icon(paso.icon, color: Colors.white, size: 20),
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
                      Text(
                        'Paso ${i + 1} · toca para ver la sugerencia',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  activo ? Icons.expand_less : Icons.expand_more,
                  color: paso.color,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              alignment: Alignment.topCenter,
              child: activo
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          paso.detalle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklist(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Titulo('Verificar antes de enviar', primary),
        const SizedBox(height: 8),
        _buildCheckGrupo(primary, 'En campo', Icons.hiking, _checkCampo),
        const SizedBox(height: 10),
        _buildCheckGrupo(primary, 'Sin viajar (remoto)', Icons.smartphone, _checkRemoto),
      ],
    );
  }

  Widget _buildNotaSecciones(Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Los campos de cada sección son obligatorios, pero NO es necesario '
              'llenar todas las secciones. Solo completa y revisa a detalle las '
              'secciones habilitadas que apliquen al tipo de evento reportado.',
              style: TextStyle(
                fontSize: 12,
                color: primary.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckGrupo(
    Color primary,
    String titulo,
    IconData icon,
    List<String> items,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeccionCard(_GuiaSeccion s) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: s.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(s.icon, color: s.color, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                s.titulo,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _requisitoChip(s.obligatorio),
          ],
        ),
        subtitle: Text(
          'Sección ${s.numero} · ${s.subtitulo}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        children: [_buildSeccionContenido(s, primary)],
      ),
    );
  }

  Widget _buildSeccionContenido(_GuiaSeccion s, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          s.queLlenar,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        for (final paso in s.pasos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.chevron_right, size: 16, color: s.color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    paso,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _buildBox(
          icon: Icons.lightbulb_outline,
          titulo: 'CONSEJO',
          texto: s.consejo,
          color: s.color,
          fondo: s.color.withValues(alpha: 0.08),
        ),
        const SizedBox(height: 8),
        _buildBox(
          icon: Icons.edit_outlined,
          titulo: 'EJEMPLO',
          texto: s.ejemplo,
          color: primary,
          fondo: primary.withValues(alpha: 0.06),
        ),
      ],
    );
  }

  Widget _buildBox({
    required IconData icon,
    required String titulo,
    required String texto,
    required Color color,
    required Color fondo,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requisitoChip(bool obligatorio) {
    final color = obligatorio ? AppColors.rechazado : AppColors.closed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        obligatorio ? 'Obligatorio' : 'Opcional',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

    Widget _buildAsistenteTeaser(Color primary) {
    final accent = Palettes.edan.accent;
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
                  '¿Dudas con el EDAN?',
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
            onPressed: () => showAsistenteIa(context),
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

  Widget _buildBiblioteca(Color primary) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBibliotecaHero(primary),
        const SizedBox(height: 14),
        _buildFiltros(primary),
        const SizedBox(height: 12),
        if (_docsCargando)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_docsError != null)
          _buildErrorDocs(primary)
        else if (_documentos.isEmpty)
          _buildVacioDocs()
        else
          for (final doc in _documentos) _buildDocCard(doc, primary),
      ],
    );
  }

  Widget _buildBibliotecaHero(Color primary) {
    final accent = Palettes.edan.accent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.library_books, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Biblioteca de documentos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            'Normativa oficial: Guía del EDAN, Ley 602 y otros. '
            'Descarga y abre el PDF.',
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filtrar por tipo',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTipoChip(primary, null, 'Todos'),
              for (final tipo in _tipos)
                _buildTipoChip(primary, tipo.id, tipo.nombre),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTipoChip(Color primary, int? tipoId, String label) {
    final selected = _tipoSeleccionado == tipoId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: primary.withValues(alpha: 0.15),
        checkmarkColor: primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? primary : AppColors.textPrimary,
        ),
        side: BorderSide(
          color: selected ? primary : AppColors.divider,
        ),
        onSelected: (_) {
          setState(() => _tipoSeleccionado = tipoId);
          _cargarDocumentos();
        },
      ),
    );
  }

  Widget _buildErrorDocs(Color primary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 32, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text(
            _docsError ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _cargarDocumentos,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildVacioDocs() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: [
          Icon(Icons.folder_off_outlined,
              size: 32, color: AppColors.textSecondary),
          SizedBox(height: 8),
          Text(
            'No hay documentos para este tipo.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDocCard(MotorDoc doc, Color primary) {
    final descargando = _descargando.contains(doc.id);
    final yaDescargado = _rutasDescargados.containsKey(doc.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (yaDescargado ? AppColors.completed : primary)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              yaDescargado ? Icons.check_circle : Icons.picture_as_pdf,
              color: yaDescargado ? AppColors.completed : primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (doc.tipoNombre.isNotEmpty) doc.tipoNombre,
                    if (doc.numPaginas > 0) '${doc.numPaginas} páginas',
                    if (yaDescargado) 'descargado',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          yaDescargado
              ? IconButton(
                  onPressed: () => _abrirDocumento(doc),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.completed.withValues(alpha: 0.12),
                    foregroundColor: AppColors.completed,
                  ),
                  tooltip: 'Abrir PDF',
                  icon: const Icon(Icons.visibility),
                )
              : IconButton(
                  onPressed: descargando ? null : () => _descargarYAbir(doc),
                  style: IconButton.styleFrom(
                    backgroundColor: primary.withValues(alpha: 0.1),
                    foregroundColor: primary,
                  ),
                  tooltip: 'Descargar y abrir',
                  icon: descargando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                ),
        ],
      ),
    );
  }
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
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
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

class _GuiaSeccion {
  final String numero;
  final String titulo;
  final String subtitulo;
  final String queLlenar;
  final List<String> pasos;
  final String consejo;
  final String ejemplo;
  final bool obligatorio;
  final IconData icon;
  final Color color;

  const _GuiaSeccion({
    required this.numero,
    required this.titulo,
    required this.subtitulo,
    required this.queLlenar,
    required this.pasos,
    required this.consejo,
    required this.ejemplo,
    required this.obligatorio,
    required this.icon,
    required this.color,
  });
}
