import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../models/usuario.dart';
import '../../../providers/reporte_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/custom_text_field.dart';
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

class UgrEdanFormScreen extends StatefulWidget {
  final int? siguienteNumero;

  const UgrEdanFormScreen({super.key, this.siguienteNumero});

  @override
  State<UgrEdanFormScreen> createState() => _UgrEdanFormScreenState();
}

class _UgrEdanFormScreenState extends State<UgrEdanFormScreen> {
  final _edan = Edan.empty();
  final Set<String> _expandidas = {'01'};

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

  // 02 · Población
  final _poblacionController = TextEditingController();
  final _familiasAfectadasController = TextEditingController();
  final _familiasDamnificadasController = TextEditingController();

  // 11 · Necesidades humanitarias
  final _obsHumanitariaController = TextEditingController();

  // 13 · Responsable
  final _respNombreController = TextEditingController();
  final _respCargoController = TextEditingController();
  final _respFonoController = TextEditingController();
  final _respCorreoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fechaLlenadoController.text = _fmtFecha(_fechaLlenado);
    _fechaEventoController.text = _fmtFecha(_fechaEvento);
    final now = TimeOfDay.now();
    _hora12 = ((now.hour % 12 == 0 ? 12 : now.hour % 12)).toString().padLeft(2, '0');
    _ampm = now.hour >= 12 ? 'PM' : 'AM';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final token = AuthService.instance.currentToken;
      if (token?.idMunicipio != null && token?.idProvincia != null && token?.idDepartamento != null) {
        context.read<ReporteProvider>().loadMunicipios(token!.idProvincia!, token.idDepartamento!);
      }
      try {
        final usuarios = await ApiService.instance.getUsuarios();
        if (mounted) setState(() => _usuarios = usuarios);
      } catch (_) {}
    });
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
    _obsHumanitariaController.dispose();
    _respNombreController.dispose();
    _respCargoController.dispose();
    _respFonoController.dispose();
    _respCorreoController.dispose();
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

  bool get _s01Completada =>
      _idDepartamento != null &&
      _idProvincia != null &&
      _idMunicipio != null &&
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
      _idTipoEvento != null &&
      _locConPoblacion
          .any((l) => l.impactoPoblacion.tieneDatosGlobales);

  bool get _s04Completada =>
      _locConSalud.any((l) =>
          l.establecimientosSalud.any((s) => s.nombreEstablecimiento.trim().isNotEmpty) ||
          l.necesidadSalud.botiquines ||
          l.necesidadSalud.atencionInmediata > 0);

  bool get _s05Completada =>
      _locConInfraestructura.any((l) =>
          l.danosViales.any((d) => d.viaPuente.trim().isNotEmpty) ||
          l.danosInfraPublica.any((d) => d.tipoEstructura.trim().isNotEmpty));

  bool get _s06Completada =>
      _locConServicios.any((l) => l.serviciosBasicos.algunaSeleccionada);

  bool get _s07Completada =>
      _locConEducacion.any((l) =>
          l.unidadesEducativas.any((u) => u.nombreEstablecimiento.trim().isNotEmpty) ||
          l.afectacionEducativa.totalAfectados > 0);

  bool get _s08Completada =>
      _locConVivienda.any((l) => l.danosVivienda.any((v) => v.danoParcial > 0 || v.danoTotal > 0));

  bool get _s09Completada =>
      _locConAgropecuario.any((l) =>
          l.danosAgricultura.any((a) => a.tipoCultivo.trim().isNotEmpty) ||
          l.danosPecuarios.any((p) => p.especie.trim().isNotEmpty) ||
          l.infraProductiva.any((i) => i.tipo.trim().isNotEmpty));

  bool get _s10Completada =>
      _locConProteccion.any((l) =>
          l.proteccion.vulnerables.algunoPositivo ||
          l.proteccion.mujeres > 0 ||
          l.proteccion.hombres > 0);

  bool get _s11Completada => _edan.necesidadHumanitaria.algunaSeleccionada;

  bool get _s13Completada =>
      _respNombreController.text.trim().isNotEmpty &&
      _respCargoController.text.trim().isNotEmpty;

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

  void _eliminarLocalidad(int index) {
    if (_edan.localidades.length <= 1) return;
    setState(() => _edan.localidades.removeAt(index));
  }

  bool _validar() {
    final faltantes = <String>[];
    if (_idTipoEvento == null) faltantes.add('03');
    if (_nombreAlcaldeController.text.trim().isEmpty) faltantes.add('01');
    if (_fonoAlcaldeController.text.trim().isEmpty) faltantes.add('01');
    if (_idDepartamento == null || _idProvincia == null || _idMunicipio == null) {
      faltantes.add('01');
    }
    if (!_edan.localidades.any((l) => l.nombre.trim().isNotEmpty)) {
      faltantes.add('01');
    }
    if (_respNombreController.text.trim().isEmpty) faltantes.add('13');
    if (_respCargoController.text.trim().isEmpty) faltantes.add('13');
    if (faltantes.isNotEmpty) {
      setState(() => _expandidas.addAll(faltantes));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete los campos obligatorios antes de revisar el EDAN.'),
        ),
      );
      return false;
    }
    return true;
  }

  Edan _construirEdan() {
    final anio = DateTime.now().year;
    _edan.codigoEdan =
        'EDAN-$anio-${(widget.siguienteNumero ?? 1).toString().padLeft(3, '0')}';
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
    _edan.necesidadHumanitaria.observaciones = _obsHumanitariaController.text.trim();
    return _edan;
  }

  Future<void> _revisar() async {
    if (!_validar()) return;
    final edan = _construirEdan();
    final confirmado = await Navigator.of(context).push<Edan>(
      MaterialPageRoute(
        builder: (_) => UgrEdanPreviewScreen(edan: edan),
      ),
    );
    if (confirmado != null && mounted) {
      Navigator.of(context).pop(confirmado);
    }
  }

  void _toggle(String num) {
    setState(() {
      if (!_expandidas.add(num)) _expandidas.remove(num);
    });
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
        child: SingleChildScrollView(
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
      ),
      bottomNavigationBar: _buildActionsBar(),
    );
  }

  Widget _buildHeader(Color primary) {
    final anio = DateTime.now().year;
    final rp = context.read<ReporteProvider>();
    final userIdMunicipio = AuthService.instance.currentToken?.idMunicipio;
    final municipio = userIdMunicipio != null
        ? rp.municipios.where((m) => m.id == userIdMunicipio).firstOrNull
        : null;
    final codigoIne = municipio?.codigoIne ?? '---';
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
            'N° $codigoIne/$anio/${widget.siguienteNumero ?? 1}',
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
      numero: '01',
      titulo: 'Datos Generales',
      descripcion: 'Ubicación, localidad, responsable y fechas',
      completada: _s01Completada,
      expanded: _expandidas.contains('01'),
      onToggle: () => _toggle('01'),
      children: [
        _subtitulo('Ubicación'),
        _buildUbicacion(),
        const SizedBox(height: 16),
        _subtitulo('Localidades afectadas'),
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
              'Agregue al menos una localidad afectada.',
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
          label: 'Agregar localidad',
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
            ? catalogo.map((t) => t.nombre).toList()
            : _tiposEvento;
        return _buildDropdown<String>(
          context: context,
          key: ValueKey('tipoEvento-$_tipoEventoNombre'),
          label: 'Tipo de evento adverso *',
          value: _tipoEventoNombre.isEmpty ? null : _tipoEventoNombre,
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
    return _buildDropdown<int>(
      context: context,
      key: ValueKey('usuarioAlcalde-$_idUsuarioAlcalde'),
      label: 'Usuario alcalde *',
      value: _idUsuarioAlcalde,
      items: _usuarios
          .map((u) => DropdownMenuItem(
                value: u.idUsuario,
                child: Text(u.nombre, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      hint: _usuarios.isEmpty ? 'Cargando usuarios...' : 'Seleccione usuario',
      onChanged: (v) {
        setState(() => _idUsuarioAlcalde = v);
        if (v != null) {
          final user = _usuarios.where((u) => u.idUsuario == v).firstOrNull;
          if (user != null) {
            _nombreAlcaldeController.text = user.nombre;
            _fonoAlcaldeController.text = user.celular ?? '';
          }
        }
      },
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
                items: List.generate(12, (i) {
                  final v = (i + 1).toString().padLeft(2, '0');
                  return DropdownMenuItem(value: v, child: Text('$v:00'));
                }),
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
              items: rp.departamentos
                  .map((d) => DropdownMenuItem(value: d.id, child: Text(d.nombre)))
                  .toList(),
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
                items: rp.provincias
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                    .toList(),
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
                items: rp.municipios
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.nombre)))
                    .toList(),
                hint: 'Seleccione municipio',
                onChanged: (v) => setState(() => _idMunicipio = v),
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

  // ---------- 02 Población ----------

  Widget _seccion02() {
    return _SeccionEdan(
      numero: '02',
      titulo: 'Información de Población Afectada y Damnificada',
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

    final totalF = locs.fold<int>(0, (acc, l) => acc + l.impactoPoblacion.fallecidos);
    final totalH = locs.fold<int>(0, (acc, l) => acc + l.impactoPoblacion.heridos);
    final totalD = locs.fold<int>(0, (acc, l) => acc + l.impactoPoblacion.desaparecidos);

    return _SeccionEdan(
      numero: '03',
      titulo: 'Información del Municipio Afectado',
      descripcion: 'Impacto en la población y necesidades de primera respuesta',
      completada: _s03Completada,
      expanded: _expandidas.contains('03'),
      onToggle: () => _toggle('03'),
      children: [
        _subtitulo('3.1 Tipo de evento'),
        _buildTipoEvento(),
        const SizedBox(height: 8),
        _subtitulo('3.2 Impacto en la población por grupo etario'),
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          return _BloqueLocalidad(
            key: ValueKey('s03-imp-$i'),
            index: i,
            nombre: l.nombre,
            children: [
              ...l.impactoPoblacion.gruposEtarios.asMap().entries.map((ge) {
                return _FilaGrupoEtarioAutonomo(
                  titulo: ge.value.rango,
                  grupo: ge.value,
                  onChanged: () {
                    _sincronizarImpacto(l);
                    setState(() {});
                  },
                );
              }),
              const SizedBox(height: 4),
              _CampoAutonomo(
                label: 'Observaciones',
                valor: l.impactoPoblacion.observaciones,
                maxLines: 2,
                onChanged: (v) {
                  l.impactoPoblacion.observaciones = v;
                  setState(() {});
                },
              ),
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
            nombre: l.nombre,
            children: [
              _checkInline(
                value: l.necesidadPrimeraRespuesta.busqueda,
                label: 'Búsqueda y rescate',
                onChanged: (v) => setState(
                    () => l.necesidadPrimeraRespuesta.busqueda = v),
              ),
              _checkInline(
                value: l.necesidadPrimeraRespuesta.salvamento,
                label: 'Salvamento',
                onChanged: (v) => setState(
                    () => l.necesidadPrimeraRespuesta.salvamento = v),
              ),
              _checkInline(
                value: l.necesidadPrimeraRespuesta.evacuacion,
                label: 'Evacuación',
                onChanged: (v) => setState(
                    () => l.necesidadPrimeraRespuesta.evacuacion = v),
              ),
              const SizedBox(height: 8),
              _CampoAutonomo(
                label: 'Observaciones',
                valor: l.necesidadPrimeraRespuesta.observaciones,
                maxLines: 2,
                onChanged: (v) {
                  l.necesidadPrimeraRespuesta.observaciones = v;
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
    final ip = l.impactoPoblacion;
    ip.fallecidos =
        ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.fallecidos);
    ip.heridos = ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.heridos);
    ip.desaparecidos =
        ip.gruposEtarios.fold<int>(0, (acc, g) => acc + g.desaparecidos);
    ip.grupoEtario = 'Total';
  }

  // ---------- 04 Salud ----------

  Widget _seccion04() {
    final locs = _locConSalud;
    if (locs.isEmpty) return const SizedBox.shrink();

    return _SeccionEdan(
      numero: '04',
      titulo: 'Salud',
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
            nombre: l.nombre,
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
                    puedeEliminar: l.establecimientosSalud.length > 1,
                    onEliminar: () => setState(
                        () => l.establecimientosSalud.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar establecimiento',
                onPressed: () => setState(
                    () => l.establecimientosSalud.add(EdanEstablecimientoSalud())),
              ),
              const SizedBox(height: 12),
              _subtitulo('4.2 Necesidades en salud'),
              _checkInline(
                value: l.necesidadSalud.botiquines,
                label: 'Botiquines',
                onChanged: (v) =>
                    setState(() => l.necesidadSalud.botiquines = v),
              ),
              const SizedBox(height: 8),
              _NumCampoAutonomo(
                label: 'Atenciones inmediatas requeridas',
                valor: l.necesidadSalud.atencionInmediata > 0
                    ? '${l.necesidadSalud.atencionInmediata}'
                    : '',
                onChanged: (v) {
                  l.necesidadSalud.atencionInmediata = int.tryParse(v.trim()) ?? 0;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _CampoAutonomo(
                label: 'Otras necesidades',
                valor: l.necesidadSalud.otrasNecesidades,
                maxLines: 2,
                onChanged: (v) {
                  l.necesidadSalud.otrasNecesidades = v;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _CampoAutonomo(
                label: 'Observaciones',
                valor: l.necesidadSalud.observaciones,
                maxLines: 2,
                onChanged: (v) {
                  l.necesidadSalud.observaciones = v;
                  setState(() {});
                },
              ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Establecimientos',
            '${locs.fold<int>(0, (a, l) => a + l.establecimientosSalud.length)}'
          ),
          (
            'Atenciones inmediatas',
            '${locs.fold<int>(0, (a, l) => a + l.necesidadSalud.atencionInmediata)}'
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
      numero: '05',
      titulo: 'Impacto en Infraestructuras',
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
            nombre: l.nombre,
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
                    onEliminar: () =>
                        setState(() => l.danosViales.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar vía / puente',
                onPressed: () =>
                    setState(() => l.danosViales.add(EdanDanoVial())),
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
                    puedeEliminar: l.danosInfraPublica.length > 1,
                    onEliminar: () =>
                        setState(() => l.danosInfraPublica.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar estructura',
                onPressed: () => setState(
                    () => l.danosInfraPublica.add(EdanDanoInfraPublica())),
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
      numero: '06',
      titulo: 'Impacto en Servicios Básicos',
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
            nombre: l.nombre,
            children: [
              _subtitulo('6.1 Servicios afectados'),
              _checkInline(
                value: l.serviciosBasicos.luzElectrica,
                label: 'Energía eléctrica',
                onChanged: (v) =>
                    setState(() => l.serviciosBasicos.luzElectrica = v),
              ),
              _checkInline(
                value: l.serviciosBasicos.aguaPotable,
                label: 'Agua potable',
                onChanged: (v) =>
                    setState(() => l.serviciosBasicos.aguaPotable = v),
              ),
              _checkInline(
                value: l.serviciosBasicos.alcantarillado,
                label: 'Alcantarillado',
                onChanged: (v) =>
                    setState(() => l.serviciosBasicos.alcantarillado = v),
              ),
              _checkInline(
                value: l.serviciosBasicos.gasDomiciliario,
                label: 'Gas domiciliario',
                onChanged: (v) =>
                    setState(() => l.serviciosBasicos.gasDomiciliario = v),
              ),
              _checkInline(
                value: l.serviciosBasicos.telecomunicaciones,
                label: 'Telecomunicaciones',
                onChanged: (v) => setState(
                    () => l.serviciosBasicos.telecomunicaciones = v),
              ),
              const SizedBox(height: 12),
              _subtitulo('6.2 Tipo de daño'),
              _checkInline(
                value: l.serviciosBasicos.danoParcial,
                label: 'Daño parcial',
                onChanged: (v) =>
                    setState(() => l.serviciosBasicos.danoParcial = v),
              ),
              _checkInline(
                value: l.serviciosBasicos.danoTotal,
                label: 'Daño total',
                onChanged: (v) =>
                    setState(() => l.serviciosBasicos.danoTotal = v),
              ),
              const SizedBox(height: 12),
              _CampoAutonomo(
                label: 'Necesidades inmediatas',
                valor: l.serviciosBasicos.necesidadesInmediatas,
                maxLines: 2,
                onChanged: (v) {
                  l.serviciosBasicos.necesidadesInmediatas = v;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _CampoAutonomo(
                label: 'Observaciones',
                valor: l.serviciosBasicos.observaciones,
                maxLines: 2,
                onChanged: (v) {
                  l.serviciosBasicos.observaciones = v;
                  setState(() {});
                },
              ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Localidades',
            '${locs.fold<int>(0, (a, l) => a + (l.serviciosBasicos.algunaSeleccionada ? 1 : 0))}'
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
      numero: '07',
      titulo: 'Impacto en Educación',
      descripcion: 'Unidades educativas y afectación de personal',
      completada: _s07Completada,
      expanded: _expandidas.contains('07'),
      onToggle: () => _toggle('07'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          final ae = l.afectacionEducativa;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.nombre,
            children: [
              _subtitulo('7.1 Daños en unidades educativas'),
              ...List.generate(l.unidadesEducativas.length, (j) {
                final valor = l.unidadesEducativas[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaEduRow(
                    titulo: 'Unidad educativa ${j + 1}',
                    valor: valor,
                    puedeEliminar: l.unidadesEducativas.length > 1,
                    onEliminar: () =>
                        setState(() => l.unidadesEducativas.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar unidad educativa',
                onPressed: () => setState(
                    () => l.unidadesEducativas.add(EdanDanoUnidadEducativa())),
              ),
              const SizedBox(height: 12),
              _subtitulo('7.2 Afectación a alumnos, profesores y administrativos'),
              Row(
                children: [
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Estudiantes',
                      valor: ae.estudiantes > 0 ? '${ae.estudiantes}' : '',
                      onChanged: (v) {
                        ae.estudiantes = int.tryParse(v.trim()) ?? 0;
                        ae.totalAfectados = ae.estudiantes +
                            ae.profesores +
                            ae.administrativos;
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Profesores',
                      valor: ae.profesores > 0 ? '${ae.profesores}' : '',
                      onChanged: (v) {
                        ae.profesores = int.tryParse(v.trim()) ?? 0;
                        ae.totalAfectados = ae.estudiantes +
                            ae.profesores +
                            ae.administrativos;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Administrativos',
                      valor: ae.administrativos > 0 ? '${ae.administrativos}' : '',
                      onChanged: (v) {
                        ae.administrativos = int.tryParse(v.trim()) ?? 0;
                        ae.totalAfectados = ae.estudiantes +
                            ae.profesores +
                            ae.administrativos;
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Total afectados',
                      valor: ae.totalAfectados > 0 ? '${ae.totalAfectados}' : '',
                      onChanged: (v) {
                        ae.totalAfectados = int.tryParse(v.trim()) ?? 0;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CampoAutonomo(
                label: 'Observaciones',
                valor: ae.observaciones,
                maxLines: 2,
                onChanged: (v) {
                  ae.observaciones = v;
                  setState(() {});
                },
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
            '${locs.fold<int>(0, (a, l) => a + l.afectacionEducativa.estudiantes)}'
          ),
          (
            'Profesores',
            '${locs.fold<int>(0, (a, l) => a + l.afectacionEducativa.profesores)}'
          ),
          (
            'Administrativos',
            '${locs.fold<int>(0, (a, l) => a + l.afectacionEducativa.administrativos)}'
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
      numero: '08',
      titulo: 'Impacto en Vivienda',
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
            nombre: l.nombre,
            children: [
              ...List.generate(l.danosVivienda.length, (j) {
                final valor = l.danosVivienda[j];
                return Padding(
                  key: ObjectKey(valor),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaViviendaRow(
                    titulo: 'Vivienda ${j + 1}',
                    valor: valor,
                    puedeEliminar: l.danosVivienda.length > 1,
                    onEliminar: () =>
                        setState(() => l.danosVivienda.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar vivienda',
                onPressed: () =>
                    setState(() => l.danosVivienda.add(EdanDanoVivienda())),
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
      numero: '09',
      titulo: 'Impacto Agropecuario',
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
            nombre: l.nombre,
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
                    onEliminar: () =>
                        setState(() => l.danosAgricultura.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar cultivo',
                onPressed: () => setState(
                    () => l.danosAgricultura.add(EdanDanoAgricultura())),
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
                    onEliminar: () =>
                        setState(() => l.danosPecuarios.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar especie',
                onPressed: () =>
                    setState(() => l.danosPecuarios.add(EdanDanoPecuario())),
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
                    onEliminar: () =>
                        setState(() => l.infraProductiva.removeAt(j)),
                    onChanged: () => setState(() {}),
                  ),
                );
              }),
              _AgregarBoton(
                label: 'Agregar infraestructura',
                onPressed: () => setState(
                    () => l.infraProductiva.add(EdanInfraProductiva())),
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

    return _SeccionEdan(
      numero: '10',
      titulo: 'Impacto en Protección',
      descripcion: 'Población vulnerable y afectación por sexo',
      completada: _s10Completada,
      expanded: _expandidas.contains('10'),
      onToggle: () => _toggle('10'),
      children: [
        ...locs.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          final p = l.proteccion;
          final v = p.vulnerables;
          return _BloqueLocalidad(
            key: ObjectKey(l),
            index: i,
            nombre: l.nombre,
            children: [
              _subtitulo('10.1 Población en situación de mayor vulnerabilidad'),
              _NumCampoAutonomo(
                label: 'Niñas y niños',
                valor: v.ninos > 0 ? '${v.ninos}' : '',
                onChanged: (val) {
                  v.ninos = int.tryParse(val.trim()) ?? 0;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _NumCampoAutonomo(
                label: 'Adolescentes',
                valor: v.adolescentes > 0 ? '${v.adolescentes}' : '',
                onChanged: (val) {
                  v.adolescentes = int.tryParse(val.trim()) ?? 0;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Mujeres lactantes',
                      valor: v.mujeresLactantes > 0
                          ? '${v.mujeresLactantes}'
                          : '',
                      onChanged: (val) {
                        v.mujeresLactantes = int.tryParse(val.trim()) ?? 0;
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Embarazadas',
                      valor: v.mujeresEmbarazadas > 0
                          ? '${v.mujeresEmbarazadas}'
                          : '',
                      onChanged: (val) {
                        v.mujeresEmbarazadas = int.tryParse(val.trim()) ?? 0;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Adultos mayores',
                      valor: v.adultosMayores > 0 ? '${v.adultosMayores}' : '',
                      onChanged: (val) {
                        v.adultosMayores = int.tryParse(val.trim()) ?? 0;
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Discapacidad',
                      valor: v.personasDiscapacidad > 0
                          ? '${v.personasDiscapacidad}'
                          : '',
                      onChanged: (val) {
                        v.personasDiscapacidad = int.tryParse(val.trim()) ?? 0;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _NumCampoAutonomo(
                label: 'Personas con enfermedad crónica',
                valor: v.personasEnfermedad > 0 ? '${v.personasEnfermedad}' : '',
                onChanged: (val) {
                  v.personasEnfermedad = int.tryParse(val.trim()) ?? 0;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _subtitulo('10.2 Afectación por sexo'),
              Row(
                children: [
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Mujeres',
                      valor: p.mujeres > 0 ? '${p.mujeres}' : '',
                      onChanged: (val) {
                        p.mujeres = int.tryParse(val.trim()) ?? 0;
                        p.total = p.mujeres + p.hombres;
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumCampoAutonomo(
                      label: 'Hombres',
                      valor: p.hombres > 0 ? '${p.hombres}' : '',
                      onChanged: (val) {
                        p.hombres = int.tryParse(val.trim()) ?? 0;
                        p.total = p.mujeres + p.hombres;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _NumCampoAutonomo(
                label: 'Total',
                valor: p.total > 0 ? '${p.total}' : '',
                readOnly: true,
                onChanged: (_) {},
              ),
              const SizedBox(height: 12),
              _subtitulo('10.3 Necesidades de protección'),
              _CampoAutonomo(
                label: 'Necesidades de protección',
                valor: p.necesidades,
                maxLines: 2,
                onChanged: (val) {
                  p.necesidades = val;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _CampoAutonomo(
                label: 'Apoyo psicosocial',
                valor: p.apoyoPsicosocial,
                maxLines: 2,
                onChanged: (val) {
                  p.apoyoPsicosocial = val;
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              _checkInline(
                value: p.reposicionDocumentos,
                label: 'Reposición de documentos',
                onChanged: (v) =>
                    setState(() => p.reposicionDocumentos = v),
              ),
              const SizedBox(height: 12),
              _CampoAutonomo(
                label: 'Observaciones',
                valor: p.observaciones,
                maxLines: 2,
                onChanged: (val) {
                  p.observaciones = val;
                  setState(() {});
                },
              ),
            ],
          );
        }),
        _CajaTotales(valores: [
          (
            'Vulnerables',
            '${locs.fold<int>(0, (a, l) => a + (l.proteccion.vulnerables.algunoPositivo ? 1 : 0))}'
          ),
          (
            'Mujeres',
            '${locs.fold<int>(0, (a, l) => a + l.proteccion.mujeres)}'
          ),
          (
            'Hombres',
            '${locs.fold<int>(0, (a, l) => a + l.proteccion.hombres)}'
          ),
        ]),
      ],
    );
  }

  // ---------- 11 Necesidades humanitarias ----------

  Widget _seccion11() {
    return _SeccionEdan(
      numero: '11',
      titulo: 'Necesidades Humanitarias',
      descripcion: 'Alimentos, refugio, higiene y otros',
      completada: _s11Completada,
      expanded: _expandidas.contains('11'),
      onToggle: () => _toggle('11'),
      children: [
        _checkInline(
          value: _edan.necesidadHumanitaria.alimentos,
          label: 'Alimentos',
          onChanged: (v) =>
              setState(() => _edan.necesidadHumanitaria.alimentos = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.refugioVivienda,
          label: 'Refugio / vivienda',
          onChanged: (v) =>
              setState(() => _edan.necesidadHumanitaria.refugioVivienda = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.ropaCama,
          label: 'Ropa de cama',
          onChanged: (v) =>
              setState(() => _edan.necesidadHumanitaria.ropaCama = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.articulosHigiene,
          label: 'Artículos de higiene',
          onChanged: (v) =>
              setState(() => _edan.necesidadHumanitaria.articulosHigiene = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.articulosCocina,
          label: 'Artículos de cocina',
          onChanged: (v) =>
              setState(() => _edan.necesidadHumanitaria.articulosCocina = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.prendasVestir,
          label: 'Prendas de vestir',
          onChanged: (v) =>
              setState(() => _edan.necesidadHumanitaria.prendasVestir = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.herramientas,
          label: 'Herramientas',
          onChanged: (v) =>
              setState(() => _edan.necesidadHumanitaria.herramientas = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.almacenamientoAgua,
          label: 'Almacenamiento de agua',
          onChanged: (v) => setState(
              () => _edan.necesidadHumanitaria.almacenamientoAgua = v),
        ),
        _checkInline(
          value: _edan.necesidadHumanitaria.banos,
          label: 'Baños',
          onChanged: (v) => setState(() => _edan.necesidadHumanitaria.banos = v),
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Observaciones',
          controller: _obsHumanitariaController,
          maxLines: 2,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ---------- 13 Responsable ----------

  Widget _seccion13() {
    return _SeccionEdan(
      numero: '13',
      titulo: 'Responsable del Formulario',
      descripcion: 'Nombre, cargo y contacto del responsable',
      completada: _s13Completada,
      expanded: _expandidas.contains('13'),
      onToggle: () => _toggle('13'),
      children: [
        _campo(
          label: 'Nombre del responsable *',
          controller: _respNombreController,
          hint: 'Ej: María López',
          textCapitalization: TextCapitalization.words,
          onChanged: (v) {
            _edan.responsable.nombre = v;
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Cargo *',
          controller: _respCargoController,
          hint: 'Ej: Técnico UGR',
          textCapitalization: TextCapitalization.words,
          onChanged: (v) {
            _edan.responsable.cargo = v;
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _campo(
                label: 'Teléfono',
                controller: _respFonoController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(20),
                ],
                onChanged: (v) {
                  _edan.responsable.fono = v;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _campo(
                label: 'Correo',
                controller: _respCorreoController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) {
                  _edan.responsable.correo = v;
                  setState(() {});
                },
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

  void _guardarBorrador() {
    final edan = _construirEdan();
    edan
      ..estado = 'borrador'
      ..idEstado = 1;
    Navigator.of(context).pop(edan);
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
    var h = int.parse(_hora12);
    if (_ampm == 'PM') {
      if (h != 12) h += 12;
    } else if (h == 12) {
      h = 0;
    }
    return '${h.toString().padLeft(2, '0')}:00';
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

Widget _buildDropdown<T>({
  required BuildContext context,
  required Key key,
  required String label,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
  String? hint,
}) {
  final primary = PaletteScope.of(context).primary;
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
        items: items,
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
  String? hint,
  TextInputType? keyboardType,
  TextCapitalization textCapitalization = TextCapitalization.none,
  bool readOnly = false,
  VoidCallback? onTap,
  Widget? suffixIcon,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
  List<TextInputFormatter>? inputFormatters,
}) {
  return CustomTextField(
    label: label,
    hint: hint,
    controller: controller,
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    readOnly: readOnly,
    onTap: onTap,
    suffixIcon: suffixIcon,
    maxLines: maxLines,
    onChanged: onChanged,
    inputFormatters: inputFormatters,
  );
}

Widget _numCampo({
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
    keyboardType: TextInputType.number,
    readOnly: readOnly,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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

class _AgregarBoton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AgregarBoton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_circle_outline, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: PaletteScope.of(context).primary,
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
        ],
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
  static const List<String> _tipos = [
    'Localidad',
    'Cantón',
    'Zona',
    'Comunidad',
    'Barrio',
  ];

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
                  'Localidad ${widget.index + 1}',
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
                  tooltip: 'Quitar localidad',
                  onPressed: widget.onEliminar,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDropdown(
            context: context,
            key: ValueKey('tipoLocalidad-${widget.index}'),
            label: 'Tipo de localidad',
            value: localidad.tipoLocalidad.isEmpty
                ? null
                : localidad.tipoLocalidad,
            items: _tipos
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            hint: 'Seleccione tipo',
            onChanged: (v) {
              localidad.tipoLocalidad = v ?? '';
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          _campo(
            label: 'Nombre de la localidad *',
            controller: _nombre,
            hint: 'Ej: Barrio Central, Zona Sur',
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
            widget.onChanged();
          }),
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
            widget.onChanged();
          }),
        ],
      ),
    );
  }

  Widget _impactoCheck(
      bool value, String label, ValueChanged<bool> onChanged) {
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
                  'Localidad ${index + 1}${nombre.trim().isNotEmpty ? ' · ${nombre.trim()}' : ''}',
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
  final bool readOnly;
  final ValueChanged<String> onChanged;

  const _NumCampoAutonomo({
    required this.label,
    required this.valor,
    required this.onChanged,
    this.readOnly = false,
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
      readOnly: widget.readOnly,
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
                const SizedBox(width: 10),
                Expanded(
                  child: _NumCampoAutonomo(
                    label: 'Desaparecidos',
                    valor: grupo.desaparecidos > 0 ? '${grupo.desaparecidos}' : '',
                    onChanged: (v) {
                      grupo.desaparecidos = int.tryParse(v.trim()) ?? 0;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaSaludRow extends StatefulWidget {
  final String titulo;
  final EdanEstablecimientoSalud valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _FilaSaludRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaSaludRow> createState() => _FilaSaludRowState();
}

class _FilaSaludRowState extends State<_FilaSaludRow> {
  late final TextEditingController _nombre = TextEditingController(text: widget.valor.nombreEstablecimiento);
  late final TextEditingController _comunidad = TextEditingController(text: widget.valor.comunidad);
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
              items: _nivelesAtencion
                  .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                  .toList(),
              onChanged: (v) {
                valor.nivelAtencion = v ?? '';
                widget.onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Nombre del establecimiento',
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
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
        _checkInline(
          value: valor.danoParcial,
          label: 'Daño parcial',
          onChanged: (v) {
            valor.danoParcial = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            valor.danoTotal = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
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
    );
  }
}

class _FilaVialRow extends StatefulWidget {
  final String titulo;
  final EdanDanoVial valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _FilaVialRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaVialRow> createState() => _FilaVialRowState();
}

class _FilaVialRowState extends State<_FilaVialRow> {
  late final TextEditingController _viaPuente = TextEditingController(text: widget.valor.viaPuente);
  late final TextEditingController _tramo = TextEditingController(text: widget.valor.tramo);
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);
  late final TextEditingController _obs = TextEditingController(text: widget.valor.observaciones);

  @override
  void dispose() {
    _viaPuente.dispose();
    _tramo.dispose();
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
          label: 'Vía o puente',
          controller: _viaPuente,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) {
            valor.viaPuente = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _campo(
          label: 'Tramo / km',
          controller: _tramo,
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
            valor.danoParcial = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            valor.danoTotal = v;
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
      ],
    );
  }
}

class _FilaInfraRow extends StatefulWidget {
  final String titulo;
  final EdanDanoInfraPublica valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _FilaInfraRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaInfraRow> createState() => _FilaInfraRowState();
}

class _FilaInfraRowState extends State<_FilaInfraRow> {
  late final TextEditingController _comunidad = TextEditingController(text: widget.valor.comunidad);
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
            valor.danoParcial = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            valor.danoTotal = v;
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
      ],
    );
  }
}

class _FilaEduRow extends StatefulWidget {
  final String titulo;
  final EdanDanoUnidadEducativa valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _FilaEduRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaEduRow> createState() => _FilaEduRowState();
}

class _FilaEduRowState extends State<_FilaEduRow> {
  late final TextEditingController _nombre = TextEditingController(text: widget.valor.nombreEstablecimiento);
  late final TextEditingController _comunidad = TextEditingController(text: widget.valor.comunidad);

  @override
  void dispose() {
    _nombre.dispose();
    _comunidad.dispose();
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
          label: 'Nombre de la unidad educativa',
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
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
        _checkInline(
          value: valor.danoParcial,
          label: 'Daño parcial',
          onChanged: (v) {
            valor.danoParcial = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            valor.danoTotal = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.suspensionClases,
          label: 'Suspensión de clases',
          onChanged: (v) {
            valor.suspensionClases = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.perdidaMaterial,
          label: 'Pérdida de material',
          onChanged: (v) {
            valor.perdidaMaterial = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.funcionaAlbergue,
          label: 'Funciona como albergue',
          onChanged: (v) {
            valor.funcionaAlbergue = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }
}

class _FilaViviendaRow extends StatefulWidget {
  final String titulo;
  final EdanDanoVivienda valor;
  final bool puedeEliminar;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _FilaViviendaRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaViviendaRow> createState() => _FilaViviendaRowState();
}

class _FilaViviendaRowState extends State<_FilaViviendaRow> {
  late final TextEditingController _comunidad = TextEditingController(text: widget.valor.comunidad);
  late final TextEditingController _parcial = TextEditingController(text: widget.valor.danoParcial > 0 ? '${widget.valor.danoParcial}' : '');
  late final TextEditingController _total = TextEditingController(text: widget.valor.danoTotal > 0 ? '${widget.valor.danoTotal}' : '');
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);
  late final TextEditingController _obs = TextEditingController(text: widget.valor.observaciones);

  @override
  void dispose() {
    _comunidad.dispose();
    _parcial.dispose();
    _total.dispose();
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
          onChanged: (v) {
            valor.comunidad = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _numCampo(
                label: 'Viviendas daño parcial',
                controller: _parcial,
                onChanged: (v) {
                  valor.danoParcial = int.tryParse(v) ?? 0;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numCampo(
                label: 'Viviendas daño total',
                controller: _total,
                onChanged: (v) {
                  valor.danoTotal = int.tryParse(v) ?? 0;
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

  const _FilaAgriculturaRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaAgriculturaRow> createState() => _FilaAgriculturaRowState();
}

class _FilaAgriculturaRowState extends State<_FilaAgriculturaRow> {
  late final TextEditingController _tipo = TextEditingController(text: widget.valor.tipoCultivo);
  late final TextEditingController _afectadas = TextEditingController(text: widget.valor.hectareasAfectadas > 0 ? '${widget.valor.hectareasAfectadas}' : '');
  late final TextEditingController _perdidas = TextEditingController(text: widget.valor.hectareasPerdidas > 0 ? '${widget.valor.hectareasPerdidas}' : '');
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);
  late final TextEditingController _obs = TextEditingController(text: widget.valor.observaciones);

  @override
  void dispose() {
    _tipo.dispose();
    _afectadas.dispose();
    _perdidas.dispose();
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
          label: 'Tipo de cultivo',
          controller: _tipo,
          hint: 'Ej: Maíz, Papa, Quinua...',
          textCapitalization: TextCapitalization.words,
          onChanged: (v) {
            valor.tipoCultivo = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _numCampo(
                label: 'Has afectadas',
                controller: _afectadas,
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

  const _FilaPecuarioRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaPecuarioRow> createState() => _FilaPecuarioRowState();
}

class _FilaPecuarioRowState extends State<_FilaPecuarioRow> {
  late final TextEditingController _especie = TextEditingController(text: widget.valor.especie);
  late final TextEditingController _raza = TextEditingController(text: widget.valor.raza);
  late final TextEditingController _afectados = TextEditingController(text: widget.valor.animalesAfectados > 0 ? '${widget.valor.animalesAfectados}' : '');
  late final TextEditingController _muertos = TextEditingController(text: widget.valor.animalesMuertos > 0 ? '${widget.valor.animalesMuertos}' : '');
  late final TextEditingController _necesidades = TextEditingController(text: widget.valor.necesidadesInmediatas);

  @override
  void dispose() {
    _especie.dispose();
    _raza.dispose();
    _afectados.dispose();
    _muertos.dispose();
    _necesidades.dispose();
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
        Row(
          children: [
            Expanded(
              child: _campo(
                label: 'Especie',
                controller: _especie,
                hint: 'Ej: Bovino, Ovino...',
                textCapitalization: TextCapitalization.words,
                onChanged: (v) {
                  valor.especie = v;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _campo(
                label: 'Raza',
                controller: _raza,
                textCapitalization: TextCapitalization.words,
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

  const _FilaInfraProdRow({
    required this.titulo,
    required this.valor,
    required this.puedeEliminar,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  State<_FilaInfraProdRow> createState() => _FilaInfraProdRowState();
}

class _FilaInfraProdRowState extends State<_FilaInfraProdRow> {
  late final TextEditingController _tipo = TextEditingController(text: widget.valor.tipo);

  @override
  void dispose() {
    _tipo.dispose();
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
          onChanged: (v) {
            valor.tipo = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        _checkInline(
          value: valor.danoParcial,
          label: 'Daño parcial',
          onChanged: (v) {
            valor.danoParcial = v;
            widget.onChanged();
          },
        ),
        _checkInline(
          value: valor.danoTotal,
          label: 'Daño total',
          onChanged: (v) {
            valor.danoTotal = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }
}
