import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/permission_service.dart';
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
import '../../../../widgets/tutorial_guide.dart';
import '../../../../widgets/asistente_ia.dart';

/// Wizard PageView del formulario EDAN (rol RESP).
///
/// Cada sección es una página. El modelo [EdanLocalidad] vive en memoria y se
/// pasa por referencia a las páginas, por lo que los datos se conservan al
/// hacer swipe horizontal. El guardado se realiza únicamente desde el ícono
/// de guardar en la AppBar o al enviar el formulario.
class EdanFormWizard extends StatefulWidget {
  final Edan? edanAEditar;

  const EdanFormWizard({super.key, this.edanAEditar});

  @override
  State<EdanFormWizard> createState() => _EdanFormWizardState();
}

/// Guía interactiva: switch maestro. `false` oculta el icono `?` de TODAS las
/// páginas sin tocar cada una. Para deshabilitar SOLO una página, poner
/// `habilitarAyuda: false` en su `_WizardPage`.
class _WizardPage {
  final String key;
  final String titulo;
  final String instruccion;
  final IconData icono;
  final Widget Function(BuildContext, EdanLocalidad, VoidCallback) builder;
  final String? tituloAyuda;
  final List<String>? consejosAyuda;
  final bool? habilitarAyuda;

  const _WizardPage({
    required this.key,
    required this.titulo,
    required this.instruccion,
    required this.icono,
    required this.builder,
    this.tituloAyuda,
    this.consejosAyuda,
    this.habilitarAyuda,
  });
}

class _EdanFormWizardState extends State<EdanFormWizard> {
  /// Switch maestro de la guía interactiva: en `false` se oculta el icono `?`
  /// de todas las páginas. Para deshabilitar solo una página, usar
  /// `habilitarAyuda: false` en su `_WizardPage`.
  static const bool kAyudasHabilitadas = true;

  /// Personajes de la guía. Se elige uno al azar en cada apertura. Se cambian
  /// reemplazando los archivos en `assets/images/`.
  static const List<String> kPersonajeImagenes = [
    'assets/images/imagen1.png',
    'assets/images/imagen2.png',
    'assets/images/imagen3.png',
  ];

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

  /// Indica si el snapshot inicial ya fue capturado de forma confiable
  /// (tras terminar la sincronización async de flags/arrays desde SQLite).
  /// Si el usuario presiona "atrás" antes, [_huboCambios] retorna `false`
  /// y solo se muestra "Cancelar"/"Salir".
  bool _snapshotListo = false;

