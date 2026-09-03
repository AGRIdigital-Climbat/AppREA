import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/edan/edan_documento_sync_service.dart';
import '../../../../services/edan/edan_localidades_envio_v2_service.dart';
import '../../../../services/edan_secciones_registry.dart';
import '../../../../services/edan/edan_sync_respo_service.dart';
import 'edan_navigation_bar.dart';
import 'edan_page01.dart';
import 'edan_page02.dart';
import 'edan_page03.dart';
import 'edan_page04.dart';
import 'edan_page05.dart';
import 'edan_page06.dart';
import 'edan_page07.dart';
import 'edan_page08.dart';
import 'edan_page09.dart';
import 'edan_page10.dart';
import 'edan_page11.dart';
import 'edan_page13.dart';
import 'edan_resumen_page.dart';
import 'edan_section_instruction.dart';
import 'edan_section_page.dart';
import 'edan_seccion_estado.dart';
import 'edan_step_indicator.dart';

/// Wizard PageView del formulario EDAN (rol RESP).
///
/// Cada sección es una página. El modelo [EdanLocalidad] vive en memoria y se
/// pasa por referencia a las páginas, por lo que los datos se conservan al
/// hacer swipe horizontal. Cada "Siguiente" guarda la sección en SQLite.
class EdanFormWizard extends StatefulWidget {
  final Edan? edanAEditar;

  const EdanFormWizard({super.key, this.edanAEditar});

  @override
  State<EdanFormWizard> createState() => _EdanFormWizardState();
}

class _WizardPage {
  final String key;
  final String titulo;
  final String instruccion;
  final IconData icono;
  final Widget Function(BuildContext, EdanLocalidad, VoidCallback) builder;
  final bool Function(EdanLocalidad)? valida;

  const _WizardPage({
    required this.key,
    required this.titulo,
    required this.instruccion,
    required this.icono,
    required this.builder,
    this.valida,
  });
}

class _EdanFormWizardState extends State<EdanFormWizard> {
  late EdanLocalidad _localidad;
  final List<EdanSeccionEstado> _estados = [];
  late PageController _pageController;
  late List<_WizardPage> _pages;
  int _currentPage = 0;
  bool _saving = false;
  bool _allowPop = false;
  final DatabaseHelper _db = DatabaseHelper.instance;

  bool _reconstruyendo = false;

  /// Snapshot serializado de la localidad al abrir el wizard, para detectar
  /// si realmente hubo cambios antes de intentar un reenvío al servidor.
  Map<String, dynamic>? _snapshotInicial;

