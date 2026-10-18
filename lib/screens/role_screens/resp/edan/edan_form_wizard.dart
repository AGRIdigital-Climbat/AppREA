import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../providers/reporte_provider.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/database_helper.dart';
import '../../../../services/api/edan_api_v2.dart';
import '../../../../services/permission_service.dart';
import '../../../../services/sync/edan_sync_engine_v2.dart';
import '../../../../services/edan/edan_envio_v2.dart';
import '../../../../services/edan/edan_localidades_envio_v2_service.dart';
import '../../../../services/edan/edan_store_v2.dart';
import '../../../../services/edan_secciones_registry.dart';
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

  /// Store V2 opcional. Cuando se inyecta (rol RESP), el wizard persiste y
  /// carga las secciones vía [EdanStoreV2] (tablas `formularios` /
  /// `filas_seccion` / `viviendas`). Si es `null` (UGR/IA o llamadores sin
  /// inyección), se mantiene el comportamiento Legacy actual (§3.2 del plan).
  final EdanStoreV2? storeV2;

  const EdanFormWizard({super.key, this.edanAEditar, this.storeV2});

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

  /// Último motivo de fallo de `_guardar` (causa real, no el genérico).
  /// Se muestra en el snackbar y queda en el log para diagnóstico.
  String? _ultimoErrorGuardado;

  /// Grupos (checkboxes de page01) que determinan qué secciones muestra el
  /// wizard. Para un **formulario nuevo** salen de lo que tildó el usuario;
  /// al **reabrir** un borrador se recalculan desde la auxiliar v31 ∪ las
  /// secciones que tienen datos reales (Fase 4).
  ///
  /// Es la matriz [EdanSeccionesRegistry.matrizGrupoSecciones] en una sola
  /// dimensión: `grupo → rutas` se resuelve con `rutasDesdeGrupos`, y el
  /// inverso con `gruposDesdeActivas`.
  Set<String> _grupos = {};

  /// Store V2 inyectado (solo RESP). Si es `null`, se usa el camino Legacy.
  EdanStoreV2? get _storeV2 => widget.storeV2;

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
    _grupos = _gruposDesdeModelo();
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
  /// siguiente, con la comparación ya normalizada. Si es un borrador en
  /// edición, además navega a la primera página aún incompleta para que el
  /// usuario retome donde se quedó.
  Future<void> _prepararSnapshot() async {
    try {
      await _sincronizarFlagsDesdeSeccionesActivas();
    } catch (e) {
      debugPrint('EdanFormWizard._prepararSnapshot error: $e');
    }
    // Baseline con `imp` derivados de los datos cargados: así una derivación
    // posterior (resumen/guardar) no genera falsos "cambios".
    _localidad.recalcularImpDesdeListas();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _snapshotInicial = _snapshotComparable(_localidad);
      _snapshotListo = true;
      if (widget.edanAEditar != null) {
        _irAPrimeraPaginaIncompleta();
      }
    });
  }

  /// Navega a la primera página (excluyendo intro/resumen) que aún no está
  /// completa según [_seccionCompleta]. Si todo está completo no hace nada.
  void _irAPrimeraPaginaIncompleta() {
    for (var i = 0; i < _pages.length; i++) {
      final key = _pages[i].key;
      if (key == 'intro' || key == 'resumen') continue;
      if (!_seccionCompleta(key)) {
        if (i != _currentPage) _irA(i);
        return;
      }
    }
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

  /// Grupos tildados según los flags gruesos del modelo. Es la lectura
  /// "adelante" de la matriz para un formulario nuevo; al reabrir un borrador
  /// la reemplaza [_gruposDesdeAuxiliar].
  Set<String> _gruposDesdeModelo() {
    final l = _localidad;
    return {
      if (l.grupPoblacion) 'grupPoblacion',
      if (l.grupSalud) 'grupSalud',
      if (l.grupInfraestructura) 'grupInfraestructura',
      if (l.grupServicios) 'grupServicios',
      if (l.grupEducacion) 'grupEducacion',
      if (l.grupVivienda) 'grupVivienda',
      if (l.grupAgropecuario) 'grupAgropecuario',
      if (l.grupProteccion) 'grupProteccion',
      if (l.grupNecesidades) 'grupNecesidades',
    };
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
          onCambio: _refrescarBloqueos,
          store: _storeV2,
        ),
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
        builder: (c, loc, _) =>
            EdanPage02(localidad: loc, onCambio: _refrescarBloqueos),
        tituloAyuda: 'Población damnificada',
        consejosAyuda: const [
          'Escribe los totales estimados de familias damnificadas, familias '
              'afectadas y población total afectada.',
          'Ingresa solo números; al menos un total debe ser mayor a cero.',
        ],
      ),
    ];

    if (_grupos.contains('grupPoblacion')) {
      // --- Página 03: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '03',
          titulo: 'Impacto en la población',
          instruccion:
              'Registre el impacto por grupo etario y las necesidades de primera '
              'respuesta. Cada grupo tiene su propio ID.',
          icono: Icons.groups_outlined,
          builder: (c, loc, _) => EdanPage03(localidad: loc, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupSalud')) {
      // --- Página 04: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '04',
          titulo: 'Impacto en la salud',
          instruccion:
              'Registre los establecimientos de salud afectados y las necesidades '
              'de salud. Puede agregar varios establecimientos.',
          icono: Icons.local_hospital_outlined,
          builder: (c, loc, _) => EdanPage04(localidad: loc, store: _storeV2, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupInfraestructura')) {
      // --- Página 05: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '05',
          titulo: 'Impacto en infraestructuras',
          instruccion:
              'Registre daños en vías, puentes e infraestructura pública.',
          icono: Icons.location_city_outlined,
          builder: (c, loc, _) => EdanPage05(localidad: loc, store: _storeV2, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupServicios')) {
      // --- Página 06: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '06',
          titulo: 'Impacto en servicios básicos',
          instruccion:
              'Indique el estado de los servicios básicos (agua, luz, '
              'alcantarillado, gas, telecomunicaciones).',
          icono: Icons.home_work_outlined,
          builder: (c, loc, _) => EdanPage06(localidad: loc, store: _storeV2, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupEducacion')) {
      // --- Página 07: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '07',
          titulo: 'Impacto en educación',
          instruccion:
              'Registre unidades educativas afectadas, suspensión de clases y '
              'personal.',
          icono: Icons.school_outlined,
          builder: (c, loc, _) => EdanPage07(localidad: loc, store: _storeV2, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupVivienda')) {
      // --- Página 08: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '08',
          titulo: 'Impacto en viviendas',
          instruccion: 'Registre viviendas con daño parcial y total.',
          icono: Icons.home_outlined,
          builder: (c, loc, _) => EdanPage08(localidad: loc, store: _storeV2, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupAgropecuario')) {
      // --- Página 09: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '09',
          titulo: 'Impacto agropecuario',
          instruccion:
              'Registre daños en cultivos, pecuarios e infraestructura productiva. '
              'Cada ítem tiene su propio ID.',
          icono: Icons.agriculture_outlined,
          builder: (c, loc, _) => EdanPage09(localidad: loc, store: _storeV2, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupProteccion')) {
      // --- Página 10: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '10',
          titulo: 'Necesidades de protección',
          instruccion:
              'Registre la población vulnerable por sexo y la necesidad de apoyo '
              'psicológico.',
          icono: Icons.shield_outlined,
          builder: (c, loc, _) => EdanPage10(localidad: loc, onCambio: _refrescarBloqueos),
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
    if (_grupos.contains('grupNecesidades')) {
      // --- Página 11: texto de la guía interactiva ---
      pages.add(
        _WizardPage(
          key: '11',
          titulo: 'Necesidades humanitarias',
          instruccion: 'Marque las necesidades humanitarias de la localidad.',
          icono: Icons.volunteer_activism_outlined,
          builder: (c, loc, _) => EdanPage11(localidad: loc, onCambio: _refrescarBloqueos),
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
    // page01 muta los flags gruesos del modelo; las páginas se derivan de
    // [_grupos], así que se refresca desde el modelo antes de reconstruir.
    _grupos = _gruposDesdeModelo();
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

  /// Recalcula [bloqueos] (botón Siguiente) cuando una página hija muta
  /// datos en `_localidad`. A diferencia de [rebuild], **no** reconstruye
  /// [_pages] (la lista de páginas la construye solo page01) ni salta de
  /// página: solo dispara `setState` para que `build()` reevalúe el gate de
  /// la página actual. Coalescido en post-frame para que varias mutaciones
  /// en el mismo frame (p. ej. un diálogo que escribe varios campos) den un
  /// solo rebuild.
  bool _refrescandoBloqueos = false;
  void _refrescarBloqueos() {
    if (!mounted || _refrescandoBloqueos) return;
    _refrescandoBloqueos = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refrescandoBloqueos = false;
      if (mounted) setState(() {});
    });
  }

  /// Lee las secciones activas y sobreescribe los flags del modelo. Se llama
  /// al abrir un borrador existente para que las páginas del wizard reflejen
  /// exactamente lo que está guardado.
  ///
  /// **Escenarios que cubre**:
  /// * *Incompleto (editar)*: se **descifran los grupos** a partir de las
  ///   secciones realmente activas (auxiliar v31 ∪ filas con datos) con
  ///   [EdanSeccionesRegistry.gruposDesdeActivas], y así se pinta page01.
  /// * *Completo (leer)*: mismo camino de lectura; el usuario solo consulta.
  ///
  /// Con `storeV2` inyectado (RESP) la fuente de verdad es la tabla auxiliar
  /// `secciones_grupos_local` ∪ `filas_seccion`. Sin store (Legacy) se usa
  /// `localidad_secciones_activas` + las tablas `seccion_*`.
  Future<void> _sincronizarFlagsDesdeSeccionesActivas() async {
    final idLocal = _localidad.idLocal;
    final store = _storeV2;

    // ── Camino V2 (RESP): secciones_grupos_local ∪ filas_seccion ──
    if (store != null) {
      final uuid = _localidad.uuidEdanLocalidad ??
          (idLocal != null && idLocal.isNotEmpty ? idLocal : null);
      if (uuid != null) {
        var activas = await store.leerSeccionesActivas(uuid);
        // Sin auxiliar ni datos (borrador recién creado, o importado por un
        // pull), no se borra lo que el usuario ya tildó: se respeta el modelo.
        if (activas.isEmpty) activas = _seccionesDesdeFlags();

        // Derivación INVERSA de la matriz: los grupos de page01 salen de las
        // secciones activas, no de los flags del modelo (que pueden haber
        // quedado pisados por `recalcularFlagsImpacto` al guardar local).
        _aplicarFlagsDesdeActivas(activas);
        _grupos = EdanSeccionesRegistry.gruposDesdeActivas(activas);

        if (activas.isNotEmpty && mounted) {
          await store.cargarSecciones(_localidad, tipos: activas);
          rebuild();
        }
      }
      return;
    }

    // ── Camino Legacy (UGR/IA): localidad_secciones_activas + seccion_* ──
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

    _aplicarFlagsDesdeActivas(activas);
    _grupos = EdanSeccionesRegistry.gruposDesdeActivas(activas);

    // Reconstruye las paginas con los flags actualizados desde SQLite.
    rebuild();
  }

  /// Aplica al modelo los flags `imp_*` derivados de las rutas activas.
  /// Compartido por los caminos V2 y Legacy para que el mapeo de grupos
  /// (p.ej. `grupAgropecuario` → agricultura/pecuarios/infra-productiva)
  /// se resuelva igual en ambos.
  void _aplicarFlagsDesdeActivas(List<String> activas) {
    final flags = EdanSeccionesRegistry.construirFlagsDesdeActivas(activas);
    _localidad
      ..grupPoblacion = flags['grup_poblacion'] ?? _localidad.grupPoblacion
      ..grupSalud = flags['grup_salud'] ?? _localidad.grupSalud
      ..grupInfraestructura =
          flags['grup_infraestructura'] ?? _localidad.grupInfraestructura
      ..grupServicios = flags['grup_servicios'] ?? _localidad.grupServicios
      ..grupEducacion = flags['grup_educacion'] ?? _localidad.grupEducacion
      ..grupVivienda = flags['grup_vivienda'] ?? _localidad.grupVivienda
      ..grupAgropecuario =
          flags['grup_agropecuario'] ?? _localidad.grupAgropecuario
      ..grupProteccion =
          flags['grup_proteccion'] ?? _localidad.grupProteccion
      ..grupNecesidades = flags['grup_necesidades'] ?? _localidad.grupNecesidades
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
      ..impProteccion = flags['imp_proteccion'] ?? _localidad.impProteccion
      ..impNecesidadHumanitaria =
          flags['imp_necesidad_humanitaria'] ??
          _localidad.impNecesidadHumanitaria;
  }

  Future<void> _next() async {
    _irA(_currentPage + 1);
  }

  /// Guarda en SQLite las secciones de [seccionKey].
  ///
  /// Con [guardarTodasActivas] (usado por el botón de la AppBar, "Guardar y
  /// salir" y "Enviar") persiste TODAS las secciones activadas por los flags
  /// de page01, no solo las de la página actual. Así, si el usuario llenó
  /// varias páginas y guarda desde una sola, las demás no se pierden al
  /// reabrir el borrador.
  Future<bool> _guardar(
    String seccionKey, {
    bool guardarTodasActivas = false,
  }) async {
    final token = AuthService.instance.currentToken;
    final envio = EdanLocalidadesEnvioV2Service();
    try {      // Determinar rutas: la página actual, o TODAS si es resumen/página sin
      // mapa. Con guardarTodasActivas se usan las secciones activadas por flags.
      final rutasPagina = EdanSeccionesRegistry.rutasDePagina(seccionKey);
      final List<String> rutasGuardar;
      if (guardarTodasActivas) {
        final activas = _seccionesDesdeFlags();
        rutasGuardar = activas.isNotEmpty
            ? activas
            : (rutasPagina.isEmpty
                ? EdanSeccionesRegistry.rutasV2Todas()
                : rutasPagina);
      } else {
        rutasGuardar = rutasPagina.isEmpty
            ? EdanSeccionesRegistry.rutasV2Todas()
            : rutasPagina;
      }

      if (_huboCambios()) {
        _localidad.editado = true;
      }

      // `imp` = datos del momento (grup NO se toca: manda page01). Así el
      // snapshot `datos_json`, el payload y el resumen cuentan lo mismo.
      _localidad.recalcularImpDesdeListas();

      final store = _storeV2;
      if (store != null) {
        // ── Camino V2 (RESP): solo tablas V2 (Etapa 5: sin doble-escritor).
        // El uuid nace en `_ensureUuid` (reutiliza el idLocal al reabrir un
        // borrador legacy) y el listado unificado lo encuentra por uuid.
        final seccionesActivas = _seccionesDesdeFlags();
        await store.guardarTodo(
          _localidad,
          usuarioId: token?.userId ?? 0,
          seccionesActivas: seccionesActivas,
          tipos: rutasGuardar,
          // Guardado completo (AppBar/"Guardar y salir"/"Enviar"): purga las
          // filas de grupos destildados. En guardados parciales NO (el modelo
          // puede no tener cargadas esas secciones).
          purgarInactivas: guardarTodasActivas,
        );
      } else if (_localidad.idLocal != null) {
        // ── Camino Legacy (UGR/IA): localidades_offline + seccion_* ──
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
      // El guardado exitoso redefine "sin cambios": se refresca el baseline
      // para que volver atrás no ofrezca "Guardar y salir" sin haber tocado
      // nada después (el modelo mutó: uuids asignados, imp derivados, etc.).
      _snapshotInicial = _snapshotComparable(_localidad);
      _snapshotListo = true;
      _ultimoErrorGuardado = null;
      return true;
    } catch (e) {
      _ultimoErrorGuardado = '$e';
      debugPrint('EdanFormWizard._guardar error: $e');
      return false;
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

  /// Deriva las rutas de sección activas a partir de [_grupos] (los
  /// checkboxes de page01). La fuente única es
  /// [EdanSeccionesRegistry.matrizGrupoSecciones], así que el wizard nunca
  /// puede divergir de lo que se pintó en page01.
  ///
  /// Antes era una lista de `if` codificada a mano que podía desincronizarse
  /// de la matriz; ahora es su proyección directa.
  List<String> _seccionesDesdeFlags() =>
      EdanSeccionesRegistry.rutasDesdeGrupos(_grupos).toList();

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
    try {
      final actual = _snapshotComparable(_localidad);
      return jsonEncode(inicial) != jsonEncode(actual);
    } catch (_) {
      // Si no se puede comparar (NaN GPS, objeto raro), se asume que SÍ hay
      // cambios: dirección segura (guardar de más, nunca perder).
      return true;
    }
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
  ///
  /// Devuelve `true` solo si realmente guardó: el llamador ("Guardar y
  /// salir") NO debe cerrar el wizard cuando el guardado falló o fue
  /// rechazado por vacío (antes salía igual y el usuario creía que guardó).
  Future<bool> _guardarSinSalir({bool mostrarSnackBar = true}) async {
    if (_saving) return false;
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
      return false;
    }
    setState(() => _saving = true);
    final ok = await _guardar(_pages[_currentPage].key, guardarTodasActivas: true);
    setState(() => _saving = false);
    if (!mounted) return false;
    if (!ok) {
      final causa = _ultimoErrorGuardado;
      final texto = causa == null || causa.isEmpty
          ? 'No se pudo guardar el formulario. Intentá de nuevo.'
          : 'No se pudo guardar: $causa';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 8),
          action: causa == null || causa.isEmpty
              ? null
              : SnackBarAction(
                  label: 'Copiar',
                  textColor: Colors.white,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: causa));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Error copiado al portapapeles'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
        ),
      );
      return false;
    }
    if (!mostrarSnackBar) return true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Borrador guardado')));
    return true;
  }

  /// Pregunta al usuario antes de salir del formulario (atrás/gesto del sistema).
  ///
  /// Si NO hay cambios sale directo sin diálogo (antes mostraba un diálogo
  /// informativo que solo pedía un tap extra). Si los hay, ofrece salir sin
  /// guardar o "Guardar y salir", y solo cierra si realmente se guardó (un
  /// guardado fallido o rechazado por vacío NO cierra el wizard).
  Future<void> _confirmarSalir() async {
    final hayCambios = _huboCambios();
    if (!hayCambios) {
      _salirPermitido();
      return;
    }
    final salir = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir del formulario?'),
        content: const Text('Tiene cambios sin guardar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: const Text('Cancelar'),
          ),
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
        ],
      ),
    );

    if (!mounted) return;
    switch (salir) {
      case 'guardar':
        // Solo se sale si realmente se guardó: si el guardado falla o el
        // formulario está vacío, el usuario se queda con el motivo visible
        // (antes salía igual y creía que había guardado).
        if (await _guardarSinSalir(mostrarSnackBar: false)) {
          _salirPermitido(guardado: true);
        }
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
    final guardado = await _guardar(
      _pages[_currentPage].key,
      guardarTodasActivas: true,
    );
    if (!guardado) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el formulario. No se envió.'),
            backgroundColor: Color(0xFFD32F2F),
          ),
        );
      }
      return;
    }

    // Enviar a UGR. Camino V2 (RESP, `storeV2` inyectado): UNA llamada por
    // `POST /formularios/completo` que —a diferencia del `sincronizar()`
    // anterior— escribe el estado destino DIRECTAMENTE en `formularios`, la
    // tabla de la que `prepararPayloadCompleto` arma el payload. Antes el estado
    // se grababa en `localidades_offline` (tabla legacy) y el POST seguía
    // enviando `id_edan_localidad_estado = 1` (borrador): el servidor guardaba
    // borrador y al re-login el reporte volvía como borrador. Camino legacy
    // (UGR/IA, sin storeV2): se conserva el sincronizador V2 previo.
    final uuid = _localidad.uuidEdanLocalidad;
    final esV2 = _storeV2 != null && uuid != null && uuid.isNotEmpty;
    final conectado = await ConnectivityService().checkNow();

    // La intención de envío se registra SIEMPRE (con o sin red): si el push
    // inmediato falla o no hay conexión, el próximo `sincronizar()` aplica el
    // estado destino. Sin esto, un "Enviar" offline se sincronizaba como
    // borrador y la intención se perdía.
    if (esV2 && uuid.isNotEmpty) {
      try {
        await _storeV2!.marcarEnvioPendiente(
          uuid,
          UgrLocalidadEstado.enviadoUgr.id,
        );
      } catch (e) {
        debugPrint('EdanFormWizard: no se pudo registrar envío pendiente: $e');
      }
    }

    var enviado = false;
    if (conectado) {
      if (esV2) {
        enviado = await EdanEnvioV2.enviar(
          _localidad,
          idEdanLocalidadEstado: UgrLocalidadEstado.enviadoUgr.id,
        );
      } else {
        Directory? dirFotos;
        try {
          final appDir = await getApplicationDocumentsDirectory();
          dirFotos = Directory('${appDir.path}/edan_fotos');
        } catch (_) {
          dirFotos = null;
        }
        final resumen = await EdanSyncEngineV2(
          api: EdanApiV2(),
          dirFotos: dirFotos,
        ).sincronizar();
        enviado = resumen.exito;
      }
    }

    if (enviado) {
      _localidad
        ..idEdanLocalidadEstado = UgrLocalidadEstado.enviadoUgr.id
        ..estadoLocalidad = UgrLocalidadEstado.enviadoUgr
        ..editado = false
        ..sincronizado = true;
      // El motor ya subió formulario + secciones + fotos: marcar
      // `formularios.estado_local = 'enviado'`. No se purga la cola a mano:
      // el motor limpia `cola_fotos` y `cola_sincronizacion` al confirmar
      // cada ítem, así no se pierden fotos aún no subidas.
      if (esV2 && uuid.isNotEmpty) {
        await _storeV2!.marcarEnviado(uuid);
      }
      // Diseño limpio: el contador de pendientes es el del store V2.
      await _storeV2?.refrescarPendientes();
    } else {
      // Sin confirmación del servidor: se mantiene BORRADOR (no se miente) y
      // `pendiente_push = 1`, para que el próximo `sincronizar()` lo reintente.
      _localidad.editado = true;
    }
    // El espejo legacy solo existe en el camino sin store (UGR/IA). En V2 el
    // estado ya quedó en `formularios` vía el motor.
    if (!esV2 && _localidad.idLocal != null) {
      await _db.updateLocalidad(_localidad);
    }

    setState(() => _saving = false);
    if (!mounted) return;
    // TEMP DIAG (borrar): mostrar el motivo real del fallo mientras se depura
    // el bug de `danos_agricultura` (status HTTP + detail del servidor).
    final diag = enviado ? null : EdanEnvioV2.ultimoErrorDiagnostico;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enviado
              ? 'Formulario enviado a UGR'
              : !conectado
                  ? 'Sin conexión: guardado como pendiente, se enviará al sincronizar'
                  : 'No se pudo enviar; quedó pendiente para reintentar'
                      '${diag != null ? ' · $diag' : ''}',
        ),
        backgroundColor: enviado ? null : const Color(0xFFF59E0B),
      ),
    );
    setState(() => _allowPop = true);
    Navigator.pop(context, true);
  }

  void _irA(int index) {
    if (index < 0 || index >= _pages.length) return;
    // Al entrar al resumen, los `imp_*` reflejan los datos del momento
    // (grup manda para visibilidad; imp = tiene-datos-ahora). Sin esto el
    // resumen mostraba vacío en registros nuevos (imp siempre false).
    if (_pages[index].key == 'resumen') {
      _localidad.recalcularImpDesdeListas();
    }
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
    // Siguiente obligatorio por página: en cabecera 01/02, todos los campos
    // asteriscados (y ≥1 casilla en page01); en secciones, por grupo marcado:
    // 1:1 completa y ≥1 hija válida en alguna 1:N. Con bloqueos el botón se
    // apaga con tooltip de lo que falta. La barra superior sigue con salto
    // libre (no se toca).
    final bloqueos = esResumen
        ? const <String>[]
        : [
            ...EdanSeccionesRegistry.bloqueosCamposPagina(
                _localidad, page.key),
            ...EdanSeccionesRegistry.bloqueosSiguiente(
                _localidad, EdanSeccionesRegistry.rutasDePagina(page.key)),
          ];

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
                    // Con bloqueos el swipe queda cerrado (solo el botón
                    // Siguiente decide avanzar); la barra superior sigue
                    // libre. Sin bloqueos se desliza normal.
                    physics: bloqueos.isEmpty
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
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
                  onNext: bloqueos.isEmpty ? _next : null,
                  nextTooltip: bloqueos.isEmpty
                      ? null
                      : bloqueos.length == 1
                          ? bloqueos.first
                          : 'Faltan datos por completar en esta página',
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
