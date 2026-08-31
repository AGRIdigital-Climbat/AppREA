import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../config/api_config.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../models/id_seccion_helper.dart';
import '../../../models/usuario.dart';
import '../../../providers/reporte_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';
import '../../../widgets/custom_text_field.dart';
import 'crear_usuario_screen.dart';
import 'ugr_edan_preview_screen.dart';

const List<String> _tiposEvento = [
  'INUNDACIÓN',
  'RIADA',
  'DESLIZAMIENTO',
  'HELADA',
  'GRANIZADA',
  'SEQUÍA',
  'INCENDIOS',
  'OTROS',
];

const List<String> _nivelesAtencion = ['1er Nivel', '2do Nivel', '3er Nivel'];

const Map<String, String> _titulosSeccion = {
  '01': 'Datos generales',
  '02': 'Información total población afectada y damnificada',
  '03': 'Impacto en la población',
  '04': 'Impacto en la salud',
  '05': 'Impacto en infraestructuras',
  '06': 'Impacto en servicios básicos',
  '07': 'Impacto en educación',
  '08': 'Impacto en viviendas',
  '09': 'Impacto agropecuario',
  '10': 'Impacto en protección',
  '11': 'Necesidades humanitarias',
  '13': 'Responsable del Formulario',
};

class UgrEdanFormScreen extends StatefulWidget {
  final Edan? edanAEditar;

  const UgrEdanFormScreen({super.key, this.edanAEditar});

  @override
  State<UgrEdanFormScreen> createState() => _UgrEdanFormScreenState();
}

class _UgrEdanFormScreenState extends State<UgrEdanFormScreen> {
  final _edan = Edan.empty();
  final Set<String> _expandidas = {'01'};

  // Indicador de sección actual al desplazar
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _indicadorKey = GlobalKey();
  final Map<String, GlobalKey> _sectionKeys = {
    '01': GlobalKey(),
    '02': GlobalKey(),
    '03': GlobalKey(),
    '04': GlobalKey(),
    '05': GlobalKey(),
    '06': GlobalKey(),
    '07': GlobalKey(),
    '08': GlobalKey(),
    '09': GlobalKey(),
    '10': GlobalKey(),
    '11': GlobalKey(),
    '13': GlobalKey(),
  };
   String? _seccionActual;
   String? _focusNodeId;

   // 01 · Datos generales
  final _nombreAlcaldeController = TextEditingController();
  final _fonoAlcaldeController = TextEditingController();
  final _fechaLlenadoController = TextEditingController();
  final _fechaEventoController = TextEditingController();
  DateTime _fechaLlenado = DateTime.now();
  DateTime _fechaEvento = DateTime.now();
  String _hora12 = '12';
  String _ampm = 'AM';
  int? _idDepartamento;
  int? _idProvincia;
  int? _idMunicipio;
  int? _idTipoEvento;
  String _tipoEventoNombre = '';
  int? _idUsuarioAlcalde;
  List<Usuario> _usuarios = [];
  String _errorUsuarios = '';

  // Código EDAN: {codigo_ine}/{año}/{secuencial del municipio}
  String _codigoIne = '---';
  int _siguienteNumero = 1;

  // 02 · Población
  final _poblacionController = TextEditingController();
  final _familiasAfectadasController = TextEditingController();
  final _familiasDamnificadasController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fechaLlenadoController.text = _fmtFecha(_fechaLlenado);
    _fechaEventoController.text = _fmtFecha(_fechaEvento);
    final now = TimeOfDay.now();
    _hora12 = ((now.hour % 12 == 0 ? 12 : now.hour % 12)).toString().padLeft(2, '0');
    _ampm = now.hour >= 12 ? 'PM' : 'AM';
    _scrollController.addListener(_onScroll);

    final token = AuthService.instance.currentToken;
    if (token != null) {
      _edan.responsable.nombre = token.nombre;
      _edan.responsable.cargo = token.cargo ?? '';
      _edan.responsable.fono = token.celular ?? '';
      _edan.responsable.correo = token.correo ?? '';
    }

    if (widget.edanAEditar != null) {
      _cargarEdan(widget.edanAEditar!);
    }

    _recalcularNumeroEdan();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final token = AuthService.instance.currentToken;
      if (token?.idMunicipio != null && token?.idProvincia != null && token?.idDepartamento != null) {
        context.read<ReporteProvider>().loadMunicipios(token!.idProvincia!, token.idDepartamento!);
      }
      _cargarUsuariosAlcalde();
      