  @override
  void initState() {
    super.initState();
    _inicializarLocalidad();
    _pageController = PageController();
    _pages = _construirPaginas();
    _precargarCatalogo();
    // Captura el baseline SOLO después de que el sync async de flags/arrays
    // terminó (borradores existentes). Sin esto, la recarga desde SQLite
    // modifica `_localidad` después del snapshot y `_huboCambios()` da falsos
    // positivos (diálogo con "Guardar y salir" sin haber tocado nada).
    _prepararSnapshot();
    // Refresca los círculos de progreso tras cargar los datos persistidos
    // (re-apertura de un borrador), para reflejar el estado completado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Espera a que la sincronización de secciones desde SQLite termine
  /// (borradores existentes) y captura el snapshot base en el frame
  /// siguiente, con la comparación ya normalizada.
  Future<void> _prepararSnapshot() async {
    try {
      await _sincronizarFlagsDesdeSeccionesActivas();
    } catch (e) {
      debugPrint('EdanFormWizard._prepararSnapshot error: $e');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _snapshotInicial = _snapshotComparable(_localidad);
      _snapshotListo = true;
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
      PermissionService.asegurarPermisosFormulario();
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
        builder: (c, loc, reb) =>
            EdanPage01(localidad: loc, onImpactosCambio: rebuild),
        // --- Página 01: texto de la guía interactiva ---
        tituloAyuda: 'Datos generales',
        habilitarAyuda:
            true, // Ejemplo de control por página (false = oculta el ?)
        consejosAyuda: const [
          'Revise cuidadosamente el tipo de evento',
          'Revise la hora de ocurrencia del evento y revise si es AM o PM.',
          'Es muy importante que marque las casillas si existe afectación y/o necesidades y revise cuidadosamente los campos',
        ],
      ),
      // --- Página 02: texto de la guía interactiva ---
      _WizardPage(
        key: '02',
        titulo: 'Población damnificada y afectada',
        instruccion:
            'Ingrese los totales estimados de población afectada y familias '
            'damnificadas.',
        icono: Icons.people_outline,
        builder: (c, loc, _) => EdanPage02(localidad: loc),
        tituloAyuda: 'Población damnificada',
        consejosAyuda: const [
          'Escribe los totales estimados de familias damnificadas, familias '
              'afectadas y población total afectada.',
          'Ingresa solo números; al menos un total debe ser mayor a cero.',
        ],
      ),
    ];

    if (l.impPoblacion) {
      // --- Página 03: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '03',
          titulo: 'Impacto en la población',
          instruccion:
              'Registre el impacto por grupo etario y las necesidades de primera '
              'respuesta. Cada grupo tiene su propio ID.',
          icono: Icons.groups_outlined,
          builder: (c, loc, _) => EdanPage03(localidad: loc),
          tituloAyuda: 'Impacto en la población',
          consejosAyuda: const [
            'Marca los grupos etarios afectados y registra heridos, fallecidos y '
                'desaparecidos por grupo. Los totales se calculan solos.',
            'Marca las necesidades de primera respuesta: búsqueda y rescate, '
                'salvamento y evacuación.',
            'Agrega observaciones cuando sea necesario.',
          ],
        ),
      );
    }
    if (l.impSalud) {
      // --- Página 04: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '04',
          titulo: 'Impacto en la salud',
          instruccion:
              'Registre los establecimientos de salud afectados y las necesidades '
              'de salud. Puede agregar varios establecimientos.',
          icono: Icons.local_hospital_outlined,
          builder: (c, loc, _) => EdanPage04(localidad: loc),
          tituloAyuda: 'Impacto en la salud',
          consejosAyuda: const [
            'Presiona "Agregar" para registrar cada establecimiento de salud '
                'afectado; puedes agregar varios.',
            'Indica el nivel de atención y el nivel de daño en la '
                'infraestructura.',
            'Marca si existe personal de salud afectado e ingresa los números.',
            'Registra la necesidad de salud (botiquín / personas con atención '
                'inmediata) y otras necesidades.',
            'Saca una foto de respaldo de cada establecimiento.',
          ],
        ),
      );
    }
    if (l.impInfraestructura) {
      // --- Página 05: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '05',
          titulo: 'Impacto en infraestructuras',
          instruccion:
              'Registre daños en vías, puentes e infraestructura pública.',
          icono: Icons.location_city_outlined,
          builder: (c, loc, _) => EdanPage05(localidad: loc),
          tituloAyuda: 'Impacto en infraestructuras',
          consejosAyuda: const [
            'Registra los daños de vías y/o puentes: tipo, tramo, tipo de daño y '
                'kilómetros de daño.',
            'Registra la infraestructura pública afectada (oficinas, mercados, '
                'estadios, etc.) y su magnitud de daño.',
            'Indica las necesidades inmediatas y observaciones de cada ítem.',
            'Saca una foto de respaldo de cada daño.',
          ],
        ),
      );
    }
    if (l.impServicios) {
      // --- Página 06: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '06',
          titulo: 'Impacto en servicios básicos',
          instruccion:
              'Indique el estado de los servicios básicos (agua, luz, '
              'alcantarillado, gas, telecomunicaciones).',
          icono: Icons.home_work_outlined,
          builder: (c, loc, _) => EdanPage06(localidad: loc),
          tituloAyuda: 'Servicios básicos',
          consejosAyuda: const [
            'Marca los servicios afectados: energía eléctrica, agua potable, '
                'alcantarillado, gas domiciliario y telecomunicaciones.',
            'Al marcar un servicio se expanden los detalles: magnitud de daño, '
                'necesidades y observaciones.',
            'Saca una foto de respaldo de cada servicio afectado.',
          ],
        ),
      );
    }
    if (l.impEducacion) {
      // --- Página 07: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '07',
          titulo: 'Impacto en educación',
          instruccion:
              'Registre unidades educativas afectadas, suspensión de clases y '
              'personal.',
          icono: Icons.school_outlined,
          builder: (c, loc, _) => EdanPage07(localidad: loc),
          tituloAyuda: 'Impacto en educación',
          consejosAyuda: const [
            'Presiona "Agregar" para registrar cada unidad educativa afectada.',
            'Ingresa el número de estudiantes, profesores y administrativos.',
            'Marca el tipo de daño (parcial o total) y si hubo suspensión de '
                'clases.',
            'Saca una foto de respaldo de cada unidad educativa.',
          ],
        ),
      );
    }
    if (l.impVivienda) {
      // --- Página 08: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '08',
          titulo: 'Impacto en viviendas',
          instruccion: 'Registre viviendas con daño parcial y total.',
          icono: Icons.home_outlined,
          builder: (c, loc, _) => EdanPage08(localidad: loc),
          tituloAyuda: 'Impacto en viviendas',
          consejosAyuda: const [
            'Presiona "Agregar" para registrar los daños por localidad.',
            'Ingresa el número de viviendas con daño parcial y con daño total.',
            'Indica las necesidades inmediatas de las viviendas afectadas.',
            'Saca una foto de respaldo de los daños.',
          ],
        ),
      );
    }
    if (l.impAgropecuario) {
      // --- Página 09: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '09',
          titulo: 'Impacto agropecuario',
          instruccion:
              'Registre daños en cultivos, pecuarios e infraestructura productiva. '
              'Cada ítem tiene su propio ID.',
          icono: Icons.agriculture_outlined,
          builder: (c, loc, _) => EdanPage09(localidad: loc),
          tituloAyuda: 'Impacto agropecuario',
          consejosAyuda: const [
            'Registra los daños en cultivos: tipo de cultivo y hectáreas '
                'afectadas y perdidas.',
            'Registra los daños en especies pecuarias: especie, raza y animales '
                'afectados y muertos.',
            'Registra los daños en la infraestructura productiva (almacenes, '
                'silos, etc.).',
            'Agrega necesidades inmediatas y observaciones en cada ítem.',
          ],
        ),
      );
    }
    if (l.impProteccion) {
      // --- Página 10: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '10',
          titulo: 'Necesidades de protección',
          instruccion:
              'Registre la población vulnerable por sexo y la necesidad de apoyo '
              'psicológico.',
          icono: Icons.shield_outlined,
          builder: (c, loc, _) => EdanPage10(localidad: loc),
          tituloAyuda: 'Necesidades de protección',
          consejosAyuda: const [
            'Marca los grupos vulnerables afectados y registra el número de '
                'mujeres y hombres.',
            'Indica si requieren apoyo psicosocial y/o reposición de documento '
                'de identidad.',
            'El total se calcula automáticamente.',
          ],
        ),
      );
    }
    if (l.impNecesidades) {
      // --- Página 11: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '11',
          titulo: 'Necesidades humanitarias',
          instruccion: 'Marque las necesidades humanitarias de la localidad.',
          icono: Icons.volunteer_activism_outlined,
          builder: (c, loc, _) => EdanPage11(localidad: loc),
          tituloAyuda: 'Necesidades humanitarias',
          consejosAyuda: const [
            'Marca las necesidades humanitarias de la localidad (alimentos, '
                'refugio, higiene, etc.).',
            'Al marcar cada necesidad puedes agregar sus observaciones '
                'específicas.',
          ],
        ),
      );
    }

    pages.add(
      _WizardPage(
        key: '13',
        titulo: 'Responsable del formulario',
        instruccion:
            'Datos del responsable. Se completan automáticamente con los datos '
            'del usuario.',
        icono: Icons.badge_outlined,
        builder: (c, loc, _) => EdanPage13(localidad: loc),
        // --- Página 13: texto de la guía interactiva ---
        tituloAyuda: 'Responsable',
        consejosAyuda: const [
          'Los datos del responsable se completan automáticamente con tu '
              'usuario.',
          'Verifica que nombre y cargo estén correctos; si faltan, complétalos '
              'para poder enviar el formulario.',
        ],
      ),
    );

    // --- Resumen: texto de la guía interactiva ---
    pages.add(
      _WizardPage(
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
        tituloAyuda: 'Resumen y envío',
        consejosAyuda: const [
          'Revisa el resumen por secciones: las completadas se ven en verde y '
              'las pendientes se señalan.',
          'Puedes volver a cualquier sección desde el indicador superior para '
              'modificar datos.',
          'Solo aquí puedes enviar el formulario. Al presionar "Enviar", pasa a '
              'estado "Enviado UGR".',
        ],
      ),
    );

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
      map[p.key] = _seccionCompleta(p.key);
    }
    return map;
  }

  bool _seccionCompleta(String key) {
    // La página intro se considera completa cuando el EDAN tiene los datos
    // mínimos (nombre + tipo de evento), igual que el valida original (§9.20).
    if (key == 'intro') {
      return _localidad.nombre.trim().isNotEmpty &&
          _localidad.idTipoEvento != null;
    }
    if (key == 'resumen') return false;
    // Completitud por DATOS REALES (misma regla que el resumen §9.7):
    // los flags imp_* de page01 NO son suficientes; se exige por lo menos un
    // dato real en la sección y (03/04/07/10) que la suma de personas no
    // supere el total de población afectada (§9.19).
    return EdanResumenPage.calcularSeccionesCompletas(_localidad)[key] ?? false;
  }

  Widget _intro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Icon(
          Icons.assessment_outlined,
          size: 64,
          color: PaletteScope.of(context).primary,
        ),
        const SizedBox(height: 16),
        const Text(
          'Formulario EDAN',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          _introTexto,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PaletteScope.of(context).primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: PaletteScope.of(context).primary.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.save_outlined,
                size: 22,
                color: PaletteScope.of(context).primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Si crea el EDAN y no lo completa, guárdelo presionando el '
                  'ícono de guardar en la parte superior.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w800,
                    color: PaletteScope.of(context).primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PaletteScope.of(context).primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: PaletteScope.of(context).primary.withValues(alpha: 0.2),
            ),
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reconstruyendo = false,
    );
  }

  /// Lee `localidad_secciones_activas` en SQLite y sobreescribe los flags
  /// del modelo. Se llama al abrir un borrador existente para que las páginas
  /// del wizard reflejen exactamente lo que está guardado.
  Future<void> _sincronizarFlagsDesdeSeccionesActivas() async {
    final idLocal = _localidad.idLocal;
    if (idLocal == null) return;

    // Leer secciones activas (checkboxes de page01). Si no hay,
    // no reemplazamos arrays desde SQLite: datos_json ya tiene el
    // estado correcto y las flags provienen del modelo directamente.
    final activas = await _db.leerSeccionesActivas(idLocal);
    if (activas.isEmpty || !mounted) return;

    // Recargar arrays desde SQLite solo para secciones activas.
    // Si el usuario quitó items del array 1:N, el modelo en
    // datos_json podría tener items fantasma; SQLite es la fuente
    // canonical gracias al cleanup en guardarSecciones.
    final sincV2 = EdanLocalidadesEnvioV2Service();
    await sincV2.cargarSeccionesDesdeSQLite(
      _localidad,
      soloLasActivas: activas,
    );

    final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas(activas);
    _localidad
      ..impPoblacion = flags['imp_poblacion'] ?? _localidad.impPoblacion
      ..impSalud = flags['imp_salud'] ?? _localidad.impSalud
      ..impInfraestructura =
          flags['imp_infraestructura'] ?? _localidad.impInfraestructura
      ..impServicios = flags['imp_servicios'] ?? _localidad.impServicios
      ..impEducacion = flags['imp_educacion'] ?? _localidad.impEducacion
      ..impVivienda = flags['imp_vivienda'] ?? _localidad.impVivienda
      ..impAgropecuario =
          flags['imp_agropecuario'] ?? _localidad.impAgropecuario
      ..impProteccion = flags['imp_proteccion'] ?? _localidad.impProteccion
      ..impNecesidades = flags['imp_necesidades'] ?? _localidad.impNecesidades
      ..impImpactoPoblacion =
          flags['imp_impacto_poblacion'] ?? _localidad.impImpactoPoblacion
      ..impPrimeraRespuesta =
          flags['imp_primera_respuesta'] ?? _localidad.impPrimeraRespuesta
      ..impSaludEstablecimientos =
          flags['imp_salud_establecimientos'] ??
          _localidad.impSaludEstablecimientos
      ..impNecesidadSalud =
          flags['imp_necesidad_salud'] ?? _localidad.impNecesidadSalud
      ..impDanosViales = flags['imp_danos_viales'] ?? _localidad.impDanosViales
      ..impDanosInfraPublica =
          flags['imp_danos_infra_publica'] ?? _localidad.impDanosInfraPublica
      ..impServiciosBasicos =
          flags['imp_servicios_basicos'] ?? _localidad.impServiciosBasicos
      ..impUnidadesEducativas =
          flags['imp_unidades_educativas'] ?? _localidad.impUnidadesEducativas
      ..impDanosVivienda =
          flags['imp_danos_vivienda'] ?? _localidad.impDanosVivienda
      ..impDanosAgricultura =
          flags['imp_danos_agricultura'] ?? _localidad.impDanosAgricultura
      ..impDanosPecuarios =
          flags['imp_danos_pecuarios'] ?? _localidad.impDanosPecuarios
      ..impInfraProductiva =
          flags['imp_infra_productiva'] ?? _localidad.impInfraProductiva
      ..impNecesidadHumanitaria =
          flags['imp_necesidad_humanitaria'] ??
          _localidad.impNecesidadHumanitaria;

    // Reconstruye las paginas con los flags actualizados desde SQLite.
    rebuild();
  }

  Future<void> _next() async {
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
        await _db.marcarSeccionesModificadas(_localidad.idLocal!, rutasGuardar);
      } else if (token != null) {
        final id = await _db.insertLocalidad(
          _localidad,
          usuarioId: token.userId,
        );
        _localidad.idLocal = id;
        final seccionesAActivar = _seccionesDesdeFlags();
        if (seccionesAActivar.isNotEmpty) {
          await _db.activarSecciones(id, seccionesAActivar);
        }
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
      _estados.add(
        EdanSeccionEstado(
          seccionId: seccionKey,
          guardadaLocal: true,
          pendienteEnvio: true,
          fechaGuardado: DateTime.now(),
        ),
      );
    }
  }

  /// Deriva las rutas de sección activas a partir de los flags
  /// actuales del modelo (checkboxes de page01). Se usa para poblar
  /// `localidad_secciones_activas` cuando `activarSecciones` se
  /// saltó al inicio porque idLocal era null.
  List<String> _seccionesDesdeFlags() {
    final result = <String>{};
    if (_localidad.impPoblacion) {
      result.addAll(['impacto-poblacion', 'primera-respuesta']);
    }
    if (_localidad.impSalud) {
      result.addAll(['salud-establecimientos', 'necesidad-salud']);
    }
    if (_localidad.impInfraestructura) {
      result.addAll(['danos-viales', 'danos-infra-publica']);
    }
    if (_localidad.impServicios) result.add('servicios-basicos');
    if (_localidad.impEducacion) result.add('unidades-educativas');
    if (_localidad.impVivienda) result.add('danos-vivienda');
    if (_localidad.impAgropecuario) {
      result.addAll([
        'danos-agricultura',
        'danos-pecuarios',
        'infra-productiva',
      ]);
    }
    if (_localidad.impProteccion) result.add('proteccion');
    if (_localidad.impNecesidades) result.add('necesidad-humanitaria');
    return result.toList();
  }

  /// Claves automáticas/de sincronización que el usuario nunca edita. No deben
  /// contar como cambios reales: pueden variar al recargar desde SQLite, al
  /// reutilizar ids de catálogo (protección/impacto) o al navegar por las
  /// páginas (p.ej. Page10 rellena `id_grupo_vulnerable_catalogo`).
  static const List<String> _clavesVolatiles = [
    'fecha_modificacion',
    'pendiente_actualizacion',
    'pendiente_eliminacion',
    'id_edan_localidad_estado',
    'id_local',
    'id_seccion',
    'id_grupo_vulnerable_catalogo',
  ];

  /// Normaliza recursivamente la serialización de la localidad para detectar
  /// cambios REALES del usuario, eliminando en cualquier profundidad las claves
  /// volátiles de sync/automáticas. Los placeholders de Page03 (grupos etarios
  /// sembrados sin marcar) ni se serializan en `toApiJson()` (solo entran los
  /// marcados o con datos), así que no afectan la comparación ni la duplicidad
  /// de `id_seccion` (que solo se genera al guardar).
  Map<String, dynamic> _snapshotComparable(EdanLocalidad localidad) {
    final json = localidad.toApiJson();
    return _normalizarNodo(json) as Map<String, dynamic>;
  }

  dynamic _normalizarNodo(dynamic valor) {
    if (valor is Map) {
      final salida = <String, dynamic>{};
      valor.forEach((clave, sub) {
        if (clave is String && _clavesVolatiles.contains(clave)) return;
        salida[clave.toString()] = _normalizarNodo(sub);
      });
      return salida;
    }
    if (valor is List) {
      return valor.map(_normalizarNodo).toList();
    }
    return valor;
  }

  bool _huboCambios() {
    if (!_snapshotListo) return false;
    final inicial = _snapshotInicial;
    if (inicial == null) return false;
    final actual = _snapshotComparable(_localidad);
    return jsonEncode(inicial) != jsonEncode(actual);
  }

  bool _esEdanVacio() {
    return _localidad.nombre.trim().isEmpty || _localidad.idTipoEvento == null;
  }

  /// Guarda a SQLite y, si hay conexión, intenta el envío inmediato al
  /// servidor (secciones v2 + fotos). Mantiene la localidad en estado BORRADOR
  /// (no toca `estadoLocalidad`/`idEdanLocalidadEstado`; el estado solo cambia
  /// a Enviado UGR cuando el usuario pulsa "Enviar" en el resumen).
  ///
  /// Solo intenta el envío cuando el snapshot detecta cambios reales y hay
  /// Guarda a SQLite SIN salir (botón de la AppBar). Si se invoca desde
  /// "Guardar y salir", se suprime su snackbar interno para no duplicar la
  /// confirmación que muestra la pantalla padre.
  Future<void> _guardarSinSalir({bool mostrarSnackBar = true}) async {
    if (_saving) return;
    if (_esEdanVacio()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se puede guardar un EDAN vacío. Complete al menos el nombre de la localidad y el tipo de evento.',
            ),
            backgroundColor: Color(0xFFD32F2F),
          ),
        );
      }
      return;
    }
    setState(() => _saving = true);
    await _guardar(_pages[_currentPage].key);
    setState(() => _saving = false);
    if (!mounted || !mostrarSnackBar) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Borrador guardado')));
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
              ? 'Tiene cambios sin guardar.'
              : 'No se realizaron ningún cambio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: const Text('Cancelar'),
          ),
          if (hayCambios) ...[
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'salir'),
              child: const Text('Salir sin guardar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'guardar'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
              ),
              child: const Text('Guardar y salir'),
            ),
          ] else
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'salir'),
              child: const Text('Salir'),
            ),
        ],
      ),
    );

    if (!mounted) return;
    switch (salir) {
      case 'guardar':
        await _guardarSinSalir(mostrarSnackBar: false);
        _salirPermitido(guardado: true);
        break;
      case 'salir':
        _salirPermitido();
        break;
      default:
        break;
    }
  }

  /// Sale del wizard. El pop devuelve `true` solo si realmente se guardó o
  /// envió el formulario; si se sale sin guardar nada devuelve `false` para que
  /// la pantalla padre no muestre la alerta "Reporte guardado correctamente"
  /// ni recargue la lista.
  void _salirPermitido({bool guardado = false}) {
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.pop(context, guardado);
  }

  Future<void> _enviar() async {
    if (_saving) return;

    // Diálogo de confirmación: declaración jurada + revisión UGR
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Color(0xFFF59E0B),
        ),
        title: const Text('Confirmar envío'),
        content: const Text(
          'La información será revisada para análisis. '
          'Corresponde hacer el documento legal del EDAN municipal '
          'por parte del UGR.\n\n'
          'Es información con declaración jurada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

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
        content: Text(
          !conectado
              ? 'Formulario enviado a UGR (sin conexión; se sincronizará después)'
              : 'Formulario enviado a UGR',
        ),
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
        body: Stack(
          children: [
            Column(
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
                      setState(() => _currentPage = i);
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
                                onAyuda:
                                    kAyudasHabilitadas &&
                                        (p.habilitarAyuda ?? true)
                                    ? () => _mostrarAyuda(context, p)
                                    : null,
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
                  onEnviar:
                      ((_localidad.estadoLocalidad ==
                                  UgrLocalidadEstado.borrador ||
                              _localidad.estadoLocalidad ==
                                  UgrLocalidadEstado.rechazadoUgr) &&
                          EdanResumenPage.formularioCompleto(_localidad))
                      ? _enviar
                      : null,
                ),
              ],
            ),
            Positioned(
              bottom: 80,
              right: 16,
              child: AsistenteIaFormFab(
                pageTitle: page.titulo,
                pageKey: page.key,
              ),
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

  /// Abre la guía interactiva de la sección. Personaje 35% del ancho de
  /// pantalla. Usa el `tituloAyuda` y los `consejosAyuda` propios de cada
  /// página; si no están definidos, cae a la instrucción de la sección.
  void _mostrarAyuda(BuildContext ctx, _WizardPage p) {
    if (!kAyudasHabilitadas || (p.habilitarAyuda ?? true) == false) return;
    final personaje =
        kPersonajeImagenes[Random().nextInt(kPersonajeImagenes.length)];
    TutorialGuide.of(ctx)
      ..setPersonajeImagen(personaje)
      ..setTamanoPersonajeFactor(0.40)
      // La flecha se apoya en el blanco propio del PNG (sin tocar la figura).
      ..setMargenesImagen(derecha: 0)
      ..setMargenesImagen(izquierda: 24)
      ..setPosicion(TutorialPosition.centerLeft)
      ..setDireccion(TutorialDirection.right)
      ..setTitulo(p.tituloAyuda ?? '¿Cómo llenar "${p.titulo}"?')
      ..setConsejos(p.consejosAyuda ?? [p.instruccion])
      ..setVisibilidad(const Duration(seconds: 8))
      ..show();
  }
}