  @override
  void initState() {
    super.initState();
    _inicializarLocalidad();
    _pageController = PageController();
    _pages = _construirPaginas();
    _precargarCatalogo();
    // Al abrir borrador existente, sincroniza flags del modelo desde SQLite.
    _sincronizarFlagsDesdeSeccionesActivas();
    // Snapshot inicial (post-frame) para comparar cambios reales al guardar/
    // salir sin modificar nada. Se excluyen los campos volátiles de sync.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapshotInicial = _snapshotComparable(_localidad);
    });
    // Refresca los círculos de progreso tras cargar los datos persistidos
    // (re-apertura de un borrador), para reflejar el estado completado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _inicializarLocalidad() {
    final edan = widget.edanAEditar;
    if (edan != null && edan.localidades.isNotEmpty) {
      _localidad = edan.localidades.first;
    } else {
      _localidad = EdanLocalidad(
        estadoLocalidad: UgrLocalidadEstado.borrador,
        idEdanLocalidadEstado: UgrLocalidadEstado.borrador.id,
      );
      final token = AuthService.instance.currentToken;
      if (token != null) {
        _localidad.idUsuario = token.userId;
        _localidad.idDepartamento = token.idDepartamento;
        _localidad.idProvincia = token.idProvincia;
        _localidad.idMunicipio = token.idMunicipio;
        _localidad.departamentoNombre = token.departamentoNombre;
        _localidad.provinciaNombre = token.provinciaNombre;
        _localidad.municipioNombre = token.municipioNombre;
        _localidad.idTipoEvento = null;
        _localidad.fechaLlenado = DateTime.now().toIso8601String();
        final r = _localidad.responsable!;
        r.nombre = token.nombre;
        r.cargo = token.cargo ?? '';
        r.fono = token.celular ?? '';
        r.correo = token.correo ?? '';
      }
    }
  }

  void _precargarCatalogo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rp = context.read<ReporteProvider>();
      if (rp.gruposVulnerables.isEmpty) {
        rp.fetchGruposVulnerablesIfNeeded();
      }
      if (_localidad.idDepartamento != null) {
        rp.loadGeography();
      }
    });
  }

  List<_WizardPage> _construirPaginas() {
    final l = _localidad;
    final pages = <_WizardPage>[
      _WizardPage(
        key: 'intro',
        titulo: 'Introducción',
        instruccion: _introTexto,
        icono: Icons.info_outline,
        builder: (c, loc, _) => _intro(),
      ),
      _WizardPage(
        key: '01',
        titulo: 'Datos generales',
        instruccion:
            'Registre la localidad afectada y marque los impactos. Los impactos '
            'marcados determinan las secciones del formulario.',
        icono: Icons.place_outlined,
        builder: (c, loc, reb) => EdanPage01(
          localidad: loc,
          onImpactosCambio: rebuild,
        ),
        valida: (l) =>
            l.nombre.trim().isNotEmpty || l.impPoblacion || l.impSalud,
      ),
      _WizardPage(
        key: '02',
        titulo: 'Población damnificada y afectada',
        instruccion:
            'Ingrese los totales estimados de población afectada y familias '
            'damnificadas.',
        icono: Icons.people_outline,
        builder: (c, loc, _) => EdanPage02(localidad: loc),
        valida: (l) =>
            l.totalPoblacionAfectada > 0 ||
            l.totalFamiliasAfectadas > 0 ||
            l.totalFamiliasDamnificadas > 0,
      ),
    ];

    if (l.impPoblacion) {
      pages.add(_WizardPage(
        key: '03',
        titulo: 'Impacto en la población',
        instruccion:
            'Registre el impacto por grupo etario y las necesidades de primera '
            'respuesta. Cada grupo tiene su propio ID.',
        icono: Icons.groups_outlined,
        builder: (c, loc, _) => EdanPage03(localidad: loc),
      ));
    }
    if (l.impSalud) {
      pages.add(_WizardPage(
        key: '04',
        titulo: 'Impacto en la salud',
        instruccion:
            'Registre los establecimientos de salud afectados y las necesidades '
            'de salud. Puede agregar varios establecimientos.',
        icono: Icons.local_hospital_outlined,
        builder: (c, loc, _) => EdanPage04(localidad: loc),
      ));
    }
    if (l.impInfraestructura) {
      pages.add(_WizardPage(
        key: '05',
        titulo: 'Impacto en infraestructuras',
        instruccion:
            'Registre daños en vías, puentes e infraestructura pública.',
        icono: Icons.location_city_outlined,
        builder: (c, loc, _) => EdanPage05(localidad: loc),
      ));
    }
    if (l.impServicios) {
      pages.add(_WizardPage(
        key: '06',
        titulo: 'Impacto en servicios básicos',
        instruccion:
            'Indique el estado de los servicios básicos (agua, luz, '
            'alcantarillado, gas, telecomunicaciones).',
        icono: Icons.home_work_outlined,
        builder: (c, loc, _) => EdanPage06(localidad: loc),
      ));
    }
    if (l.impEducacion) {
      pages.add(_WizardPage(
        key: '07',
        titulo: 'Impacto en educación',
        instruccion:
            'Registre unidades educativas afectadas, suspensión de clases y '
            'personal.',
        icono: Icons.school_outlined,
        builder: (c, loc, _) => EdanPage07(localidad: loc),
      ));
    }
    if (l.impVivienda) {
      pages.add(_WizardPage(
        key: '08',
        titulo: 'Impacto en viviendas',
        instruccion: 'Registre viviendas con daño parcial y total.',
        icono: Icons.home_outlined,
        builder: (c, loc, _) => EdanPage08(localidad: loc),
      ));
    }
    if (l.impAgropecuario) {
      pages.add(_WizardPage(
        key: '09',
        titulo: 'Impacto agropecuario',
        instruccion:
            'Registre daños en cultivos, pecuarios e infraestructura productiva. '
            'Cada ítem tiene su propio ID.',
        icono: Icons.agriculture_outlined,
        builder: (c, loc, _) => EdanPage09(localidad: loc),
      ));
    }
    if (l.impProteccion) {
      pages.add(_WizardPage(
        key: '10',
        titulo: 'Necesidades de protección',
        instruccion:
            'Registre la población vulnerable por sexo y la necesidad de apoyo '
            'psicológico.',
        icono: Icons.shield_outlined,
        builder: (c, loc, _) => EdanPage10(localidad: loc),
      ));
    }
    if (l.impNecesidades) {
      pages.add(_WizardPage(
        key: '11',
        titulo: 'Necesidades humanitarias',
        instruccion: 'Marque las necesidades humanitarias de la localidad.',
        icono: Icons.volunteer_activism_outlined,
        builder: (c, loc, _) => EdanPage11(localidad: loc),
      ));
    }

    pages.add(_WizardPage(
      key: '13',
      titulo: 'Responsable del formulario',
      instruccion:
          'Datos del responsable. Se completan automáticamente con los datos '
          'del usuario.',
      icono: Icons.badge_outlined,
      builder: (c, loc, _) => EdanPage13(localidad: loc),
      valida: (l) =>
          (l.responsable?.nombre.trim().isNotEmpty ?? false) &&
          (l.responsable?.cargo.trim().isNotEmpty ?? false),
    ));

    pages.add(_WizardPage(
      key: 'resumen',
      titulo: 'Resumen y envío',
      instruccion:
          'Revise el resumen de la información. Solo aquí puede enviar el '
          'formulario a "Enviado UGR".',
      icono: Icons.summarize_outlined,
      builder: (c, loc, _) => EdanResumenPage(
        localidad: loc,
        seccionesCompletas: _seccionesCompletas(),
      ),
    ));

    return pages;
  }

  static const String _introTexto =
      'El EDAN (Evaluación de Daños y Análisis de Necesidades) es una herramienta oficial utilizada para registrar directamente en el lugar de un desastre la gravedad, ubicación y extensión de los daños provocados por un evento adverso..\n\n'
      'Complete cada sección según corresponda al evento. Deslice hacia la izquierda para '
      'avanzar entre secciones o presione "SIGUIENTE"; Presione el ícono de guardar en la parte superior para salvar la información.';

  Map<String, bool> _seccionesCompletas() {
    final map = <String, bool>{};
    for (final p in _pages) {
      if (p.key == 'intro' || p.key == 'resumen') continue;
      if (p.valida != null) {
        map[p.key] = p.valida!(_localidad);
      } else {
        map[p.key] = _seccionTieneDatos(p.key);
      }
    }
    return map;
  }

  bool _seccionTieneDatos(String key) {
    switch (key) {
      case '03':
        if (_localidad.impImpactoPoblacion ||
            _localidad.impPrimeraRespuesta) {
          return true;
        }
        return _localidad.impactoPoblacion.any((i) => i.tieneDatosGlobales) ||
            (_localidad.necesidadPrimeraRespuesta?.tieneDatos ?? false);
      case '04':
        if (_localidad.impSaludEstablecimientos ||
            _localidad.impNecesidadSalud) {
          return true;
        }
        return _localidad.establecimientosSalud.isNotEmpty ||
            (_localidad.necesidadSalud?.tieneDatos ?? false);
      case '05':
        if (_localidad.impDanosViales || _localidad.impDanosInfraPublica) {
          return true;
        }
        return _localidad.danosViales.isNotEmpty ||
            _localidad.danosInfraPublica.isNotEmpty;
      case '06':
        return _localidad.impServiciosBasicos
            ? true
            : _localidad.serviciosBasicos.any((s) => s.tieneDatos);
      case '07':
        return _localidad.impUnidadesEducativas
            ? true
            : _localidad.unidadesEducativas.isNotEmpty;
      case '08':
        return _localidad.impDanosVivienda
            ? true
            : _localidad.danosVivienda.isNotEmpty;
      case '09':
        if (_localidad.impDanosAgricultura ||
            _localidad.impDanosPecuarios ||
            _localidad.impInfraProductiva) {
          return true;
        }
        return _localidad.danosAgricultura.isNotEmpty ||
            _localidad.danosPecuarios.isNotEmpty ||
            _localidad.infraProductiva.isNotEmpty;
      case '10':
        return _localidad.impProteccion
            ? true
            : _localidad.proteccion.any((g) => g.tieneDatos);
      case '11':
        return _localidad.impNecesidadHumanitaria
            ? true
            : (_localidad.necesidadHumanitaria?.tieneDatos ?? false);
      default:
        return false;
    }
  }

  Widget _intro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Icon(Icons.assessment_outlined,
            size: 64, color: PaletteScope.of(context).primary),
        const SizedBox(height: 16),
        const Text(
          'Formulario EDAN',
          style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        const Text(
          _introTexto,
          style: TextStyle(
            fontSize: 14, height: 1.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PaletteScope.of(context).primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: PaletteScope.of(context).primary.withValues(alpha: 0.2)),
          ),
          child: const Text(
            'Para enviar, complete todas las secciones y presione "Enviar" '
            'desde el resumen final.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  // Reconstruye las páginas cuando cambian los impactos en la sección 01.
  void rebuild() {
    if (_reconstruyendo) return;
    _reconstruyendo = true;
    final nuevas = _construirPaginas();
    setState(() {
      _pages = nuevas;
      if (_currentPage >= nuevas.length - 2) {
        _pageController.jumpToPage(nuevas.length - 2);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconstruyendo = false);
  }

  /// Lee `localidad_secciones_activas` en SQLite y sobreescribe los flags
  /// del modelo. Se llama al abrir un borrador existente para que las páginas
  /// del wizard reflejen exactamente lo que está guardado.
  Future<void> _sincronizarFlagsDesdeSeccionesActivas() async {
    final idLocal = _localidad.idLocal;
    if (idLocal == null) return;

    // FIX Duplicacion: recargar arrays desde las tablas de seccion SQLite
    // antes de sincronizar flags. Si el usuario quito items del array 1:N,
    // el modelo en datos_json podria tener items fantasma; SQLite es la
    // fuente canonical gracias al cleanup en guardarSecciones.
    final sincV2 = EdanLocalidadesEnvioV2Service();
    await sincV2.cargarSeccionesDesdeSQLite(_localidad);

    final activas = await _db.leerSeccionesActivas(idLocal);
    if (activas.isEmpty || !mounted) return;

    final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas(activas);
    _localidad
      ..impPoblacion = flags['imp_poblacion'] ?? _localidad.impPoblacion
      ..impSalud = flags['imp_salud'] ?? _localidad.impSalud
      ..impInfraestructura = flags['imp_infraestructura'] ?? _localidad.impInfraestructura
      ..impServicios = flags['imp_servicios'] ?? _localidad.impServicios
      ..impEducacion = flags['imp_educacion'] ?? _localidad.impEducacion
      ..impVivienda = flags['imp_vivienda'] ?? _localidad.impVivienda
      ..impAgropecuario = flags['imp_agropecuario'] ?? _localidad.impAgropecuario
      ..impProteccion = flags['imp_proteccion'] ?? _localidad.impProteccion
      ..impNecesidades = flags['imp_necesidades'] ?? _localidad.impNecesidades
      ..impImpactoPoblacion = flags['imp_impacto_poblacion'] ?? _localidad.impImpactoPoblacion
      ..impPrimeraRespuesta = flags['imp_primera_respuesta'] ?? _localidad.impPrimeraRespuesta
      ..impSaludEstablecimientos = flags['imp_salud_establecimientos'] ?? _localidad.impSaludEstablecimientos
      ..impNecesidadSalud = flags['imp_necesidad_salud'] ?? _localidad.impNecesidadSalud
      ..impDanosViales = flags['imp_danos_viales'] ?? _localidad.impDanosViales
      ..impDanosInfraPublica = flags['imp_danos_infra_publica'] ?? _localidad.impDanosInfraPublica
      ..impServiciosBasicos = flags['imp_servicios_basicos'] ?? _localidad.impServiciosBasicos
      ..impUnidadesEducativas = flags['imp_unidades_educativas'] ?? _localidad.impUnidadesEducativas
      ..impDanosVivienda = flags['imp_danos_vivienda'] ?? _localidad.impDanosVivienda
      ..impDanosAgricultura = flags['imp_danos_agricultura'] ?? _localidad.impDanosAgricultura
      ..impDanosPecuarios = flags['imp_danos_pecuarios'] ?? _localidad.impDanosPecuarios
      ..impInfraProductiva = flags['imp_infra_productiva'] ?? _localidad.impInfraProductiva
      ..impNecesidadHumanitaria = flags['imp_necesidad_humanitaria'] ?? _localidad.impNecesidadHumanitaria;

    // Reconstruye las paginas con los flags actualizados desde SQLite.
    rebuild();
  }

  Future<void> _next() async {
    if (_saving) return;
    final actual = _pages[_currentPage];
    if (actual.key == 'intro') {
      _irA(_currentPage + 1);
      return;
    }
    setState(() => _saving = true);
    // Solo guarda localmente. El envío al servidor ocurre solo al presionar
    // "Guardar" o "Salir y guardar" (via _guardarYEnviar).
    if (_huboCambios()) {
      await _guardar(actual.key);
    } else {
      await _guardarSinMarcar();
    }
    setState(() => _saving = false);
    if (!mounted) return;
    _irA(_currentPage + 1);
  }

  Future<void> _guardar(String seccionKey) async {
    final token = AuthService.instance.currentToken;
    final envio = EdanLocalidadesEnvioV2Service();
    try {
      // Determinar rutas: la página actual, o TODAS si es resumen/página sin mapa.
      final rutasPagina = EdanSeccionesRegistry.rutasDePagina(seccionKey);
      final rutasGuardar = rutasPagina.isEmpty
          ? EdanSeccionesRegistry.rutasV2Todas()
          : rutasPagina;

      if (_huboCambios()) {
        _localidad.editado = true;
      }

      if (_localidad.idLocal != null) {
        await _db.updateLocalidad(_localidad);
        await envio.guardarSecciones(_localidad, rutasGuardar);
        await _db.marcarSeccionesModificadas(
          _localidad.idLocal!,
          rutasGuardar,
        );
      } else if (token != null) {
        final id = await _db.insertLocalidad(_localidad, usuarioId: token.userId);
        _localidad.idLocal = id;
        await envio.guardarSecciones(_localidad, rutasGuardar);
        await _db.marcarSeccionesModificadas(id, rutasGuardar);
      }
      _marcarGuardada(seccionKey);
    } catch (e) {
      debugPrint('EdanFormWizard._guardar error: $e');
    }
  }

  void _marcarGuardada(String seccionKey) {
    final idx = _estados.indexWhere((e) => e.seccionId == seccionKey);
    if (idx >= 0) {
      _estados[idx] = _estados[idx].copyWith(
        guardadaLocal: true,
        pendienteEnvio: true,
        fechaGuardado: DateTime.now(),
      );
    } else {
      _estados.add(EdanSeccionEstado(
        seccionId: seccionKey,
        guardadaLocal: true,
        pendienteEnvio: true,
        fechaGuardado: DateTime.now(),
      ));
    }
  }

  /// Persiste la localidad a SQLite SIN marcar secciones como modificadas
  /// (útil al salir sin que hubiera cambios reales, para no reenviar luego).
  Future<void> _guardarSinMarcar() async {
    final token = AuthService.instance.currentToken;
    try {
      if (_localidad.idLocal != null) {
        await _db.updateLocalidad(_localidad);
      } else if (token != null) {
        final id = await _db.insertLocalidad(_localidad, usuarioId: token.userId);
        _localidad.idLocal = id;
      }
    } catch (e) {
      debugPrint('EdanFormWizard._guardarSinMarcar error: $e');
    }
  }

  /// Serializa la localidad para detección de cambios, excluyendo los campos
  /// volátiles de sync (fechas/flags de estado) que el usuario no edita.
  Map<String, dynamic> _snapshotComparable(EdanLocalidad localidad) {
    final json = localidad.toApiJson();
    for (final clave in const [
      'fecha_modificacion',
      'pendiente_actualizacion',
      'pendiente_eliminacion',
      'id_edan_localidad_estado',
    ]) {
      json.remove(clave);
    }
    return json;
  }

  bool _huboCambios() {
    final inicial = _snapshotInicial;
    if (inicial == null) return true;
    final actual = _snapshotComparable(_localidad);
    return jsonEncode(inicial) != jsonEncode(actual);
  }

  /// Guarda a SQLite y, si hay conexión, intenta el envío inmediato al
  /// servidor (secciones v2 + fotos). Mantiene la localidad en estado BORRADOR
  /// (no toca `estadoLocalidad`/`idEdanLocalidadEstado`; el estado solo cambia
  /// a Enviado UGR cuando el usuario pulsa "Enviar" en el resumen).
  ///
  /// Solo intenta el envío cuando el snapshot detecta cambios reales y hay
  /// secciones marcadas como modificadas; si no hay cambios, no reenvía ni
  /// reporta un error (evita el mensaje espurio "falló el envío").
  Future<_GuardadoResult> _guardarYEnviar(String seccionKey) async {
    final sinCambios = !_huboCambios();
    if (!sinCambios) {
      await _guardar(seccionKey);
    } else {
      // No hubo cambios: persiste la fila tal cual (por si faltaba crear el
      // id_local) pero sin marcar secciones como modificadas.
      await _guardarSinMarcar();
      return _GuardadoResult.sinCambios;
    }

    final idLocal = _localidad.idLocal;
    if (idLocal == null) return _GuardadoResult.soloLocal;

    final modificadas = await _db.getSeccionesModificadas(idLocal);
    if (modificadas.isEmpty) return _GuardadoResult.sinCambios;

    final conectado = await ConnectivityService().checkNow();
    if (!conectado) return _GuardadoResult.sinConexion;

    final ok = await EdanDocumentoSyncService()
        .enviarLocalidadDocumento(_localidad);
      if (ok) {
        _localidad
          ..editado = false
          ..sincronizado = true;
        await _db.updateLocalidad(_localidad);
        // Limpiar las marcas de modificada para las rutas enviadas.
        await _db.clearSeccionesModificadas(idLocal, modificadas.toSet());
        EdanSyncRespoService.instance.recargarPendientes();
        return _GuardadoResult.enviado;
      }
    return _GuardadoResult.fallo;
  }

  Future<void> _guardarBorrador() async {
    setState(() => _saving = true);
    final resultado = await _guardarYEnviar(_pages[_currentPage].key);
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_mensajeGuardado(resultado))),
    );
    setState(() => _allowPop = true);
    Navigator.pop(context, true);
  }

  /// Mensaje de snackbar según el resultado del guardado/salida.
  String _mensajeGuardado(_GuardadoResult r) {
    switch (r) {
      case _GuardadoResult.enviado:
        return 'Borrador guardado y enviado';
      case _GuardadoResult.soloLocal:
      case _GuardadoResult.sinCambios:
        return 'Borrador guardado';
      case _GuardadoResult.fallo:
        return 'Borrador guardado (falló el envío, quedó pendiente)';
      case _GuardadoResult.sinConexion:
        return 'Borrador guardado (sin conexión, se sincronizará después)';
    }
  }

  /// Guarda a SQLite SIN salir (botón de la AppBar).
  Future<void> _guardarSinSalir() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _guardar(_pages[_currentPage].key);
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Borrador guardado')),
    );
  }

  /// Pregunta al usuario antes de salir del formulario (atrás/gesto del sistema).
  Future<void> _confirmarSalir() async {
    final hayCambios = _huboCambios();
    final salir = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir del formulario?'),
        content: Text(
          hayCambios
              ? 'Tiene cambios sin guardar. Puede guardar el borrador antes de salir.'
              : 'No se realizaron cambios. ¿Desea salir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'salir'),
            child: const Text('Salir'),
          ),
          if (hayCambios)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'guardar'),
              child: const Text('Salir y guardar'),
            ),
        ],
      ),
    );

    if (!mounted) return;
    switch (salir) {
      case 'guardar':
        // Guarda igual que el botón de la AppBar (solo local, sin reenvío).
        await _guardarSinSalir();
        _salirPermitido();
        break;
      case 'salir':
        _salirPermitido();
        break;
      default:
        break;
    }
  }

  void _salirPermitido() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.pop(context, true);
  }

  Future<void> _enviar() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _guardar(_pages[_currentPage].key);

    // Marcar estado Enviado UGR (destino del responsable al enviar).
    _localidad.idEdanLocalidadEstado = UgrLocalidadEstado.enviadoUgr.id;
    _localidad.estadoLocalidad = UgrLocalidadEstado.enviadoUgr;
    _localidad.editado = true;
    if (_localidad.idLocal != null) {
      await _db.updateLocalidad(_localidad);
    }

    // Si hay conexión, envío inmediato al servidor (secciones v2 + fotos).
    final conectado = await ConnectivityService().checkNow();
    if (conectado) {
      final docSync = EdanDocumentoSyncService();
      // PRIORIDAD: procesar cola de deletes offline PRIMERO
      await docSync.procesarColaDeletes();
      // Eliminar filas marcadas con marcado_borrar=1
      await docSync.eliminarFilasAntesDelPush(_localidad);
      // Enviar documento completo (fotos + POST/PUT)
      final ok = await docSync.enviarLocalidadDocumento(_localidad);
      if (ok && _localidad.idLocal != null) {
        _localidad
          ..editado = false
          ..sincronizado = true;
        await _db.updateLocalidad(_localidad);
        // Limpiar las marcas de modificada (ya se enviaron todas).
        await _db.marcarTodasSeccionesSincronizadas(_localidad.idLocal!);
        EdanSyncRespoService.instance.recargarPendientes();
      }
    }

    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!conectado
            ? 'Formulario enviado a UGR (sin conexión; se sincronizará después)'
            : 'Formulario enviado a UGR'),
      ),
    );
    setState(() => _allowPop = true);
    Navigator.pop(context, true);
  }

  void _irA(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() => _currentPage = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isLast = _currentPage == _pages.length - 1;
    final esResumen = page.key == 'resumen';

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmarSalir();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Formulario EDAN'),
          actions: [
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              tooltip: 'Guardar borrador',
              onPressed: _saving ? null : _guardarSinSalir,
            ),
          ],
        ),
        body: Column(
        children: [
          EdanStepIndicator(
            currentIndex: _currentPage,
            total: _pages.length,
            titulos: [for (final p in _pages) p.titulo],
            iconos: [for (final p in _pages) p.icono],
            completada: [for (final p in _pages) _seccionCompleta(p.key)],
            onTap: (i) => _irA(i),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const PageScrollPhysics(),
              itemCount: _pages.length,
              onPageChanged: (i) {
                // Auto-guardar la página que se deja al hacer swipe.
                final prevKey = _pages[_currentPage].key;
                final prevRutas = EdanSeccionesRegistry.rutasDePagina(prevKey);
                setState(() => _currentPage = i);
                if (prevRutas.isNotEmpty && _huboCambios()) {
                  _guardar(prevKey);
                }
              },
              itemBuilder: (context, index) {
                final p = _pages[index];
                return EdanSectionPage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p.key != 'intro')
                        EdanSeccionInstruction(
                          titulo: p.titulo,
                          instruccion: p.instruccion,
                          icono: p.icono,
                          estadoEtiqueta: _estadoEtiqueta(p.key),
                          completada: _seccionCompleta(p.key),
                        ),
                      const SizedBox(height: 14),
                      p.builder(context, _localidad, rebuild),
                    ],
                  ),
                );
              },
            ),
          ),
          EdanNavigationBar(
            showBack: _currentPage > 0,
            isLastPage: isLast,
            isPreview: esResumen,
            saving: _saving,
            onBack: () => _irA(_currentPage - 1),
            onNext: _next,
            onSaveDraft: _guardarBorrador,
            onEnviar: _enviar,
          ),
        ],
      ),
      ),
    );
  }

  String? _estadoEtiqueta(String key) {
    if (_seccionCompleta(key)) return 'Completada';
    return 'Pendiente';
  }

  bool _seccionCompleta(String key) {
    final p = _pages.firstWhere((p) => p.key == key, orElse: () => _WizardPage(
          key: key, titulo: '', instruccion: '', icono: Icons.circle, builder: (c, l, r) => const SizedBox.shrink()));
    if (p.valida != null) return p.valida!(_localidad);
    return _seccionTieneDatos(key);
  }
}

/// Resultado del flujo de guardado (con o sin envío automático).
enum _GuardadoResult {
  /// No hubo cambios reales; se guardó local sin reenviar.
  sinCambios,

  /// Se guardó y subió al servidor correctamente.
  enviado,

  /// Conexión disponible pero el envío falló (queda pendiente).
  fallo,

  /// Sin conexión a internet; queda pendiente para el sync central.
  sinConexion,

  /// La localidad no tiene idLocal aún; solo persistió local.
  soloLocal,
}