      // Forzar carga de gruposVulnerables si está vacío
      final rp = context.read<ReporteProvider>();
      if (rp.gruposVulnerables.isEmpty) {
        await rp.fetchGruposVulnerablesIfNeeded();
      }
    });
  }

  Future<void> _cargarUsuariosAlcalde() async {
    final idMunicipio = AuthService.instance.currentToken?.idMunicipio;
    if (!ConnectivityService().isConnected) {
      if (mounted) setState(() => _errorUsuarios = 'Sin conexión a internet');
      return;
    }
    try {
      final usuarios = await ApiService.instance.getUsuarios(
        idMunicipio: idMunicipio,
        idRol: 8,
      );
      if (!mounted) return;
      setState(() {
        _usuarios = usuarios;
        _errorUsuarios = '';
      });
    } catch (e) {
      final url =
          '${ApiConfig.usuariosEndpoint}?id_municipio=${idMunicipio ?? ''}&id_rol=8&skip=0&limit=50';
      debugPrint('Error cargando usuarios alcalde [$url]: $e');
      if (mounted) setState(() => _errorUsuarios = ApiService.traducirError(e));
    }
  }

  void _cargarEdan(Edan edan) {
    _edan.idLocal = edan.idLocal;
    _edan.idServer = edan.idServer;
    _edan.idEdan = edan.idEdan;
    _edan.codigoEdan = edan.codigoEdan;
    _edan.idReporte = edan.idReporte;
    _edan.idUsuario = edan.idUsuario;
    _edan.esBorrador = edan.esBorrador;
    _edan.idDepartamento = edan.idDepartamento;
    _edan.idProvincia = edan.idProvincia;
    _edan.idMunicipio = edan.idMunicipio;
    _edan.departamentoNombre = edan.departamentoNombre;
    _edan.provinciaNombre = edan.provinciaNombre;
    _edan.municipioNombre = edan.municipioNombre;
    _edan.nombreAlcalde = edan.nombreAlcalde;
    _edan.fonoAlcalde = edan.fonoAlcalde;
    _edan.fechaLlenado = edan.fechaLlenado;
    _edan.fechaEvento = edan.fechaEvento;
    _edan.idTipoEvento = edan.idTipoEvento;
    _edan.tipoEventoNombre = edan.tipoEventoNombre;
    _edan.totalPoblacionAfectada = edan.totalPoblacionAfectada;
    _edan.totalFamiliasAfectadas = edan.totalFamiliasAfectadas;
    _edan.totalFamiliasDamnificadas = edan.totalFamiliasDamnificadas;
    _edan.localidades.clear();
    _edan.localidades.addAll(edan.localidades);
    _edan.necesidadHumanitaria = edan.necesidadHumanitaria;
    _edan.responsable = edan.responsable;
    _edan.idEstado = edan.idEstado;
    _edan.estado = edan.estado;

    // Variables locales para los dropdowns
    _idDepartamento = edan.idDepartamento;
    _idProvincia = edan.idProvincia;
    _idMunicipio = edan.idMunicipio;
    _idTipoEvento = edan.idTipoEvento;
    _tipoEventoNombre = edan.tipoEventoNombre ?? '';
    _idUsuarioAlcalde = edan.idUsuario;

    final rp = context.read<ReporteProvider>();
    if (_idDepartamento != null) {
      rp.loadProvincias(_idDepartamento!);
      if (_idProvincia != null) {
        rp.loadMunicipios(_idProvincia!, _idDepartamento!);
      }
    }

    _nombreAlcaldeController.text = edan.nombreAlcalde;
    _fonoAlcaldeController.text = edan.fonoAlcalde;
    if (edan.fechaLlenado.isNotEmpty) {
      try {
        _fechaLlenado = DateTime.parse(edan.fechaLlenado);
        _fechaLlenadoController.text = _fmtFecha(_fechaLlenado);
      } catch (_) {}
    }
    if (edan.fechaEvento.isNotEmpty) {
      try {
        _fechaEvento = DateTime.parse(edan.fechaEvento);
        _fechaEventoController.text = _fmtFecha(_fechaEvento);
      } catch (_) {}
    }
    if (edan.horaEvento.isNotEmpty) {
      _aplicarHora24h(edan.horaEvento);
    }
    _poblacionController.text = edan.totalPoblacionAfectada > 0
        ? edan.totalPoblacionAfectada.toString()
        : '';
    _familiasAfectadasController.text = edan.totalFamiliasAfectadas > 0
        ? edan.totalFamiliasAfectadas.toString()
        : '';
    _familiasDamnificadasController.text = edan.totalFamiliasDamnificadas > 0
        ? edan.totalFamiliasDamnificadas.toString()
        : '';
  }

  @override
  void dispose() {
    _nombreAlcaldeController.dispose();
    _fonoAlcaldeController.dispose();
    _fechaLlenadoController.dispose();
    _fechaEventoController.dispose();
    _poblacionController.dispose();
    _familiasAfectadasController.dispose();
    _familiasDamnificadasController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- Completadas (igual que la web) ----------

  List<EdanLocalidad> get _locConPoblacion =>
      _edan.localidades.where((l) => l.impPoblacion).toList();
  List<EdanLocalidad> get _locConSalud =>
      _edan.localidades.where((l) => l.impSalud).toList();
  List<EdanLocalidad> get _locConInfraestructura =>
      _edan.localidades.where((l) => l.impInfraestructura).toList();
  List<EdanLocalidad> get _locConServicios =>
      _edan.localidades.where((l) => l.impServicios).toList();
  List<EdanLocalidad> get _locConEducacion =>
      _edan.localidades.where((l) => l.impEducacion).toList();
  List<EdanLocalidad> get _locConVivienda =>
      _edan.localidades.where((l) => l.impVivienda).toList();
  List<EdanLocalidad> get _locConAgropecuario =>
      _edan.localidades.where((l) => l.impAgropecuario).toList();
  List<EdanLocalidad> get _locConProteccion =>
      _edan.localidades.where((l) => l.impProteccion).toList();
  List<EdanLocalidad> get _locConNecesidades =>
      _edan.localidades.where((l) => l.impNecesidades).toList();

  bool get _s01Completada =>
      _idDepartamento != null &&
      _idProvincia != null &&
      _idMunicipio != null &&
      _idTipoEvento != null &&
      _edan.localidades.any((l) => l.nombre.trim().isNotEmpty) &&
      _idUsuarioAlcalde != null &&
      _fonoAlcaldeController.text.trim().isNotEmpty &&
      _fechaLlenadoController.text.isNotEmpty &&
      _fechaEventoController.text.isNotEmpty;

  bool get _s02Completada =>
      _intDe(_poblacionController) > 0 ||
      _intDe(_familiasAfectadasController) > 0 ||
      _intDe(_familiasDamnificadasController) > 0;

  bool get _s03Completada =>
      _locConPoblacion.any((l) => l.impactoPoblacion.any((i) => i.tieneDatosGlobales));

  bool get _s04Completada =>
      _locConSalud.any((l) =>
          l.establecimientosSalud.any((s) => s.nombreEstablecimiento.trim().isNotEmpty) ||
          (l.necesidadSalud?.botiquines ?? false) ||
          (l.necesidadSalud?.numeroPersonas ?? 0) > 0);

  bool get _aplicaNecesidadesSalud {
    final t = _tipoEventoNombre
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    return t.contains('incendio') ||
        t.contains('inundacion') ||
        t.contains('sequia');
  }

  bool get _s05Completada =>
      _locConInfraestructura.any((l) =>
          l.danosViales.any((d) => d.viaPuente.trim().isNotEmpty) ||
          l.danosInfraPublica.any((d) => d.tipoEstructura.trim().isNotEmpty));

  bool get _s06Completada =>
      _locConServicios.any((l) => l.serviciosBasicos.any((s) => s.tieneDatos));

  bool get _s07Completada =>
      _locConEducacion.any((l) => l.unidadesEducativas.any((u) =>
          u.nombreEstablecimiento.trim().isNotEmpty ||
          u.estudiantes > 0 ||
          u.profesores > 0 ||
          u.administrativos > 0));

  bool get _s08Completada =>
      _locConVivienda.any((l) => l.danosVivienda.any((v) => v.danoParcial > 0 || v.danoTotal > 0));

  bool get _s09Completada =>
      _locConAgropecuario.any((l) =>
          l.danosAgricultura.any((a) => a.tipoCultivo.trim().isNotEmpty) ||
          l.danosPecuarios.any((p) => p.especie.trim().isNotEmpty) ||
          l.infraProductiva.any((i) => i.tipo.trim().isNotEmpty));

  bool get _s10Completada =>
      _locConProteccion.any((l) => l.proteccion.any((g) => g.tieneDatos));

  bool get _s11Completada =>
      _locConNecesidades.any((l) => l.necesidadHumanitaria?.algunaSeleccionada ?? false);

  bool get _s13Completada =>
      _edan.responsable.nombre.trim().isNotEmpty &&
      _edan.responsable.cargo.trim().isNotEmpty;

  // ---------- Acciones ----------

  Future<void> _pickFechaLlenado() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaLlenado,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fechaLlenado = picked;
      _fechaLlenadoController.text = _fmtFecha(picked);
    });
  }

  Future<void> _pickFechaEvento() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaEvento,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fechaEvento = picked;
      _fechaEventoController.text = _fmtFecha(picked);
    });
  }

  void _agregarLocalidad() {
    setState(() => _edan.localidades.add(EdanLocalidad()));
  }

  Future<void> _eliminarLocalidad(int index) async {
    if (_edan.localidades.length <= 1) return;
    final ok = await _confirmarConfirmacionLocalidad();
    if (!ok || !mounted) return;
    setState(() => _edan.localidades.removeAt(index));
  }

  Future<bool> _confirmarConfirmacionLocalidad() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Eliminar lugar afectado?'),
            content: const Text('Se eliminará este lugar afectado del EDAN.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmarEliminarItem(String mensaje) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Eliminar ítem?'),
            content: Text(mensaje),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _confirmarAgregarSubitem({
    required String etiquetaLugar,
    required String item,
    required String articuloUno,
    required String articuloOtro,
    required int cantidad,
    required VoidCallback onAgregar,
  }) async {
    final articulo = cantidad == 0 ? articuloUno : articuloOtro;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar elemento'),
        content: Text(
          '¿Está seguro de agregar $articulo $item en $etiquetaLugar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      onAgregar();
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _focusNodeId = null);
        });
      });
    }
  }

  Future<void> _recalcularNumeroEdan() async {
    final municipioId =
        _idMunicipio ?? AuthService.instance.currentToken?.idMunicipio;
    if (municipioId == null) return;
    final db = DatabaseHelper.instance;
    final rp = context.read<ReporteProvider>();
    final count =
        await db.countEdansPorMunicipioAnio(municipioId, DateTime.now().year);
    var ine = '';
    final municipio =
        rp.municipios.where((m) => m.id == municipioId).firstOrNull;
    if (municipio != null) {
      ine = municipio.codigoIne;
    } else {
      ine = (await db.getCodigoIneMunicipio(municipioId)) ?? '';
    }
    if (!mounted) return;
    setState(() {
      _codigoIne = ine.isEmpty ? '---' : ine;
      _siguienteNumero = count + 1;
    });
  }

  void _resolverIdTipoEvento() {
    if ((_idTipoEvento == null || _idTipoEvento == 0) &&
        _tipoEventoNombre.isNotEmpty) {
      _idTipoEvento = context
          .read<ReporteProvider>()
          .tiposEvento
          .where((c) => c.nombre == _tipoEventoNombre)
          .firstOrNull
          ?.idTipoEvento;
    }
  }

  void _normalizarLocalidad(EdanLocalidad loc) {
    final canon = tipoLocalidadNombreCanonico(loc.tipoLocalidad);
    if (canon != null && canon != loc.tipoLocalidad) {
      loc.tipoLocalidad = canon;
    }
    if (loc.idTipoLocalidad == null || loc.idTipoLocalidad == 0) {
      loc.idTipoLocalidad = tipoLocalidadIdPorNombre(loc.tipoLocalidad);
    }
    if (loc.idTipoEvento == 0) loc.idTipoEvento = null;
  }

  Edan _construirEdan() {
    _resolverIdTipoEvento();
    final anio = DateTime.now().year;
    if (_edan.codigoEdan.isEmpty && _idMunicipio != null) {
      _edan.codigoEdan =
          '$_codigoIne/$anio/${_siguienteNumero.toString().padLeft(3, '0')}';
    }
    _edan.idTipoEvento = _idTipoEvento;
    _edan.tipoEventoNombre = _tipoEventoNombre.isEmpty ? 'Evento' : _tipoEventoNombre;
    _edan.idDepartamento = _idDepartamento;
    _edan.idProvincia = _idProvincia;
    _edan.idMunicipio = _idMunicipio;
    _edan.idUsuario = _idUsuarioAlcalde;
    _edan.nombreAlcalde = _nombreAlcaldeController.text.trim();
    _edan.fonoAlcalde = _fonoAlcaldeController.text.trim();
    _edan.fechaLlenado = _fmtIso(_fechaLlenado);
    _edan.fechaEvento = _fmtIso(_fechaEvento);
    _edan.horaEvento = _horaIso();
    _edan.totalPoblacionAfectada = _intDe(_poblacionController);
    _edan.totalFamiliasAfectadas = _intDe(_familiasAfectadasController);
    _edan.totalFamiliasDamnificadas = _intDe(_familiasDamnificadasController);
    for (final localidad in _edan.localidades) {
      _normalizarLocalidad(localidad);
      for (final item in localidad.impactoPoblacion) {
        item.idSeccion ??= generarIdSeccion('im');
      }
      localidad.necesidadPrimeraRespuesta?.idSeccion ??= generarIdSeccion('pr');
      for (final item in localidad.establecimientosSalud) {
        item.idSeccion ??= generarIdSeccion('sv');
      }
      localidad.necesidadSalud?.idSeccion ??= generarIdSeccion('sn');
      for (final item in localidad.danosViales) {
        item.idSeccion ??= generarIdSeccion('dv');
      }
      for (final item in localidad.danosInfraPublica) {
        item.idSeccion ??= generarIdSeccion('di');
      }
      for (final item in localidad.serviciosBasicos) {
        item.idSeccion ??= generarIdSeccion('sb');
      }
      for (final item in localidad.unidadesEducativas) {
        item.idSeccion ??= generarIdSeccion('ue');
      }
      for (final item in localidad.danosVivienda) {
        item.idSeccion ??= generarIdSeccion('vv');
      }
      for (final item in localidad.danosAgricultura) {
        item.idSeccion ??= generarIdSeccion('da');
      }
      for (final item in localidad.danosPecuarios) {
        item.idSeccion ??= generarIdSeccion('dp');
      }
      for (final item in localidad.infraProductiva) {
        item.idSeccion ??= generarIdSeccion('ip');
      }
      for (final item in localidad.proteccion) {
        item.idSeccion ??= generarIdSeccion('po');
      }
      localidad.necesidadHumanitaria?.idSeccion ??= generarIdSeccion('nh');
    }
    return _edan;
  }

  Future<void> _revisar() async {
    final edan = _construirEdan();
    final confirmado = await Navigator.of(context).push<Edan>(
      MaterialPageRoute(
        builder: (_) => UgrEdanPreviewScreen(edan: edan),
      ),
    );
    if (confirmado == null || !mounted) return;
    
    // Guardar EDAN confirmado
    final userId = AuthService.instance.userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: usuario no autenticado'),
          backgroundColor: AppColors.rechazado,
        ),
      );
      return;
    }
    
    try {
      confirmado
        ..estado = 'enviado'
        ..idEstado = 2
        ..esBorrador = false;
      
      if (confirmado.idLocal != null) {
        await DatabaseHelper.instance.updateEdan(confirmado);
      } else {
        await DatabaseHelper.instance.insertEdan(confirmado, usuarioId: userId);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('EDAN enviado correctamente'),
          backgroundColor: AppColors.aprobado,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: AppColors.rechazado,
        ),
      );
    }
  }

  void _toggle(String num) {
    setState(() {
      if (!_expandidas.add(num)) _expandidas.remove(num);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    final refCtx = _indicadorKey.currentContext;
    if (refCtx == null) return;
    final refBox = refCtx.findRenderObject();
    if (refBox is! RenderBox) return;
    final refTop = refBox.localToGlobal(Offset.zero).dy;
    String? actual;
    _sectionKeys.forEach((numero, key) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      if (box.localToGlobal(Offset.zero).dy <= refTop) actual = numero;
    });
    if (actual != _seccionActual) {
      setState(() => _seccionActual = actual);
    }
  }

  String? get _tituloIndicador {
    final n = _seccionActual;
    if (n == null) return null;
    final t = _titulosSeccion[n];
    if (t == null) return null;
    return '$n · $t';
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Scaffold(
      backgroundColor: PaletteScope.of(context).background,
      appBar: AppBar(
        title: const Text(
          'Nuevo EDAN',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: PaletteScope.of(context).primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(primary),
                  const SizedBox(height: 16),
                  _seccion01(),
                  _seccion02(),
                  _seccion03(),
                  _seccion04(),
                  _seccion05(),
                  _seccion06(),
                  _seccion07(),
                  _seccion08(),
                  _seccion09(),
                  _seccion10(),
                  _seccion11(),
                  _seccion13(),
                  const SizedBox(height: 8),
                  _buildDeclaracion(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: _IndicadorSeccion(
                  key: _indicadorKey,
                  texto: _tituloIndicador,
                  visible: _seccionActual != null,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildActionsBar(),
    );
  }

  Widget _buildHeader(Color primary) {
    final anio = DateTime.now().year;
    final codigo = _edan.codigoEdan.isNotEmpty
        ? _edan.codigoEdan
        : '$_codigoIne/$anio/${_siguienteNumero.toString().padLeft(3, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Text(
            'EVALUACIÓN DE DAÑOS Y\nANÁLISIS DE NECESIDADES',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'N° $codigo',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: primary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Formulario de registro · Unidad de Gestión de Riesgos',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ---------- 01 Datos generales ----------

  Widget _seccion01() {

    return _SeccionEdan(
      key: _sectionKeys['01'],
      numero: '01',
      titulo: 'Datos generales',
      descripcion: 'Ubicación, lugar, responsable y fechas',
      completada: _s01Completada,
      expanded: _expandidas.contains('01'),
      onToggle: () => _toggle('01'),
      children: [
        _subtitulo('Ubicación'),
        _buildUbicacion(),
        if (_edan.idReporte != null) ...[
          const SizedBox(height: 16),
          _subtitulo('Reporte vinculado'),
          _buildReporteVinculado(),
        ],
        const SizedBox(height: 16),
        _subtitulo('Lugares afectados'),
        if (_edan.localidades.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Text(
              'Agregue al menos un lugar afectado.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          ..._edan.localidades.asMap().entries.map((entry) {
            final i = entry.key;
            final localidad = entry.value;
            return Padding(
              key: ObjectKey(localidad),
              padding: const EdgeInsets.only(bottom: 12),
              child: _TarjetaLocalidad(
                localidad: localidad,
                index: i,
                puedeEliminar: _edan.localidades.length > 1,
                onEliminar: () => _eliminarLocalidad(i),
                onChanged: () => setState(() {}),
              ),
            );
          }),
        _AgregarBoton(
          label: 'Agregar lugar',
          onPressed: _agregarLocalidad,
        ),
        const SizedBox(height: 16),
        _subtitulo('Responsable'),
        _buildUsuarioAlcalde(),
        const SizedBox(height: 12),
        _campo(
          label: 'Teléfono *',
          controller: _fonoAlcaldeController,
          hint: 'Ej: 70700000',
          readOnly: _idUsuarioAlcalde != null,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(20),
          ],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        _subtitulo('Fechas'),
        _buildTipoEvento(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _campo(
                label: 'Fecha llenado *',
                controller: _fechaLlenadoController,
                readOnly: true,
                onTap: _pickFechaLlenado,
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _campo(
                label: 'Fecha evento *',
                controller: _fechaEventoController,
                readOnly: true,
                onTap: _pickFechaEvento,
                suffixIcon: const Icon(Icons.event_outlined, size: 18),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildHora(),
      ],
    );
  }

  Widget _buildTipoEvento() {
    return Consumer<ReporteProvider>(
      builder: (context, rp, _) {
        final catalogo = rp.tiposEvento;
        final nombres = catalogo.isNotEmpty
            ? (catalogo.map((t) => t.nombre).toList()..sort())
            : _tiposEvento;
        String? valor = _tipoEventoNombre.isEmpty ? null : _tipoEventoNombre;
        if (catalogo.isNotEmpty && _idTipoEvento != null) {
          final porId = catalogo
              .where((c) => c.idTipoEvento == _idTipoEvento)
              .firstOrNull;
          if (porId != null) valor = porId.nombre;
        }
        return _buildDropdown<String>(
          context: context,
          key: ValueKey('tipoEvento-$_tipoEventoNombre'),
          label: 'Tipo de evento adverso *',
          value: valor,
          items: nombres
              .map((n) => DropdownMenuItem(value: n, child: Text(n)))
              .toList(),
          hint: 'Seleccione tipo de evento',
          onChanged: (v) {
            setState(() {
              _tipoEventoNombre = v ?? '';
              _idTipoEvento = catalogo.isNotEmpty && v != null
                  ? catalogo
                      .firstWhere((c) => c.nombre == v,
                          orElse: () => catalogo.first)
                      .idTipoEvento
                  : null;
            });
          },
        );
      },
    );
  }

  Widget _buildUsuarioAlcalde() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown<int>(
          context: context,
          key: ValueKey('usuarioAlcalde-$_idUsuarioAlcalde'),
          label: 'Usuario alcalde *',
          value: _idUsuarioAlcalde,
          items: [
            const DropdownMenuItem(value: -1, child: Text('+ Agregar nuevo')),
            ...(_usuarios.toList()..sort((a, b) => a.nombre.compareTo(b.nombre))).map((u) => DropdownMenuItem(
                  value: u.idUsuario,
                  child: Text(u.nombre, overflow: TextOverflow.ellipsis),
                )),
          ],
          etiquetaValorGuardado: _nombreAlcaldeController.text.isNotEmpty
              ? _nombreAlcaldeController.text
              : null,
          hint: _usuarios.isEmpty
              ? (_errorUsuarios.isNotEmpty
                  ? 'No se pudieron cargar los usuarios'
                  : 'Cargando usuarios...')
              : 'Seleccione usuario',
          onChanged: (v) async {
            if (v == -1) {
              final token = AuthService.instance.currentToken;
              final nuevoId = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                  builder: (_) => CrearUsuarioScreen(
                    idMunicipio: token?.idMunicipio,
                    idProvincia: token?.idProvincia,
                    idDepartamento: token?.idDepartamento,
                  ),
                ),
              );
              if (nuevoId != null && mounted) {
                await _cargarUsuariosAlcalde();
                if (!mounted) return;
                setState(() {
                  _idUsuarioAlcalde = nuevoId;
                  final user = _usuarios.where((u) => u.idUsuario == nuevoId).firstOrNull;
                  if (user != null) {
                    _nombreAlcaldeController.text = user.nombre;
                    _fonoAlcaldeController.text = user.celular ?? '';
                  }
                });
              }
            } else {
              setState(() => _idUsuarioAlcalde = v);
              if (v != null) {
                final user = _usuarios.where((u) => u.idUsuario == v).firstOrNull;
                if (user != null) {
                  _nombreAlcaldeController.text = user.nombre;
                  _fonoAlcaldeController.text = user.celular ?? '';
                }
              }
            }
          },
        ),
        if (_errorUsuarios.isNotEmpty && _usuarios.isEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: _cargarUsuariosAlcalde,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No se pudo cargar la lista de alcaldes:\n$_errorUsuarios\n\nToca aquí para reintentar.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.error,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.error,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHora() {
    final primary = PaletteScope.of(context).primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hora del evento *',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _hora12,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
                items: _itemsConValor<String>(
                  List.generate(12, (i) {
                    final v = (i + 1).toString().padLeft(2, '0');
                    return DropdownMenuItem(value: v, child: Text('$v:00'));
                  }),
                  _hora12,
                ),
                hint: const Text(
                  'Seleccione hora',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                onChanged: (v) => setState(() => _hora12 = v ?? _hora12),
              ),
            ),
            const SizedBox(width: 12),
            _ampmBtn('AM'),
            const SizedBox(width: 4),
            _ampmBtn('PM'),
          ],
        ),
      ],
    );
  }

  Widget _ampmBtn(String label) {
    final selected = _ampm == label;
    final primary = PaletteScope.of(context).primary;
    return GestureDetector(
      onTap: () => setState(() => _ampm = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildUbicacion() {
    return Consumer<ReporteProvider>(
      builder: (context, rp, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDropdown<int>(
              context: context,
              key: ValueKey('departamento-$_idDepartamento'),
              label: 'Departamento *',
              value: _idDepartamento,
              items: (rp.departamentos.toList()..sort((a, b) => a.nombre.compareTo(b.nombre)))
                  .map((d) => DropdownMenuItem(value: d.id, child: Text(d.nombre)))
                  .toList(),
              etiquetaValorGuardado: _edan.departamentoNombre,
              hint: 'Seleccione departamento',
              onChanged: (v) {
                setState(() {
                  _idDepartamento = v;
                  _idProvincia = null;
                  _idMunicipio = null;
                });
                if (v != null) rp.loadProvincias(v);
              },
            ),
            const SizedBox(height: 12),
            if (rp.isLoadingProvincias)
              _cargandoRow('Cargando provincias...')
            else
              _buildDropdown<int>(
                context: context,
                key: ValueKey('provincia-$_idProvincia'),
                label: 'Provincia *',
                value: _idProvincia,
                items: (rp.provincias.toList()..sort((a, b) => a.nombre.compareTo(b.nombre)))
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                    .toList(),
                etiquetaValorGuardado: _edan.provinciaNombre,
                hint: 'Seleccione provincia',
                onChanged: (v) {
                  setState(() {
                    _idProvincia = v;
                    _idMunicipio = null;
                  });
                  if (v != null && _idDepartamento != null) {
                    rp.loadMunicipios(v, _idDepartamento!);
                  }
                },
              ),
            const SizedBox(height: 12),
            if (rp.isLoadingMunicipios)
              _cargandoRow('Cargando municipios...')
            else
              _buildDropdown<int>(
                context: context,
                key: ValueKey('municipio-$_idMunicipio'),
                label: 'Municipio *',
                value: _idMunicipio,
                items: (rp.municipios.toList()..sort((a, b) => a.nombre.compareTo(b.nombre)))
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.nombre)))
                    .toList(),
                etiquetaValorGuardado: _edan.municipioNombre,
                hint: 'Seleccione municipio',
                onChanged: (v) {
                  setState(() => _idMunicipio = v);
                  _recalcularNumeroEdan();
                },
              ),
          ],
        );
      },
    );
  }

  Widget _cargandoRow(String texto) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildReporteVinculado() {
    return const SizedBox.shrink();
  }

  // ---------- 02 Población ----------

  Widget _seccion02() {

    return _SeccionEdan(
      key: _sectionKeys['02'],
      numero: '02',
      titulo: 'Información total población afectada y damnificada',
      descripcion: 'Totales estimados a la fecha del evento',
      completada: _s02Completada,
      expanded: _expandidas.contains('02'),
      onToggle: () => _toggle('02'),
      children: [
        _numCampo(
          label: 'Población total afectada',
          controller: _poblacionController,
          hint: 'Ej: 1250',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _numCampo(
          label: 'Total de familias afectadas',
          controller: _familiasAfectadasController,
          hint: 'Ej: 260',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _numCampo(
          label: 'Total de familias damnificadas',
          controller: _familiasDamnificadasController,
          hint: 'Ej: 90',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ---------- 03 Municipio afectado ----------

  Widget _seccion03() {
    final locs = _locConPoblacion;
    if (locs.isEmpty) return const SizedBox.shrink();

    final totalF = locs.fold<int>(0, (acc, l) => acc + (l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0].fallecidos : 0));
    final totalH = locs.fold<int>(0, (acc, l) => acc + (l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0].heridos : 0));
    final totalD = locs.fold<int>(0, (acc, l) => acc + (l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0].desaparecidos : 0));

    return _SeccionEdan(
      key: _sectionKeys['03'],
      numero: '03',
      titulo: 'Impacto en la población',
      descripcion: 'Impacto en la población y necesidades de primera respuesta',
      completada: _s03Completada,
      expanded: _expandidas.contains('03'),
      onToggle: () => _toggle('03'),
      children: [
        _subtitulo('3.2 Impacto en la población por grupo etario'),
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ValueKey('s03-imp-$i'),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              ...(l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0].gruposEtarios.asMap().entries : <MapEntry<int, EdanGrupoEtario>>[]).map((ge) {
                return _FilaGrupoEtarioAutonomo(
                  titulo: ge.value.rango,
                  grupo: ge.value,
                  onChanged: () {
                    _sincronizarImpacto(l);
                    setState(() {});
                  },
                );
              }),
            ],
          );
        }),
        _CajaTotales(valores: [
          ('Fallecidos', '$totalF'),
          ('Heridos', '$totalH'),
          ('Desaparecidos', '$totalD'),
        ]),
        const SizedBox(height: 8),
        _subtitulo('3.3 Necesidades en primera respuesta'),
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ValueKey('s03-resp-$i'),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              _SiNoAutonomo(
                label: 'Búsqueda y rescate',
                valor: l.necesidadPrimeraRespuesta?.busqueda ?? false,
                onValor: (v) => setState(() {
                  l.necesidadPrimeraRespuesta ??= EdanNecesidadPrimeraRespuesta()
                    ..idSeccion = generarIdSeccion('pr');
                  l.necesidadPrimeraRespuesta!.busqueda = v;
                }),
              ),
              const SizedBox(height: 8),
              _SiNoAutonomo(
                label: 'Salvamento',
                valor: l.necesidadPrimeraRespuesta?.salvamento ?? false,
                onValor: (v) => setState(() {
                  l.necesidadPrimeraRespuesta ??= EdanNecesidadPrimeraRespuesta()
                    ..idSeccion = generarIdSeccion('pr');
                  l.necesidadPrimeraRespuesta!.salvamento = v;
                }),
              ),
              const SizedBox(height: 8),
              _SiNoAutonomo(
                label: 'Evacuación',
                valor: l.necesidadPrimeraRespuesta?.evacuacion ?? false,
                onValor: (v) => setState(() {
                  l.necesidadPrimeraRespuesta ??= EdanNecesidadPrimeraRespuesta()
                    ..idSeccion = generarIdSeccion('pr');
                  l.necesidadPrimeraRespuesta!.evacuacion = v;
                }),
              ),
              const SizedBox(height: 8),
              _CampoAutonomo(
                label: 'Observaciones',
                valor: l.necesidadPrimeraRespuesta?.observaciones ?? '',
                maxLines: 2,
                onChanged: (v) {
                  l.necesidadPrimeraRespuesta ??= EdanNecesidadPrimeraRespuesta()
                    ..idSeccion = generarIdSeccion('pr');
                  l.necesidadPrimeraRespuesta!.observaciones = v;
                  setState(() {});
                },
              ),
            ],
          );
        }),
      ],
    );
  }

  void _sincronizarImpacto(EdanLocalidad l) {
    if (l.impactoPoblacion.isEmpty) {
      l.impactoPoblacion.add(EdanImpactoPoblacion()
        ..idSeccion = generarIdSeccion('im'));
    }
    final ip = l.impactoPoblacion[0];
    ip.fallecidos = ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.fallecidos);
    ip.heridos = ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.heridos);
    ip.desaparecidos = ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.desaparecidos);
    ip.grupoEtario = 'Total';
  }

  // ---------- 04 Salud ----------

  Widget _seccion04() {
    final locs = _locConSalud;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      key: _sectionKeys['04'],
      numero: '04',
      titulo: 'Impacto en la salud',
      descripcion: 'Daños en servicios de salud y necesidades',
      completada: _s04Completada,
      expanded: _expandidas.contains('04'),
      onToggle: () => _toggle('04'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          final totalEst = l.establecimientosSalud.length;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              _subtitulo('4.1 Daños en servicios de salud ($totalEst)'),
              ...List.generate(l.establecimientosSalud.length, (j) {
                final valor = l.establecimientosSalud[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaSaludRow(
                    titulo: 'Establecimiento ${j + 1}',
                    valor: valor,
                    comunidadInicial: l.etiquetaLugar,
                    puedeEliminar: l.establecimientosSalud.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará este establecimiento de salud.');
                      if (!ok || !mounted) return;
                      setState(() => l.establecimientosSalud.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar establecimiento',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'establecimiento',
                  articuloUno: 'un',
                  articuloOtro: 'otro',
                   cantidad: l.establecimientosSalud.length,
                    onAgregar: () {
                        final item = EdanEstablecimientoSalud()
                          ..idSeccion = generarIdSeccion('sv')
                          ..comunidad = l.etiquetaLugar;
                        setState(() {
                          l.establecimientosSalud.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
              if (_aplicaNecesidadesSalud) ...[
                const SizedBox(height: 12),
                _subtitulo('4.2 Necesidades en salud'),
                _GrupoDeCampos(
                  titulo: 'Necesidades en salud',
                  children: [
                    const Text(
                      'Botiquín',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Número de personas que requieren atención inmediata',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _NumCampoAutonomo(
                      label: 'Número de personas',
                      valor: l.necesidadSalud?.numeroPersonas != null && l.necesidadSalud!.numeroPersonas > 0
                          ? '${l.necesidadSalud!.numeroPersonas}'
                          : '',
                      onChanged: (v) {
                        l.necesidadSalud ??= EdanNecesidadSalud()
                          ..idSeccion = generarIdSeccion('sn');
                        l.necesidadSalud!.numeroPersonas = int.tryParse(v.trim()) ?? 0;
                        l.necesidadSalud!.botiquines = l.necesidadSalud!.numeroPersonas > 0;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _CampoAutonomo(
                      label: 'Otras necesidades',
                      valor: l.necesidadSalud?.otrasNecesidades ?? '',
                      maxLines: 2,
                      onChanged: (v) {
                        l.necesidadSalud ??= EdanNecesidadSalud()
                          ..idSeccion = generarIdSeccion('sn');
                        l.necesidadSalud!.otrasNecesidades = v;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _CampoAutonomo(
                      label: 'Observaciones',
                      valor: l.necesidadSalud?.observaciones ?? '',
                      maxLines: 2,
                      onChanged: (v) {
                        l.necesidadSalud ??= EdanNecesidadSalud()
                          ..idSeccion = generarIdSeccion('sn');
                        l.necesidadSalud!.observaciones = v;
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Establecimientos',
            '${locs.fold<int>(0, (a, l) => a + l.establecimientosSalud.length)}'
          ),
          if (_aplicaNecesidadesSalud)
            (
              'Número de personas',
              '${locs.fold<int>(0, (a, l) => a + (l.necesidadSalud?.numeroPersonas ?? 0))}'
            ),
        ]),
      ],
    );
  }

  // ---------- 05 Infraestructura ----------

  Widget _seccion05() {
    final locs = _locConInfraestructura;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      key: _sectionKeys['05'],
      numero: '05',
      titulo: 'Impacto en infraestructuras',
      descripcion: 'Daños viales y en infraestructura pública',
      completada: _s05Completada,
      expanded: _expandidas.contains('05'),
      onToggle: () => _toggle('05'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              _subtitulo('5.1 Daños en infraestructura vial'),
              ...List.generate(l.danosViales.length, (j) {
                final valor = l.danosViales[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaVialRow(
                    titulo: 'Vía / puente ${j + 1}',
                    valor: valor,
                    puedeEliminar: l.danosViales.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará este registro de vía o puente.');
                      if (!ok || !mounted) return;
                      setState(() => l.danosViales.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar vía / puente',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'vía / puente',
                  articuloUno: 'una',
                  articuloOtro: 'otra',
                   cantidad: l.danosViales.length,
                    onAgregar: () {
                        final item = EdanDanoVial()
                          ..idSeccion = generarIdSeccion('dv');
                        setState(() {
                          l.danosViales.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
              const SizedBox(height: 12),
              _subtitulo('5.2 Daños en infraestructura pública'),
              ...List.generate(l.danosInfraPublica.length, (j) {
                final valor = l.danosInfraPublica[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaInfraRow(
                    titulo: 'Estructura ${j + 1}',
                    valor: valor,
                    comunidadInicial: l.etiquetaLugar,
                    puedeEliminar: l.danosInfraPublica.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará este registro de infraestructura pública.');
                      if (!ok || !mounted) return;
                      setState(() => l.danosInfraPublica.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar estructura',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'estructura',
                  articuloUno: 'una',
                  articuloOtro: 'otra',
                   cantidad: l.danosInfraPublica.length,
                    onAgregar: () {
                        final item = EdanDanoInfraPublica()
                          ..idSeccion = generarIdSeccion('di')
                          ..comunidad = l.etiquetaLugar;
                        setState(() {
                          l.danosInfraPublica.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Vías / puentes',
            '${locs.fold<int>(0, (a, l) => a + l.danosViales.length)}'
          ),
          (
            'Estructuras',
            '${locs.fold<int>(0, (a, l) => a + l.danosInfraPublica.length)}'
          ),
        ]),
      ],
    );
  }

  // ---------- 06 Servicios básicos ----------

  Widget _seccion06() {
    final locs = _locConServicios;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      key: _sectionKeys['06'],
      numero: '06',
      titulo: 'Impacto en servicios básicos',
      descripcion: 'Agua, luz, alcantarillado y comunicaciones',
      completada: _s06Completada,
      expanded: _expandidas.contains('06'),
      onToggle: () => _toggle('06'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              _subtitulo('6.1 Servicios afectados'),
              ...List.generate(l.serviciosBasicos.length, (j) {
                final s = l.serviciosBasicos[j];
                return Padding(
                  key: ObjectKey(s),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaServicioRow(
                    titulo: s.etiqueta,
                    valor: s,
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(s) == _focusNodeId,
                  ),
                );
              }),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Localidades',
            '${locs.fold<int>(0, (a, l) => a + (l.serviciosBasicos.any((s) => s.tieneDatos) ? 1 : 0))}'
          ),
        ]),
      ],
    );
  }

  // ---------- 07 Educación ----------

  Widget _seccion07() {
    final locs = _locConEducacion;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      key: _sectionKeys['07'],
      numero: '07',
      titulo: 'Impacto en educación',
      descripcion: 'Unidades educativas y afectación de personal',
      completada: _s07Completada,
      expanded: _expandidas.contains('07'),
      onToggle: () => _toggle('07'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              ...List.generate(l.unidadesEducativas.length, (j) {
                final valor = l.unidadesEducativas[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaEduRow(
                    titulo: 'Unidad educativa ${j + 1}',
                    valor: valor,
                    comunidadInicial: l.etiquetaLugar,
                    puedeEliminar: l.unidadesEducativas.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará esta unidad educativa.');
                      if (!ok || !mounted) return;
                      setState(() => l.unidadesEducativas.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar unidad educativa',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'unidad educativa',
                  articuloUno: 'una',
                  articuloOtro: 'otra',
                   cantidad: l.unidadesEducativas.length,
                    onAgregar: () {
                        final item = EdanDanoUnidadEducativa()
                          ..idSeccion = generarIdSeccion('ue')
                          ..comunidad = l.etiquetaLugar;
                        setState(() {
                          l.unidadesEducativas.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Unidades educativas',
            '${locs.fold<int>(0, (a, l) => a + l.unidadesEducativas.length)}'
          ),
          (
            'Estudiantes',
            '${locs.fold<int>(0, (a, l) => a + l.unidadesEducativas.fold<int>(0, (x, u) => x + u.estudiantes))}'
          ),
          (
            'Profesores',
            '${locs.fold<int>(0, (a, l) => a + l.unidadesEducativas.fold<int>(0, (x, u) => x + u.profesores))}'
          ),
          (
            'Administrativos',
            '${locs.fold<int>(0, (a, l) => a + l.unidadesEducativas.fold<int>(0, (x, u) => x + u.administrativos))}'
          ),
          (
            'Total afectados',
            '${locs.fold<int>(0, (a, l) => a + l.unidadesEducativas.fold<int>(0, (x, u) => x + u.totalAfectados))}'
          ),
        ]),
      ],
    );
  }

  // ---------- 08 Vivienda ----------

  Widget _seccion08() {
    final locs = _locConVivienda;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      key: _sectionKeys['08'],
      numero: '08',
      titulo: 'Impacto en viviendas',
      descripcion: 'Daños parciales y totales por localidad',
      completada: _s08Completada,
      expanded: _expandidas.contains('08'),
      onToggle: () => _toggle('08'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              ...List.generate(l.danosVivienda.length, (j) {
                final valor = l.danosVivienda[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaViviendaRow(
                    titulo: 'Vivienda ${j + 1}',
                    valor: valor,
                    comunidadInicial: l.etiquetaLugar,
                    puedeEliminar: l.danosVivienda.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará este registro de daño en viviendas.');
                      if (!ok || !mounted) return;
                      setState(() => l.danosVivienda.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar vivienda',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'vivienda',
                  articuloUno: 'una',
                  articuloOtro: 'otra',
                   cantidad: l.danosVivienda.length,
                    onAgregar: () {
                        final item = EdanDanoVivienda()
                          ..idSeccion = generarIdSeccion('vv')
                          ..comunidad = l.etiquetaLugar;
                        setState(() {
                          l.danosVivienda.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Daño parcial',
            '${locs.fold<int>(0, (a, l) => a + l.danosVivienda.fold<int>(0, (s, v) => s + v.danoParcial))}'
          ),
          (
            'Daño total',
            '${locs.fold<int>(0, (a, l) => a + l.danosVivienda.fold<int>(0, (s, v) => s + v.danoTotal))}'
          ),
        ]),
      ],
    );
  }

  // ---------- 09 Agropecuario ----------

  Widget _seccion09() {
    final locs = _locConAgropecuario;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      key: _sectionKeys['09'],
      numero: '09',
      titulo: 'Impacto agropecuario',
      descripcion: 'Agricultura, pecuario e infraestructura productiva',
      completada: _s09Completada,
      expanded: _expandidas.contains('09'),
      onToggle: () => _toggle('09'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              _subtitulo('9.1 Daños en agricultura'),
              ...List.generate(l.danosAgricultura.length, (j) {
                final valor = l.danosAgricultura[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaAgriculturaRow(
                    titulo: 'Cultivo ${j + 1}',
                    valor: valor,
                    puedeEliminar: l.danosAgricultura.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará este cultivo.');
                      if (!ok || !mounted) return;
                      setState(() => l.danosAgricultura.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar cultivo',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'cultivo',
                  articuloUno: 'un',
                  articuloOtro: 'otro',
                   cantidad: l.danosAgricultura.length,
                    onAgregar: () {
                        final item = EdanDanoAgricultura()
                          ..idSeccion = generarIdSeccion('da');
                        setState(() {
                          l.danosAgricultura.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
              const SizedBox(height: 12),
              _subtitulo('9.2 Daños pecuarios'),
              ...List.generate(l.danosPecuarios.length, (j) {
                final valor = l.danosPecuarios[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaPecuarioRow(
                    titulo: 'Especie ${j + 1}',
                    valor: valor,
                    puedeEliminar: l.danosPecuarios.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará esta especie pecuaria.');
                      if (!ok || !mounted) return;
                      setState(() => l.danosPecuarios.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar especie',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'especie',
                  articuloUno: 'una',
                  articuloOtro: 'otra',
                   cantidad: l.danosPecuarios.length,
                    onAgregar: () {
                        final item = EdanDanoPecuario()
                          ..idSeccion = generarIdSeccion('dp');
                        setState(() {
                          l.danosPecuarios.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
              const SizedBox(height: 12),
              _subtitulo('9.3 Daños en infraestructura productiva'),
              ...List.generate(l.infraProductiva.length, (j) {
                final valor = l.infraProductiva[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaInfraProdRow(
                    titulo: 'Infraestructura ${j + 1}',
                    valor: valor,
                    puedeEliminar: l.infraProductiva.length > 1,
                    onEliminar: () async {
                      final ok = await _confirmarEliminarItem(
                          'Se eliminará esta infraestructura productiva.');
                      if (!ok || !mounted) return;
                      setState(() => l.infraProductiva.removeAt(j));
                    },
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(valor) == _focusNodeId,
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar infraestructura',
                onPressed: () => _confirmarAgregarSubitem(
                  etiquetaLugar: l.etiquetaLugar,
                  item: 'infraestructura',
                  articuloUno: 'una',
                  articuloOtro: 'otra',
                   cantidad: l.infraProductiva.length,
                    onAgregar: () {
                        final item = EdanInfraProductiva()
                          ..idSeccion = generarIdSeccion('ip');
                        setState(() {
                          l.infraProductiva.add(item);
                          _focusNodeId = item.idSeccion;
                        });
                      },
                ),
              ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Cultivos',
            '${locs.fold<int>(0, (a, l) => a + l.danosAgricultura.length)}'
          ),
          (
            'Especies',
            '${locs.fold<int>(0, (a, l) => a + l.danosPecuarios.length)}'
          ),
          (
            'Infraestructura',
            '${locs.fold<int>(0, (a, l) => a + l.infraProductiva.length)}'
          ),
        ]),
      ],
    );
  }

  // ---------- 10 Protección ----------

  Widget _seccion10() {
    final locs = _locConProteccion;
    if (locs.isEmpty) return const SizedBox.shrink();
    final rp = context.watch<ReporteProvider>();
    final catalogo = rp.gruposVulnerables;

    return _SeccionEdan(
      key: _sectionKeys['10'],
      numero: '10',
      titulo: 'Impacto en protección',
      descripcion: 'Población vulnerable y afectación por sexo',
      completada: _s10Completada,
      expanded: _expandidas.contains('10'),
      onToggle: () => _toggle('10'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.etiquetaLugar,
            children: [
              for (var j = 0; j < l.proteccion.length; j++)
                if (j > 0) ...[
                  const SizedBox(height: 10),
                  _FilaProteccionRow(
                    titulo: j < catalogo.length
                        ? catalogo[j].nombre
                        : 'Grupo ${j + 1}',
                    valor: l.proteccion[j],
                    soloMujeres: j < catalogo.length &&
                        catalogo[j].nombre.toLowerCase().contains('mujeres'),
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(l.proteccion[j]) == _focusNodeId,
                  ),
                ] else
                  _FilaProteccionRow(
                    titulo: catalogo.isNotEmpty
                        ? catalogo[0].nombre
                        : 'Grupo 1',
                    valor: l.proteccion[0],
                    soloMujeres: catalogo.isNotEmpty &&
                        catalogo[0].nombre.toLowerCase().contains('mujeres'),
                    onChanged: () => setState(() {}),
                    autoFocus: idSeccionDe(l.proteccion[0]) == _focusNodeId,
                  ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Mujeres',
            '${locs.fold<int>(0, (a, l) => a + l.proteccion.fold<int>(0, (x, g) => x + g.mujeres))}'
          ),
          (
            'Hombres',
            '${locs.fold<int>(0, (a, l) => a + l.proteccion.fold<int>(0, (x, g) => x + g.hombres))}'
          ),
          (
            'Total',
            '${locs.fold<int>(0, (a, l) => a + l.proteccion.fold<int>(0, (x, g) => x + g.total))}'
          ),
        ]),
      ],
    );
  }

  // ---------- 11 Necesidades humanitarias ----------

  Widget _seccion11() {
    final locs = _locConNecesidades;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      key: _sectionKeys['11'],
      numero: '11',
      titulo: 'Necesidades humanitarias',
      descripcion: 'Alimentos, refugio, higiene y otros por localidad',
      completada: _s11Completada,
      expanded: _expandidas.contains('11'),
      onToggle: () => _toggle('11'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _BloqueLocalidadNecesidades(
              key: ObjectKey(l),
              index: i,
              nombre: l.etiquetaLugar,
              necesidad: l.necesidadHumanitaria ?? EdanNecesidadHumanitaria(),
              onChanged: () => setState(() {}),
            ),
          );
        }),
      ],
    );
  }

  // ---------- 13 Responsable ----------

  Widget _seccion13() {
    final r = _edan.responsable;
    return _SeccionEdan(
      key: _sectionKeys['13'],
      numero: '13',
      titulo: 'Responsable del Formulario',
      descripcion: 'Datos del usuario registrado',
      completada: _s13Completada,
      expanded: _expandidas.contains('13'),
      onToggle: () => _toggle('13'),
      children: [
        _campo(
          label: 'Nombre',
          initial: r.nombre,
          readOnly: true,
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Cargo',
          initial: r.cargo,
          readOnly: true,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _campo(
                label: 'Teléfono',
                initial: r.fono,
                readOnly: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _campo(
                label: 'Correo',
                initial: r.correo,
                readOnly: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeclaracion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: AppColors.pending, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Declaración jurada: El presente formulario tiene carácter de '
              'declaración jurada. La información proporcionada debe ser '
              'correcta y será verificada por las autoridades '
              'correspondientes.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsBar() {
    final primary = PaletteScope.of(context).primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _guardarBorrador,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Borrador'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _revisar,
              icon: const Icon(Icons.preview, size: 18),
              label: const Text('V. previa'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarBorrador() async {
    final edan = _construirEdan();
    edan
      ..estado = 'borrador'
      ..idEstado = 1
      ..esBorrador = true;

    final userId = AuthService.instance.userId;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: usuario no autenticado'),
          backgroundColor: AppColors.rechazado,
        ),
      );
      return;
    }

    try {
      if (edan.idLocal != null) {
        await DatabaseHelper.instance.updateEdan(edan);
      } else {
        await DatabaseHelper.instance.insertEdan(edan, usuarioId: userId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('EDAN guardado como borrador'),
          backgroundColor: AppColors.aprobado,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: AppColors.rechazado,
        ),
      );
    }
  }

  // ---------- Helpers ----------

  int _intDe(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  String _fmtFecha(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _fmtIso(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _horaIso() {
    var h = int.tryParse(_hora12) ?? 0;
    if (_ampm == 'PM') {
      if (h != 12) h += 12;
    } else if (h == 12) {
      h = 0;
    }
    return '${h.toString().padLeft(2, '0')}:00';
  }

  void _aplicarHora24h(String horaEvento) {
    final partes = horaEvento.split(':');
    if (partes.isEmpty) return;
    final hora = int.tryParse(partes.first) ?? 12;
    _ampm = hora >= 12 ? 'PM' : 'AM';
    _hora12 = (hora % 12 == 0 ? 12 : hora % 12).toString().padLeft(2, '0');
  }
}

Widget _subtitulo(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _BotonSacarFoto extends StatefulWidget {
  final List<EdanFoto> fotos;
  final VoidCallback onChanged;
  final String? fotografia;
  final double coordenadaLat;
  final double coordenadaLon;
  final void Function(double lat, double lon)? onCoordenadasCapturadas;
  final String? seccion;

  const _BotonSacarFoto({
    required this.fotos,
    required this.onChanged,
    this.fotografia,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
    this.onCoordenadasCapturadas,
    this.seccion,
  });

  @override
  State<_BotonSacarFoto> createState() => _BotonSacarFotoState();
}

class _BotonSacarFotoState extends State<_BotonSacarFoto> {
  bool _cargando = false;
  String? _advertencia;

  Future<void> _sacarFoto() async {
    if (_cargando) return;
    setState(() {
      _cargando = true;
      _advertencia = null;
    });

    try {
      final camOk = await Permission.camera.request().isGranted;
      final locOk = await Permission.location.request().isGranted;
      if (!camOk || !locOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Se necesitan permisos de cámara y ubicación.'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() => _cargando = false);
        }
        return;
      }

      Position posicionFinal;
      try {
        posicionFinal = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        posicionFinal = await Geolocator.getLastKnownPosition() ??
            (await Geolocator.getCurrentPosition());
      }

      if (posicionFinal.accuracy > 30) {
        if (mounted) {
          setState(() {
            _advertencia = 'Precisión baja (${posicionFinal.accuracy.toStringAsFixed(0)}m). Intentando mejorar...';
          });
        }
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          ),
        ).listen((pos) {
          if (pos.accuracy <= 30) {
            posicionFinal = pos;
            if (mounted) {
              setState(() {
                _advertencia = 'Precisión mejorada: ${pos.accuracy.toStringAsFixed(0)}m';
              });
            }
          }
        });
      }

      final picker = ImagePicker();
      final imagen = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (imagen == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final nombreArchivo = 'edan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final archivo = File('${dir.path}/$nombreArchivo');
      await File(imagen.path).copy(archivo.path);

      widget.fotos.clear();
      widget.fotos.add(EdanFoto(
        ruta: archivo.path,
        latitud: posicionFinal.latitude,
        longitud: posicionFinal.longitude,
        precision: posicionFinal.accuracy,
      ));

      if (mounted) {
        widget.onCoordenadasCapturadas?.call(posicionFinal.latitude, posicionFinal.longitude);
        widget.onChanged();
        setState(() {
          _cargando = false;
          _advertencia = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _cargando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaria = PaletteScope.of(context).primary;
    final foto = widget.fotos.isNotEmpty ? widget.fotos.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_advertencia != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _advertencia!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.pending,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (foto != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(foto.ruta),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${foto.latitud.toStringAsFixed(4)}, ${foto.longitud.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '±${foto.precision.toStringAsFixed(0)}m',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final ok = await _confirmarEliminarFoto(context);
                        if (!ok) return;
                        widget.fotos.clear();
                        widget.onChanged();
                        setState(() => _advertencia = null);
                      },
                      child: const Icon(Icons.delete_outline, size: 16, color: AppColors.rechazado),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cargando ? null : _sacarFoto,
              icon: _cargando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.camera_alt_outlined, size: 18),
              label: Text(_cargando ? 'Obteniendo GPS...' : 'Sacar foto'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaria,
                side: BorderSide(color: primaria, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
      ],
    );
  }

  Future<bool> _confirmarEliminarFoto(BuildContext dialogCtx) async {
    return await showDialog<bool>(
          context: dialogCtx,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Eliminar foto?'),
            content: const Text('Se eliminará la foto de respaldo de este ítem.'),
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
        ) ??
        false;
  }
}

class _GrupoDeCampos extends StatelessWidget {
  final String titulo;
  final List<Widget> children;

  const _GrupoDeCampos({
    required this.titulo,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

List<DropdownMenuItem<T>> _itemsConValor<T>(
  List<DropdownMenuItem<T>> items,
  T? value, {
  String? etiqueta,
}) {
  if (value == null || items.any((i) => i.value == value)) return items;
  return <DropdownMenuItem<T>>[
    DropdownMenuItem<T>(
      value: value,
      child: Text(
        etiqueta ?? '$value',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    ...items,
  ];
}

Widget _buildDropdown<T>({
  required BuildContext context,
  required Key key,
  required String label,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
  String? hint,
  String? etiquetaValorGuardado,
}) {
  final primary = PaletteScope.of(context).primary;
  final itemsFinal = _itemsConValor<T>(
    items,
    value,
    etiqueta: etiquetaValorGuardado,
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<T>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary, width: 2),
          ),
        ),
        items: itemsFinal,
        onChanged: onChanged,
        hint: hint != null
            ? Text(
                hint,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                ),
              )
            : null,
      ),
    ],
  );
}

Widget _campo({
  required String label,
  TextEditingController? controller,
  String? initial,
  String? hint,
  TextInputType? keyboardType,
  TextCapitalization textCapitalization = TextCapitalization.none,
  bool readOnly = false,
  VoidCallback? onTap,
  Widget? suffixIcon,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
  List<TextInputFormatter>? inputFormatters,
  bool autofocus = false,
}) {
  return CustomTextField(
    label: label,
    hint: hint,
    controller: controller,
    initial: initial,
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    readOnly: readOnly,
    onTap: onTap,
    suffixIcon: suffixIcon,
    maxLines: maxLines,
    onChanged: onChanged,
    inputFormatters: inputFormatters,
    autofocus: autofocus,
  );
}

Widget _numCampo({
  required String label,
  TextEditingController? controller,
  String? hint,
  bool readOnly = false,
  ValueChanged<String>? onChanged,
  bool autofocus = false,
}) {
  return CustomTextField(
    label: label,
    hint: hint,
    controller: controller,
    keyboardType: TextInputType.number,
    readOnly: readOnly,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: onChanged,
    autofocus: autofocus,
  );
}

Widget _numCampoDecimal({
  required String label,
  TextEditingController? controller,
  String? hint,
  bool readOnly = false,
  ValueChanged<String>? onChanged,
}) {
  return CustomTextField(
    label: label,
    hint: hint,
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    readOnly: readOnly,
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
    ],
    onChanged: onChanged,
  );
}

Widget _checkInline({
  required bool value,
  required String label,
  required ValueChanged<bool> onChanged,
}) {
  return Row(
    children: [
      SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
        ),
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

Widget _siNoCheck({
  required bool? seleccionado,
  required ValueChanged<bool> onSeleccion,
}) {
  return Row(
    children: [
      Expanded(
        child: _checkInline(
          value: seleccionado == true,
          label: 'Sí',
          onChanged: (v) {
            if (v) onSeleccion(true);
          },
        ),
      ),
      Expanded(
        child: _checkInline(
          value: seleccionado == false,
          label: 'No',
          onChanged: (v) {
            if (v) onSeleccion(false);
          },
        ),
      ),
    ],
  );
}

class _SiNoAutonomo extends StatefulWidget {
  final String label;
  final bool valor;
  final ValueChanged<bool> onValor;

  const _SiNoAutonomo({
    required this.label,
    required this.valor,
    required this.onValor,
  });

  @override
  State<_SiNoAutonomo> createState() => _SiNoAutonomoState();
}

class _SiNoAutonomoState extends State<_SiNoAutonomo> {
  bool? _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.valor ? true : null;
  }

  @override
  Widget build(BuildContext context) {
    return _GrupoDeCampos(
      titulo: widget.label,
      children: [
        _siNoCheck(
          seleccionado: _sel,
          onSeleccion: (v) {
            _sel = v;
            widget.onValor(v);
            setState(() {});
          },
        ),
      ],
    );
  }
}

class _AgregarBoton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AgregarBoton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_circle_outline, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          backgroundColor: primary.withValues(alpha: 0.06),
          side: BorderSide(color: primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _SeccionEdan extends StatelessWidget {
  final String numero;
  final String titulo;
  final String descripcion;
  final bool completada;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _SeccionEdan({
    super.key,
    required this.numero,
    required this.titulo,
    required this.descripcion,
    required this.completada,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        numero,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (descripcion.isNotEmpty)
                          Text(
                            descripcion,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Badge(completada: completada),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

class _IndicadorSeccion extends StatelessWidget {
  final String? texto;
  final bool visible;

  const _IndicadorSeccion({
    super.key,
    required this.texto,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Center(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1 : 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.track_changes, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    texto ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final bool completada;

  const _Badge({required this.completada});

  @override
  Widget build(BuildContext context) {
    final color = completada ? AppColors.completed : AppColors.pending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        completada ? 'Completado' : 'Pendiente',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  final String titulo;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final List<Widget> children;

  const _RowCard({
    required this.titulo,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (puedeEliminar)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.rechazado,
                  tooltip: 'Quitar',
                  onPressed: onEliminar,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

// ---------- Localidades ----------

class _TarjetaLocalidad extends StatefulWidget {
  final EdanLocalidad localidad;
  final int index;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _TarjetaLocalidad({
    required this.localidad,
    required this.index,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_TarjetaLocalidad> createState() => _TarjetaLocalidadState();
}

class _TarjetaLocalidadState extends State<_TarjetaLocalidad> {
  late final TextEditingController _nombre;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.localidad.nombre);
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localidad = widget.localidad;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lugar ${widget.index + 1}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (widget.puedeEliminar)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.rechazado,
                  tooltip: 'Quitar lugar',
                  onPressed: widget.onEliminar,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Consumer<ReporteProvider>(
            builder: (context, rp, _) {
              final catalogo = rp.tiposLocalidad;
              final items = <DropdownMenuItem<String>>[];
              if (catalogo.isNotEmpty) {
                final ordenado = catalogo.toList()..sort((a, b) => a.nombre.compareTo(b.nombre));
                items.addAll(ordenado.map(
                  (t) => DropdownMenuItem(value: t.nombre, child: Text(t.nombre)),
                ));
              } else {
                final ordenado = kTiposLocalidadId.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
                items.addAll(ordenado.map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.key)),
                ));
              }
              String? valor =
                  localidad.tipoLocalidad.isEmpty ? null : localidad.tipoLocalidad;
              if (valor != null) {
                final canon = tipoLocalidadNombreCanonico(valor);
                if (canon != null && canon != valor) {
                  valor = canon;
                }
                if (!items.any((m) => m.value == valor)) {
                  items.add(
                      DropdownMenuItem(value: valor, child: Text(valor)));
                }
              }
              return _buildDropdown(
                context: context,
                key: ValueKey('tipoLocalidad-${widget.index}'),
                label: 'Tipo de lugar',
                value: valor,
                items: items,
                hint: 'Seleccione tipo',
                onChanged: (v) {
                  localidad.tipoLocalidad = v ?? '';
                  localidad.idTipoLocalidad = tipoLocalidadIdPorNombre(v);
                  widget.onChanged();
                },
              );
            },
          ),
          const SizedBox(height: 12),
          _campo(
            label: 'Nombre del lugar *',
            controller: _nombre,
            hint: 'Ej: Las Lomas, San Bernardo',
            textCapitalization: TextCapitalization.words,
            onChanged: (v) {
              localidad.nombre = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Impactos (marque los que aplican)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          _impactoCheck(localidad.impPoblacion, 'Población', (v) {
            localidad.impPoblacion = v;
            if (v && localidad.impactoPoblacion.isEmpty) {
              final rp = context.read<ReporteProvider>();
              localidad.impactoPoblacion.add(EdanImpactoPoblacion(
                gruposEtarios: EdanImpactoPoblacion.gruposDesdeCatalogo(
                    rp.gruposEtarios
                        .map((g) => {
                              'id_grupo_etario': g.idGrupoEtario,
                              'nombre': g.nombre,
                            })
                        .toList()),
              )..idSeccion = generarIdSeccion('im'));
            }
            widget.onChanged();
          }),
          if (localidad.impPoblacion && !localidad.impProteccion)
            const Padding(
              padding: EdgeInsets.only(left: 30, bottom: 4),
              child: Text(
                'Recuerde también marcar Protección para la sección 10',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          _impactoCheck(localidad.impSalud, 'Salud', (v) {
            localidad.impSalud = v;
            widget.onChanged();
          }),
          _impactoCheck(localidad.impInfraestructura, 'Infraestructura', (v) {
            localidad.impInfraestructura = v;
            widget.onChanged();
          }),
          _impactoCheck(localidad.impServicios, 'Servicios básicos', (v) {
            localidad.impServicios = v;
            widget.onChanged();
          }),
          _impactoCheck(localidad.impEducacion, 'Educación', (v) {
            localidad.impEducacion = v;
            widget.onChanged();
          }),
          _impactoCheck(localidad.impVivienda, 'Vivienda', (v) {
            localidad.impVivienda = v;
            widget.onChanged();
          }),
          _impactoCheck(localidad.impAgropecuario, 'Agropecuario', (v) {
            localidad.impAgropecuario = v;
            widget.onChanged();
          }),
          _impactoCheck(localidad.impProteccion, 'Protección', (v) {
            localidad.impProteccion = v;
            if (v && localidad.proteccion.isEmpty) {
              final catalogo = context.read<ReporteProvider>().gruposVulnerables;
              localidad.proteccion = EdanLocalidad.proteccionDesdeCatalogo(
                  catalogo.map((c) => {'id_grupo_vulnerable': c.idGrupoVulnerable, 'nombre': c.nombre}).toList());
            }
            widget.onChanged();
          }),
          _impactoCheck(localidad.impNecesidades, 'Necesidades humanitarias', (v) {
            localidad.impNecesidades = v;
            widget.onChanged();
          }),
        ],
      ),
    );
  }

  Widget _impactoCheck(
      bool value, String label, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
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
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BloqueLocalidad extends StatelessWidget {
  final int index;
  final String nombre;
  final List<Widget> children;

  const _BloqueLocalidad({
    super.key,
    required this.index,
    required this.nombre,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Lugar ${index + 1}${nombre.trim().isNotEmpty ? ' · ${nombre.trim()}' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _CajaTotales extends StatelessWidget {
  final List<(String, String)> valores;

  const _CajaTotales({required this.valores});

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Totales',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: valores.map((v) => _filaTotal(v.$1, v.$2)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _filaTotal(String label, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ---------- Filas repetibles ----------

class _CampoAutonomo extends StatefulWidget {
  final String label;
  final String valor;
  final int maxLines;
  final ValueChanged<String> onChanged;

  const _CampoAutonomo({
    required this.label,
    required this.valor,
    required this.onChanged,
    this.maxLines = 1,
  });

  @override
  State<_CampoAutonomo> createState() => _CampoAutonomoState();
}

class _CampoAutonomoState extends State<_CampoAutonomo> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valor);
  }

  @override
  void didUpdateWidget(covariant _CampoAutonomo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valor != oldWidget.valor && _controller.text != widget.valor) {
      _controller.text = widget.valor;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _campo(
      label: widget.label,
      controller: _controller,
      maxLines: widget.maxLines,
      onChanged: (v) => widget.onChanged(v),
    );
  }
}

class _NumCampoAutonomo extends StatefulWidget {
  final String label;
  final String valor;
  final ValueChanged<String> onChanged;

  const _NumCampoAutonomo({
    required this.label,
    required this.valor,
    required this.onChanged,
  });

  @override
  State<_NumCampoAutonomo> createState() => _NumCampoAutonomoState();
}

class _NumCampoAutonomoState extends State<_NumCampoAutonomo> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valor);
  }

  @override
  void didUpdateWidget(covariant _NumCampoAutonomo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valor != oldWidget.valor && _controller.text != widget.valor) {
      _controller.text = widget.valor;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _numCampo(
      label: widget.label,
      controller: _controller,
      onChanged: (v) => widget.onChanged(v),
    );
  }
}

class _FilaGrupoEtarioAutonomo extends StatelessWidget {
  final String titulo;
  final EdanGrupoEtario grupo;
  final VoidCallback onChanged;

  const _FilaGrupoEtarioAutonomo({
    required this.titulo,
    required this.grupo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _NumCampoAutonomo(
                    label: 'Fallecidos',
                    valor: grupo.fallecidos > 0 ? '${grupo.fallecidos}' : '',
                    onChanged: (v) {
                      grupo.fallecidos = int.tryParse(v.trim()) ?? 0;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NumCampoAutonomo(
                    label: 'Heridos',
                    valor: grupo.heridos > 0 ? '${grupo.heridos}' : '',
                    onChanged: (v) {
                      grupo.heridos = int.tryParse(v.trim()) ?? 0;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _NumCampoAutonomo(
              label: 'Desaparecidos',
              valor: grupo.desaparecidos > 0 ? '${grupo.desaparecidos}' : '',
              onChanged: (v) {
                grupo.desaparecidos = int.tryParse(v.trim()) ?? 0;
                onChanged();
              },
            ),
            const SizedBox(height: 10),
            _CampoAutonomo(
              label: 'Observaciones',
              valor: grupo.observaciones,
              maxLines: 2,
              onChanged: (v) {
                grupo.observaciones = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BloqueLocalidadNecesidades extends StatelessWidget {
  final int index;
  final String nombre;
  final EdanNecesidadHumanitaria necesidad;
  final VoidCallback onChanged;

  const _BloqueLocalidadNecesidades({
    super.key,
    required this.index,
    required this.nombre,
    required this.necesidad,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Lugar ${index + 1}${nombre.trim().isNotEmpty ? ' · ${nombre.trim()}' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _checkInline(
                value: necesidad.alimentos,
                label: 'Alimentos',
                onChanged: (v) {
                  necesidad.alimentos = v;
                  onChanged();
                },
              ),
              if (necesidad.alimentos)
                _CampoAutonomo(
                  label: 'Observaciones · Alimentos',
                  valor: necesidad.obsAlimentos,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsAlimentos = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.refugioVivienda,
                label: 'Refugio / vivienda',
                onChanged: (v) {
                  necesidad.refugioVivienda = v;
                  onChanged();
                },
              ),
              if (necesidad.refugioVivienda)
                _CampoAutonomo(
                  label: 'Observaciones · Refugio / vivienda',
                  valor: necesidad.obsRefugioVivienda,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsRefugioVivienda = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.ropaCama,
                label: 'Ropa de cama',
                onChanged: (v) {
                  necesidad.ropaCama = v;
                  onChanged();
                },
              ),
              if (necesidad.ropaCama)
                _CampoAutonomo(
                  label: 'Observaciones · Ropa de cama',
                  valor: necesidad.obsRopaCama,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsRopaCama = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.articulosHigiene,
                label: 'Artículos de higiene',
                onChanged: (v) {
                  necesidad.articulosHigiene = v;
                  onChanged();
                },
              ),
              if (necesidad.articulosHigiene)
                _CampoAutonomo(
                  label: 'Observaciones · Artículos de higiene',
                  valor: necesidad.obsArticulosHigiene,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsArticulosHigiene = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.articulosCocina,
                label: 'Artículos de cocina',
                onChanged: (v) {
                  necesidad.articulosCocina = v;
                  onChanged();
                },
              ),
              if (necesidad.articulosCocina)
                _CampoAutonomo(
                  label: 'Observaciones · Artículos de cocina',
                  valor: necesidad.obsArticulosCocina,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsArticulosCocina = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.prendasVestir,
                label: 'Prendas de vestir',
                onChanged: (v) {
                  necesidad.prendasVestir = v;
                  onChanged();
                },
              ),
              if (necesidad.prendasVestir)
                _CampoAutonomo(
                  label: 'Observaciones · Prendas de vestir',
                  valor: necesidad.obsPrendasVestir,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsPrendasVestir = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.herramientas,
                label: 'Herramientas',
                onChanged: (v) {
                  necesidad.herramientas = v;
                  onChanged();
                },
              ),
              if (necesidad.herramientas)
                _CampoAutonomo(
                  label: 'Observaciones · Herramientas',
                  valor: necesidad.obsHerramientas,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsHerramientas = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.almacenamientoAgua,
                label: 'Almacenamiento de agua',
                onChanged: (v) {
                  necesidad.almacenamientoAgua = v;
                  onChanged();
                },
              ),
              if (necesidad.almacenamientoAgua)
                _CampoAutonomo(
                  label: 'Observaciones · Almacenamiento de agua',
                  valor: necesidad.obsAlmacenamientoAgua,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsAlmacenamientoAgua = v;
                    onChanged();
                  },
                ),
              _checkInline(
                value: necesidad.banos,
                label: 'Baños',
                onChanged: (v) {
                  necesidad.banos = v;
                  onChanged();
                },
              ),
              if (necesidad.banos)
                _CampoAutonomo(
                  label: 'Observaciones · Baños',
                  valor: necesidad.obsBanos,
                  maxLines: 2,
                  onChanged: (v) {
                    necesidad.obsBanos = v;
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilaSaludRow extends StatefulWidget {
  final String titulo;
  final EdanEstablecimientoSalud valor;
  final String comunidadInicial;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaSaludRow({
    required this.titulo,
    required this.valor,
    required this.comunidadInicial,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaSaludRow> createState() => _FilaSaludRowState();
}

class _FilaSaludRowState extends State<_FilaSaludRow> {
  late final TextEditingController _nombre = TextEditingController(text: widget.valor.nombreEstablecimiento);
  late final TextEditingController _comunidad = TextEditingController(
      text: widget.valor.comunidad.isNotEmpty
          ? widget.valor.comunidad
          : widget.comunidadInicial);
  late final TextEditingController _medicos = TextEditingController(text: widget.valor.medicosAfectados > 0 ? '${widget.valor.medicosAfectados}' : '');
  late final TextEditingController _enfermeras = TextEditingController(text: widget.valor.enfermerasAfectados > 0 ? '${widget.valor.enfermerasAfectados}' : '');
  late final TextEditingController _otros = TextEditingController(text: widget.valor.otrosAfectados > 0 ? '${widget.valor.otrosAfectados}' : '');

  @override
  void dispose() {
    _nombre.dispose();
    _comunidad.dispose();
    _medicos.dispose();
    _enfermeras.dispose();
    _otros.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        _campo(
          label: 'Nombre del establecimiento',
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          autofocus: widget.autoFocus,
          onChanged: (v) {
            valor.nombreEstablecimiento = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Comunidad / localidad',
          controller: _comunidad,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) {
            valor.comunidad = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nivel de atención',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: valor.nivelAtencion.isEmpty ? null : valor.nivelAtencion,
              isExpanded: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: PaletteScope.of(context).primary, width: 2),
                ),
              ),
              items: _itemsConValor<String>(
                _nivelesAtencion
                    .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                valor.nivelAtencion.isEmpty ? null : valor.nivelAtencion,
              ),
              hint: const Text(
                'Seleccione nivel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onChanged: (v) {
                valor.nivelAtencion = v ?? '';
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _GrupoDeCampos(
          titulo: 'Tipo de daño',
          children: [
            _checkInline(
              value: valor.danoParcial,
              label: 'Daño parcial',
              onChanged: (v) {
                setState(() {
                  valor.danoParcial = v;
                  if (v) valor.danoTotal = false;
                });
                widget.onChanged();
              },
            ),
            _checkInline(
              value: valor.danoTotal,
              label: 'Daño total',
              onChanged: (v) {
                setState(() {
                  valor.danoTotal = v;
                  if (v) valor.danoParcial = false;
                });
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _GrupoDeCampos(
          titulo: 'Personal de salud afectado',
          children: [
            Row(
              children: [
                Expanded(
                  child: _numCampo(
                    label: 'Médicos afectados',
                    controller: _medicos,
                    onChanged: (v) {
                      valor.medicosAfectados = int.tryParse(v) ?? 0;
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numCampo(
                    label: 'Enfermeras',
                    controller: _enfermeras,
                    onChanged: (v) {
                      valor.enfermerasAfectados = int.tryParse(v) ?? 0;
                      widget.onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _numCampo(
              label: 'Otro personal afectado',
              controller: _otros,
              onChanged: (v) {
                valor.otrosAfectados = int.tryParse(v) ?? 0;
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Salud',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaVialRow extends StatefulWidget {
  final String titulo;
  final EdanDanoVial valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaVialRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaVialRow> createState() => _FilaVialRowState();
}

class _FilaVialRowState extends State<_FilaVialRow> {
  late final TextEditingController _tramo = TextEditingController(text: widget.valor.tramo);
  late final TextEditingController _km = TextEditingController(
      text: widget.valor.kmDanio > 0 ? '${widget.valor.kmDanio}' : '');
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);
  late final TextEditingController _obs = TextEditingController(text: widget.valor.observaciones);

  @override
  void dispose() {
    _tramo.dispose();
    _km.dispose();
    _necesidades.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    final esVia = valor.viaPuente.trim().toLowerCase() == 'vía' ||
        valor.viaPuente.trim().toLowerCase() == 'via';
    final esPuente = valor.viaPuente.trim().toLowerCase() == 'puente';
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        Row(
          children: [
            Expanded(
              child: _checkInline(
                value: esVia,
                label: 'Vía',
                onChanged: (v) {
                  if (!v) return;
                  setState(() => valor.viaPuente = 'Vía');
                  widget.onChanged();
                },
              ),
            ),
            Expanded(
              child: _checkInline(
                value: esPuente,
                label: 'Puente',
                onChanged: (v) {
                  if (!v) return;
                  setState(() => valor.viaPuente = 'Puente');
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Tramo / Tramo',
          controller: _tramo,
          autofocus: widget.autoFocus,
          onChanged: (v) {
            valor.tramo = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _checkInline(
          value: valor.danoParcial,
          label: 'Daño parcial',
          onChanged: (v) {
            setState(() {
              valor.danoParcial = v;
              if (v) valor.danoTotal = false;
            });
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            setState(() {
              valor.danoTotal = v;
              if (v) valor.danoParcial = false;
            });
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _numCampoDecimal(
          label: 'Km dañados',
          hint: '0.0',
          controller: _km,
          onChanged: (v) {
            valor.kmDanio = double.tryParse(v) ?? 0;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _campo(
          label: 'Necesidades inmediatas',
          controller: _necesidades,
          maxLines: 2,
          onChanged: (v) {
            valor.necesidadesInmediatas = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Observaciones',
          controller: _obs,
          maxLines: 2,
          onChanged: (v) {
            valor.observaciones = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Vías y puentes',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaServicioRow extends StatefulWidget {
  final String titulo;
  final EdanServicioBasicoDetalle valor;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaServicioRow({
    required this.titulo,
    required this.valor,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaServicioRow> createState() => _FilaServicioRowState();
}

class _FilaServicioRowState extends State<_FilaServicioRow> {
  late final TextEditingController _necesidades =
      TextEditingController(text: widget.valor.necesidadesInmediatas);
  late final TextEditingController _obs =
      TextEditingController(text: widget.valor.observaciones);

  @override
  void dispose() {
    _necesidades.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: false,
      onEliminar: () {},
      children: [
        _checkInline(
          value: valor.danoParcial,
          label: 'Daño parcial',
          onChanged: (v) {
            setState(() {
              valor.danoParcial = v;
              if (v) valor.danoTotal = false;
            });
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            setState(() {
              valor.danoTotal = v;
              if (v) valor.danoParcial = false;
            });
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _campo(
          label: 'Necesidades inmediatas',
          controller: _necesidades,
          maxLines: 2,
          autofocus: widget.autoFocus,
          onChanged: (v) {
            valor.necesidadesInmediatas = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Observaciones',
          controller: _obs,
          maxLines: 2,
          onChanged: (v) {
            valor.observaciones = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Servicios básicos',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaInfraRow extends StatefulWidget {
  final String titulo;
  final EdanDanoInfraPublica valor;
  final String comunidadInicial;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaInfraRow({
    required this.titulo,
    required this.valor,
    required this.comunidadInicial,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaInfraRow> createState() => _FilaInfraRowState();
}

class _FilaInfraRowState extends State<_FilaInfraRow> {
  late final TextEditingController _comunidad = TextEditingController(
      text: widget.valor.comunidad.isNotEmpty
          ? widget.valor.comunidad
          : widget.comunidadInicial);
  late final TextEditingController _tipo = TextEditingController(text: widget.valor.tipoEstructura);
  late final TextEditingController _obs = TextEditingController(text: widget.valor.observaciones);

  @override
  void dispose() {
    _comunidad.dispose();
    _tipo.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        _campo(
          label: 'Comunidad',
          controller: _comunidad,
          textCapitalization: TextCapitalization.words,
          autofocus: widget.autoFocus,
          onChanged: (v) {
            valor.comunidad = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Tipo de estructura',
          controller: _tipo,
          hint: 'Ej: Puente, Edificio, Mercado...',
          textCapitalization: TextCapitalization.words,
          onChanged: (v) {
            valor.tipoEstructura = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _checkInline(
          value: valor.danoParcial,
          label: 'Daño parcial',
          onChanged: (v) {
            setState(() {
              valor.danoParcial = v;
              if (v) valor.danoTotal = false;
            });
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            setState(() {
              valor.danoTotal = v;
              if (v) valor.danoParcial = false;
            });
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _campo(
          label: 'Observaciones',
          controller: _obs,
          maxLines: 2,
          onChanged: (v) {
            valor.observaciones = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Infraestructura pública',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaEduRow extends StatefulWidget {
  final String titulo;
  final EdanDanoUnidadEducativa valor;
  final String comunidadInicial;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaEduRow({
    required this.titulo,
    required this.valor,
    required this.comunidadInicial,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaEduRow> createState() => _FilaEduRowState();
}

class _FilaEduRowState extends State<_FilaEduRow> {
  late final TextEditingController _nombre = TextEditingController(text: widget.valor.nombreEstablecimiento);
  late final TextEditingController _comunidad = TextEditingController(
      text: widget.valor.comunidad.isNotEmpty
          ? widget.valor.comunidad
          : widget.comunidadInicial);
  late final TextEditingController _estudiantes = TextEditingController(
      text: widget.valor.estudiantes > 0 ? '${widget.valor.estudiantes}' : '');
  late final TextEditingController _profesores = TextEditingController(
      text: widget.valor.profesores > 0 ? '${widget.valor.profesores}' : '');
  late final TextEditingController _administrativos = TextEditingController(
      text: widget.valor.administrativos > 0
          ? '${widget.valor.administrativos}'
          : '');
  late final TextEditingController _total = TextEditingController(
      text: widget.valor.totalAfectados > 0
          ? '${widget.valor.totalAfectados}'
          : '');
  late final TextEditingController _obs =
      TextEditingController(text: widget.valor.observaciones);
  bool? _suspension;
  bool? _perdida;
  bool? _albergue;

  @override
  void initState() {
    super.initState();
    _suspension = widget.valor.suspensionClases;
    _perdida = widget.valor.perdidaMaterial;
    _albergue = widget.valor.funcionaAlbergue;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _comunidad.dispose();
    _estudiantes.dispose();
    _profesores.dispose();
    _administrativos.dispose();
    _total.dispose();
    _obs.dispose();
    super.dispose();
  }

  void _actTotal() {
    _total.text = widget.valor.totalAfectados > 0
        ? '${widget.valor.totalAfectados}'
        : '';
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        _subtitulo('7.1 · Daños en unidades educativas'),
        _campo(
          label: 'Nombre de la unidad educativa',
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          autofocus: widget.autoFocus,
          onChanged: (v) {
            valor.nombreEstablecimiento = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Comunidad / localidad',
          controller: _comunidad,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) {
            valor.comunidad = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _GrupoDeCampos(
          titulo: 'Tipo de daño',
          children: [
            _checkInline(
              value: valor.danoParcial,
              label: 'Daño parcial',
              onChanged: (v) {
                setState(() {
                  valor.danoParcial = v;
                  if (v) valor.danoTotal = false;
                });
                widget.onChanged();
              },
            ),
            _checkInline(
              value: valor.danoTotal,
              label: 'Daño total',
              onChanged: (v) {
                setState(() {
                  valor.danoTotal = v;
                  if (v) valor.danoParcial = false;
                });
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        _GrupoDeCampos(
          titulo: 'Suspensión de clases',
          children: [
            _siNoCheck(
              seleccionado: _suspension,
              onSeleccion: (v) {
                _suspension = v;
                valor.suspensionClases = v;
                setState(() {});
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        _GrupoDeCampos(
          titulo: 'Pérdida de material educativo',
          children: [
            _siNoCheck(
              seleccionado: _perdida,
              onSeleccion: (v) {
                _perdida = v;
                valor.perdidaMaterial = v;
                setState(() {});
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        _GrupoDeCampos(
          titulo: 'Funciona como albergue',
          children: [
            _siNoCheck(
              seleccionado: _albergue,
              onSeleccion: (v) {
                _albergue = v;
                valor.funcionaAlbergue = v;
                setState(() {});
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _subtitulo('7.2 · Afectación a alumnos, profesores y administrativos'),
        Row(
          children: [
            Expanded(
              child: _numCampo(
                label: 'Estudiantes',
                controller: _estudiantes,
                onChanged: (v) {
                  valor.estudiantes = int.tryParse(v) ?? 0;
                  _actTotal();
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numCampo(
                label: 'Profesores',
                controller: _profesores,
                onChanged: (v) {
                  valor.profesores = int.tryParse(v) ?? 0;
                  _actTotal();
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _numCampo(
                label: 'Administrativos',
                controller: _administrativos,
                onChanged: (v) {
                  valor.administrativos = int.tryParse(v) ?? 0;
                  _actTotal();
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numCampo(
                label: 'Total afectados',
                controller: _total,
                readOnly: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Observaciones',
          controller: _obs,
          maxLines: 2,
          onChanged: (v) {
            valor.observaciones = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Educación',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaViviendaRow extends StatefulWidget {
  final String titulo;
  final EdanDanoVivienda valor;
  final String comunidadInicial;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaViviendaRow({
    required this.titulo,
    required this.valor,
    required this.comunidadInicial,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaViviendaRow> createState() => _FilaViviendaRowState();
}

class _FilaViviendaRowState extends State<_FilaViviendaRow> {
  late final TextEditingController _comunidad = TextEditingController(
      text: widget.valor.comunidad.isNotEmpty
          ? widget.valor.comunidad
          : widget.comunidadInicial);
  bool? _tipo;
  late final TextEditingController _nro = TextEditingController();
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);
  late final TextEditingController _obs = TextEditingController(text: widget.valor.observaciones);

  @override
  void initState() {
    super.initState();
    if (widget.valor.danoParcial > 0) {
      _tipo = true;
      _nro.text = '${widget.valor.danoParcial}';
    } else if (widget.valor.danoTotal > 0) {
      _tipo = false;
      _nro.text = '${widget.valor.danoTotal}';
    }
  }

  @override
  void dispose() {
    _comunidad.dispose();
    _nro.dispose();
    _necesidades.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        _campo(
          label: 'Comunidad',
          controller: _comunidad,
          textCapitalization: TextCapitalization.words,
          autofocus: widget.autoFocus,
          onChanged: (v) {
            valor.comunidad = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _GrupoDeCampos(
          titulo: 'Tipo de daño',
          children: [
            _checkInline(
              value: _tipo == true,
              label: 'Daño parcial',
              onChanged: (v) {
                setState(() {
                  _tipo = v ? true : null;
                  valor.danoParcial = v ? (int.tryParse(_nro.text) ?? 0) : 0;
                  if (v) valor.danoTotal = 0;
                });
                widget.onChanged();
              },
            ),
            _checkInline(
              value: _tipo == false,
              label: 'Daño total',
              onChanged: (v) {
                setState(() {
                  _tipo = v ? false : null;
                  valor.danoTotal = v ? (int.tryParse(_nro.text) ?? 0) : 0;
                  if (v) valor.danoParcial = 0;
                });
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        _numCampo(
          label: 'Nº de viviendas',
          controller: _nro,
          onChanged: (v) {
            final n = int.tryParse(v) ?? 0;
            if (_tipo == true) {
              valor.danoParcial = n;
              valor.danoTotal = 0;
            } else if (_tipo == false) {
              valor.danoParcial = 0;
              valor.danoTotal = n;
            }
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Necesidades inmediatas',
          controller: _necesidades,
          maxLines: 2,
          onChanged: (v) {
            valor.necesidadesInmediatas = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Observaciones',
          controller: _obs,
          maxLines: 2,
          onChanged: (v) {
            valor.observaciones = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Viviendas',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaAgriculturaRow extends StatefulWidget {
  final String titulo;
  final EdanDanoAgricultura valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaAgriculturaRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaAgriculturaRow> createState() => _FilaAgriculturaRowState();
}

class _FilaAgriculturaRowState extends State<_FilaAgriculturaRow> {
  late final TextEditingController _afectadas = TextEditingController(text: widget.valor.hectareasAfectadas > 0 ? '${widget.valor.hectareasAfectadas}' : '');
  late final TextEditingController _perdidas = TextEditingController(text: widget.valor.hectareasPerdidas > 0 ? '${widget.valor.hectareasPerdidas}' : '');
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);
  late final TextEditingController _obs = TextEditingController(text: widget.valor.observaciones);

  @override
  void dispose() {
    _afectadas.dispose();
    _perdidas.dispose();
    _necesidades.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    final rp = context.watch<ReporteProvider>();
    final cultivos = rp.cultivos;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Tipo de cultivo',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: cultivos.any((c) => c.idCultivo == valor.idCultivo) ? valor.idCultivo : null,
              isExpanded: true,
              isDense: true,
              hint: const Text('Seleccione cultivo'),
              items: (cultivos.toList()..sort((a, b) => a.nombre.compareTo(b.nombre))).map((c) => DropdownMenuItem(
                value: c.idCultivo,
                child: Text(c.nombre),
              )).toList(),
              onChanged: (v) {
                if (v != null) {
                  final seleccion = cultivos.firstWhere((c) => c.idCultivo == v);
                  valor.idCultivo = v;
                  valor.tipoCultivo = seleccion.nombre;
                } else {
                  valor.idCultivo = null;
                  valor.tipoCultivo = '';
                }
                widget.onChanged();
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _numCampo(
                label: 'Has afectadas',
                controller: _afectadas,
                autofocus: widget.autoFocus,
                onChanged: (v) {
                  valor.hectareasAfectadas = int.tryParse(v) ?? 0;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numCampo(
                label: 'Has perdidas',
                controller: _perdidas,
                onChanged: (v) {
                  valor.hectareasPerdidas = int.tryParse(v) ?? 0;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Necesidades inmediatas',
          controller: _necesidades,
          maxLines: 2,
          onChanged: (v) {
            valor.necesidadesInmediatas = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Observaciones',
          controller: _obs,
          maxLines: 2,
          onChanged: (v) {
            valor.observaciones = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Agricultura',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaPecuarioRow extends StatefulWidget {
  final String titulo;
  final EdanDanoPecuario valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaPecuarioRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaPecuarioRow> createState() => _FilaPecuarioRowState();
}

class _FilaPecuarioRowState extends State<_FilaPecuarioRow> {
  late final TextEditingController _raza = TextEditingController(text: widget.valor.raza);
  late final TextEditingController _afectados = TextEditingController(text: widget.valor.animalesAfectados > 0 ? '${widget.valor.animalesAfectados}' : '');
  late final TextEditingController _muertos = TextEditingController(text: widget.valor.animalesMuertos > 0 ? '${widget.valor.animalesMuertos}' : '');
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);

  @override
  void dispose() {
    _raza.dispose();
    _afectados.dispose();
    _muertos.dispose();
    _necesidades.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    final rp = context.watch<ReporteProvider>();
    final grupos = rp.pecuarioGrupos;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Especie',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: grupos.any((g) => g.idPecuarioGrupo == valor.idEspecie) ? valor.idEspecie : null,
                    isExpanded: true,
                    isDense: true,
                    hint: const Text('Seleccione especie'),
                    items: (grupos.toList()..sort((a, b) => a.nombre.compareTo(b.nombre))).map((g) => DropdownMenuItem(
                      value: g.idPecuarioGrupo,
                      child: Text(g.nombre),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        final seleccion = grupos.firstWhere((g) => g.idPecuarioGrupo == v);
                        valor.idEspecie = v;
                        valor.especie = seleccion.nombre;
                      } else {
                        valor.idEspecie = null;
                        valor.especie = '';
                      }
                      widget.onChanged();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _campo(
                label: 'Raza',
                controller: _raza,
                textCapitalization: TextCapitalization.words,
                autofocus: widget.autoFocus,
                onChanged: (v) {
                  valor.raza = v;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _numCampo(
                label: 'Animales afectados',
                controller: _afectados,
                onChanged: (v) {
                  valor.animalesAfectados = int.tryParse(v) ?? 0;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numCampo(
                label: 'Animales muertos',
                controller: _muertos,
                onChanged: (v) {
                  valor.animalesMuertos = int.tryParse(v) ?? 0;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Necesidades inmediatas',
          controller: _necesidades,
          maxLines: 2,
          onChanged: (v) {
            valor.necesidadesInmediatas = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Pecuario',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaInfraProdRow extends StatefulWidget {
  final String titulo;
  final EdanInfraProductiva valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final bool autoFocus;

  const _FilaInfraProdRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
    this.autoFocus = false,
  });

  @override
  State<_FilaInfraProdRow> createState() => _FilaInfraProdRowState();
}

class _FilaInfraProdRowState extends State<_FilaInfraProdRow> {
  late final TextEditingController _tipo = TextEditingController(text: widget.valor.tipo);
  bool? _dano;
  late final TextEditingController _nro = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.valor.danoParcial > 0) {
      _dano = true;
      _nro.text = '${widget.valor.danoParcial}';
    } else if (widget.valor.danoTotal > 0) {
      _dano = false;
      _nro.text = '${widget.valor.danoTotal}';
    }
  }

  @override
  void dispose() {
    _tipo.dispose();
    _nro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: widget.puedeEliminar,
      onEliminar: widget.onEliminar,
      children: [
        _campo(
          label: 'Tipo de infraestructura',
          controller: _tipo,
          hint: 'Ej: Sistema riego, Silo, Camino...',
          textCapitalization: TextCapitalization.words,
          autofocus: widget.autoFocus,
          onChanged: (v) {
            valor.tipo = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _GrupoDeCampos(
          titulo: 'Tipo de daño',
          children: [
            _checkInline(
              value: _dano == true,
              label: 'Daño parcial',
              onChanged: (v) {
                setState(() {
                  _dano = v ? true : null;
                  valor.danoParcial = v ? (int.tryParse(_nro.text) ?? 0) : 0;
                  if (v) valor.danoTotal = 0;
                });
                widget.onChanged();
              },
            ),
            _checkInline(
              value: _dano == false,
              label: 'Daño total',
              onChanged: (v) {
                setState(() {
                  _dano = v ? false : null;
                  valor.danoTotal = v ? (int.tryParse(_nro.text) ?? 0) : 0;
                  if (v) valor.danoParcial = 0;
                });
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        _numCampo(
          label: 'Nº de infraestructuras afectadas',
          controller: _nro,
          onChanged: (v) {
            final n = int.tryParse(v) ?? 0;
            if (_dano == true) {
              valor.danoParcial = n;
              valor.danoTotal = 0;
            } else if (_dano == false) {
              valor.danoParcial = 0;
              valor.danoTotal = n;
            }
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BotonSacarFoto(
          fotos: valor.fotos,
          onChanged: widget.onChanged,
          fotografia: valor.fotografia,
          coordenadaLat: valor.coordenadaLat,
          coordenadaLon: valor.coordenadaLon,
          seccion: 'Infraestructura productiva',
          onCoordenadasCapturadas: (lat, lon) {
            valor.coordenadaLat = lat;
            valor.coordenadaLon = lon;
          },
        ),
      ],
    );
  }
}

class _FilaProteccionRow extends StatefulWidget {
  final String titulo;
  final EdanGrupoVulnerable valor;
  final VoidCallback onChanged;
  final bool soloMujeres;
  final bool autoFocus;

  const _FilaProteccionRow({
    required this.titulo,
    required this.valor,
    required this.onChanged,
    this.soloMujeres = false,
    this.autoFocus = false,
  });

  @override
  State<_FilaProteccionRow> createState() => _FilaProteccionRowState();
}

class _FilaProteccionRowState extends State<_FilaProteccionRow> {
  late final TextEditingController _mujeres = TextEditingController(
      text: widget.valor.mujeres > 0 ? '${widget.valor.mujeres}' : '');
  late final TextEditingController _hombres = TextEditingController(
      text: widget.valor.hombres > 0 ? '${widget.valor.hombres}' : '');
  late final TextEditingController _total = TextEditingController(
      text: widget.valor.total > 0 ? '${widget.valor.total}' : '');
  late final TextEditingController _obs =
      TextEditingController(text: widget.valor.observaciones);
  bool? _apoyo;
  bool? _repos;

  @override
  void initState() {
    super.initState();
    _apoyo = widget.valor.apoyoPsicologico;
    _repos = widget.valor.reposicionDocumentos;
  }

  @override
  void dispose() {
    _mujeres.dispose();
    _hombres.dispose();
    _total.dispose();
    _obs.dispose();
    super.dispose();
  }

  void _actTotal() {
    _total.text = widget.valor.total > 0 ? '${widget.valor.total}' : '';
  }

  @override
  Widget build(BuildContext context) {
    final valor = widget.valor;
    return _RowCard(
      titulo: widget.titulo,
      puedeEliminar: false,
      onEliminar: () {},
      children: [
        Row(
          children: [
            Expanded(
              child: _numCampo(
                label: 'Nº mujeres',
                controller: _mujeres,
                autofocus: widget.autoFocus,
                onChanged: (v) {
                  valor.mujeres = int.tryParse(v) ?? 0;
                  _actTotal();
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            if (!widget.soloMujeres)
              Expanded(
                child: _numCampo(
                  label: 'Nº hombres',
                  controller: _hombres,
                  onChanged: (v) {
                    valor.hombres = int.tryParse(v) ?? 0;
                    _actTotal();
                    widget.onChanged();
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _numCampo(
          label: 'Total',
          controller: _total,
          readOnly: true,
          onChanged: (_) {},
        ),
        const SizedBox(height: 12),
        _GrupoDeCampos(
          titulo: 'Apoyo psicológico',
          children: [
            _siNoCheck(
              seleccionado: _apoyo,
              onSeleccion: (v) {
                _apoyo = v;
                valor.apoyoPsicologico = v;
                setState(() {});
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _GrupoDeCampos(
          titulo: 'Reposición de documento de identidad',
          children: [
            _siNoCheck(
              seleccionado: _repos,
              onSeleccion: (v) {
                _repos = v;
                valor.reposicionDocumentos = v;
                setState(() {});
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Observaciones',
          controller: _obs,
          maxLines: 2,
          onChanged: (v) {
            valor.observaciones = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }
}
