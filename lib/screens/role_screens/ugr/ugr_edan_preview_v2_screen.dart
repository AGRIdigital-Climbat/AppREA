import 'dart:io';

import 'package:flutter/material.dart';
import '../../../config/api_config.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../models/usuario.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';
import 'crear_usuario_screen.dart';
import 'ugr_route.dart';

class UgrEdanPreviewV2Screen extends StatefulWidget {
  final Edan edan;
  final bool soloLectura;
  final bool sinAlcalde;
  final bool cargarResponsableDeCache;
  final bool esConsolidado;

  const UgrEdanPreviewV2Screen({
    super.key,
    required this.edan,
    this.soloLectura = false,
    this.sinAlcalde = false,
    this.cargarResponsableDeCache = false,
    this.esConsolidado = false,
  });

  @override
  State<UgrEdanPreviewV2Screen> createState() => _UgrEdanPreviewV2ScreenState();
}

class _UgrEdanPreviewV2ScreenState extends State<UgrEdanPreviewV2Screen> {
  bool _guardando = false;
  bool _bannerExpanded = false;
  Usuario? _alcaldeSeleccionado;
  Future<List<Usuario>>? _alcaldesListFuture;

  Edan get edan => widget.edan;
  bool get soloLectura => widget.soloLectura;
  bool get sinAlcalde => widget.sinAlcalde;
  bool get esConsolidado => widget.esConsolidado;
  bool get _modoEdicionCabecera => !soloLectura && !sinAlcalde;

  void _cargarAlcaldes() {
    final municipioId = edan.idMunicipio;
    if (municipioId != null && ConnectivityService().isConnected) {
      _alcaldesListFuture = ApiService.instance.getUsuarios(
        idMunicipio: municipioId,
        idRol: 8,
      );
    } else {
      _alcaldesListFuture = Future.value(<Usuario>[]);
    }
  }

  void _confirmar(BuildContext context) {
    edan
      ..estado = 'enviado'
      ..idEstado = 1;
    Navigator.of(context).pop(edan);
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    edan.completarResponsableDesdeCache();
    for (final l in edan.localidades) {
      l.deduplicarSecciones();
    }
    final incompletos = edan.incompletosPorSeccion(exigirAlcalde: !sinAlcalde);

    final seccionesVisibles = <String>{
      '01',
      '13',
      if (edan.localidades.any((l) => l.impPoblacion)) '03',
      if (edan.localidades.any((l) => l.impSalud)) '04',
      if (edan.localidades.any((l) => l.impInfraestructura)) '05',
      if (edan.localidades.any((l) => l.impServicios)) '06',
      if (edan.localidades.any((l) => l.impEducacion)) '07',
      if (edan.localidades.any((l) => l.impVivienda)) '08',
      if (edan.localidades.any((l) => l.impAgropecuario)) '09',
      if (edan.localidades.any((l) => l.impProteccion)) '10',
      if (edan.localidades.any((l) => l.impNecesidades)) '11',
    };
    final incompletosVisibles = incompletos.keys
        .where((k) => seccionesVisibles.contains(k))
        .toList();
    return Scaffold(
      backgroundColor: PaletteScope.of(context).background,
      appBar: AppBar(
        title: const Text(
          'Vista previa del EDAN',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDocHeader(primary),
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
          const SizedBox(height: 12),
          _buildDeclaracion(),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            soloLectura
                ? SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(0, 56),
                      ),
                      child: const Text('Confirmar consolidación'),
                    ),
                  )
                : _modoEdicionCabecera
                    ? SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _guardando ? null : _guardarBorrador,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.divider,
                            disabledForegroundColor: AppColors.textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size(0, 56),
                          ),
                          child: _guardando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Guardar cambios'),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (incompletosVisibles.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.pending.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.pending),
                                      SizedBox(width: 6),
                                      Text(
                                        'Campos faltantes para enviar:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.pending,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ...incompletosVisibles.map((key) => Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: Text(
                                          '· Sección $key: ${incompletos[key]!.join(", ")}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      )),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (incompletosVisibles.isEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.aprobado.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.check_circle, size: 16, color: AppColors.aprobado),
                                  SizedBox(width: 6),
                                  Text(
                                    'Formulario completo y listo para enviar al UGR',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.aprobado,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primary,
                                    side: BorderSide(color: primary, width: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    minimumSize: const Size(0, 56),
                                  ),
                                  child: const Text('Volver y Editar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: incompletosVisibles.isEmpty
                                      ? () => _confirmar(context)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: AppColors.divider,
                                    disabledForegroundColor: AppColors.textSecondary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    minimumSize: const Size(0, 56),
                                  ),
                                  child: const Text('Confirmar y Enviar'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
            if (!soloLectura && edan.idEstado == 1 && edan.idEdan != null && esConsolidado) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _guardando ? null : _deshacerEdan,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Deshacer EDAN'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Business logic methods (identical to v1) ---

  Future<void> _registrarNuevoAlcalde(int municipioId) async {
    final nuevoId = await Navigator.of(context).push<int>(
      ugrRoute(CrearUsuarioScreen(
        idMunicipio: municipioId,
        idDepartamento: edan.idDepartamento,
        idProvincia: edan.idProvincia,
      )),
    );
    if (nuevoId != null && mounted) {
      if (!ConnectivityService().isConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
          );
        }
        return;
      }
      try {
        final u = await ApiService.instance.getUsuario(nuevoId);
        setState(() {
          edan
            ..idUsuarioAlcalde = u.idUsuario
            ..nombreAlcalde = u.nombre
            ..fonoAlcalde = u.celular ?? '';
          _alcaldeSeleccionado = u;
          _cargarAlcaldes();
        });
        await _guardarAlcalde();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al obtener datos del usuario: ${ApiService.traducirError(e)}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _asignarAlcaldeSeleccionado() async {
    if (_alcaldeSeleccionado == null) return;
    setState(() {
      edan
        ..idUsuarioAlcalde = _alcaldeSeleccionado!.idUsuario
        ..nombreAlcalde = _alcaldeSeleccionado!.nombre
        ..fonoAlcalde = _alcaldeSeleccionado!.celular ?? '';
      _bannerExpanded = false;
    });
    await _guardarAlcalde();
  }

  Future<void> _guardarAlcalde() async {
    final edanId = edan.idEdan ?? edan.idServer;
    if (edanId == null) return;
    if (edan.idUsuario != null && edan.idUsuario != AuthService.instance.userId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solo el creador puede editar este EDAN.'), backgroundColor: AppColors.pending),
        );
      }
      return;
    }
    if (!ConnectivityService().isConnected) {
      if (edan.idLocal != null) {
        await DatabaseHelper.instance.updateEdan(edan);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alcalde guardado localmente. Se sincronizará cuando haya conexión.'), backgroundColor: AppColors.pending),
          );
          setState(() {});
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
          );
        }
      }
      return;
    }
    setState(() => _guardando = true);
    try {
      await ApiService.instance.updateEdan(edanId, {
        'id_usuario_alcalde': edan.idUsuarioAlcalde,
        'nombre_alcalde': edan.nombreAlcalde,
        'fono_alcalde': edan.fonoAlcalde,
        'responsable': {
          'nombre': edan.nombreAlcalde,
          'fono': edan.fonoAlcalde,
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alcalde asignado correctamente'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardarBorrador() async {
    final edanId = edan.idEdan ?? edan.idServer;
    if (edanId == null) return;
    if (edan.idUsuario != null && edan.idUsuario != AuthService.instance.userId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solo el creador puede editar este EDAN.'), backgroundColor: AppColors.pending),
        );
      }
      return;
    }
    if (!ConnectivityService().isConnected) {
      if (edan.idLocal != null) {
        await DatabaseHelper.instance.updateEdan(edan);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Guardado localmente. Se sincronizará cuando haya conexión.'), backgroundColor: AppColors.pending),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
          );
        }
      }
      return;
    }
    setState(() => _guardando = true);
    try {
      await ApiService.instance.updateEdan(edanId, {
        'id_usuario_alcalde': edan.idUsuarioAlcalde,
        'nombre_alcalde': edan.nombreAlcalde,
        'fono_alcalde': edan.fonoAlcalde,
        'responsable': {
          'nombre': edan.nombreAlcalde,
          'fono': edan.fonoAlcalde,
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cambios guardados correctamente'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _deshacerEdan() async {
    final edanId = edan.idEdan;
    if (edanId == null) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deshacer EDAN'),
        content: Text(
          '¿Deshacer el EDAN ${edan.codigoEdan}? '
          'Se liberarán ${edan.localidades.length} localidad(es) '
          'y el EDAN será eliminado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Deshacer'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    if (!ConnectivityService().isConnected) {
      if (edan.idLocal != null) {
        await DatabaseHelper.instance.markEdanAsPendingDeletion(edan.idLocal!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('EDAN marcado para eliminar. Se procesará al sincronizar.'), backgroundColor: AppColors.pending),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
          );
        }
      }
      return;
    }
    setState(() => _guardando = true);
    try {
      await ApiService.instance.deshacerEdan(edanId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('EDAN deshecho correctamente. Localidades liberadas.'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al deshacer: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // --- Header ---

  Widget _buildDocHeader(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Text(
            'EVALUACIÓN EDAN',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'SINAGER-SAT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.reaFooterText,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              edan.codigoEdan.isEmpty
                  ? 'EDAN / ${DateTime.now().year}'
                  : edan.codigoEdan,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          if (edan.tipoEventoNombre != null &&
              edan.tipoEventoNombre!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              edan.tipoEventoNombre!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.reaFooterText,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _headerStat('Población', '${edan.totalPoblacionAfectada}'),
                Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.3)),
                _headerStat('Fam. Afectadas', '${edan.totalFamiliasAfectadas}'),
                Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.3)),
                _headerStat('Fam. Damnificadas', '${edan.totalFamiliasDamnificadas}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  // --- Secciones ---

  Widget _seccion01() {
    return _DocSeccion(
      numero: '01',
      titulo: 'Datos generales',
      children: [
        if (!sinAlcalde) _campoAlcaldeInline(),
        _kvGrid([
          _kv('Departamento', _v(edan.departamentoNombre)),
          _kv('Provincia', _v(edan.provinciaNombre)),
          _kv('Municipio', _v(edan.municipioNombre)),
          _kv('Fecha llenado', _v(edan.fechaLlenado)),
          _kv('Fecha evento', _v(edan.fechaEvento)),
          _kv('Hora evento', _v(edan.horaEvento)),
          _kv('Tipo de evento', _v(edan.tipoEventoNombre)),
          _kv('Lugares afectados',
              edan.localidadesAfectadas > 0 ? '${edan.localidadesAfectadas}' : '-'),
        ]),
        _subtitulo('Lugares (${edan.localidades.length})'),
        if (edan.localidades.isEmpty)
          _vacio()
        else
          ...edan.localidades.asMap().entries.map((entry) {
            final l = entry.value;
            return _kvGrid([
              _kv('Lugar', _v(l.etiquetaLugar)),
              if (_impactosLocalidad(l).isNotEmpty)
                _kv('Impactos', _impactosLocalidad(l).join(', ')),
            ]);
          }),
      ],
    );
  }

  List<String> _impactosLocalidad(EdanLocalidad l) {
    return [
      if (l.impPoblacion) 'Población',
      if (l.impSalud) 'Salud',
      if (l.impInfraestructura) 'Infraestructura',
      if (l.impServicios) 'Servicios básicos',
      if (l.impEducacion) 'Educación',
      if (l.impVivienda) 'Vivienda',
      if (l.impAgropecuario) 'Agropecuario',
      if (l.impProteccion) 'Protección',
      if (l.impNecesidades) 'Necesidades humanitarias',
    ];
  }

  Widget _campoAlcaldeInline() {
    final primary = PaletteScope.of(context).primary;
    final tieneAlcalde = (edan.nombreAlcalde).trim().isNotEmpty;
    final municipioId = edan.idMunicipio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _guardando
              ? null
              : () {
                  setState(() => _bannerExpanded = !_bannerExpanded);
                  if (_bannerExpanded && _alcaldesListFuture == null && municipioId != null) {
                    _cargarAlcaldes();
                  }
                },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tieneAlcalde
                  ? primary.withValues(alpha: 0.04)
                  : AppColors.pending.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: tieneAlcalde
                    ? primary.withValues(alpha: 0.2)
                    : AppColors.pending.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  tieneAlcalde ? Icons.person : Icons.person_off,
                  size: 18,
                  color: tieneAlcalde ? primary : AppColors.pending,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alcalde',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tieneAlcalde ? AppColors.textSecondary : AppColors.pending,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tieneAlcalde ? edan.nombreAlcalde : 'Sin alcalde asignado',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tieneAlcalde ? AppColors.textPrimary : AppColors.pending,
                        ),
                      ),
                      if (tieneAlcalde && (edan.fonoAlcalde).trim().isNotEmpty)
                        Text(
                          edan.fonoAlcalde,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                Icon(
                  _bannerExpanded ? Icons.keyboard_arrow_up : Icons.edit,
                  size: 18,
                  color: tieneAlcalde ? primary : AppColors.pending,
                ),
              ],
            ),
          ),
        ),
        if (_bannerExpanded) ...[
          const SizedBox(height: 8),
          if (_alcaldesListFuture != null)
            FutureBuilder<List<Usuario>>(
              future: _alcaldesListFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No se pudieron cargar los alcaldes. Toca para reintentar.',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  );
                }
                final alcaldes = snap.data ?? [];
                if (alcaldes.isEmpty) {
                  return _buildSinAlcalde(primary, municipioId!);
                }
                return _buildListaAlcaldes(alcaldes, primary, municipioId!);
              },
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildSinAlcalde(Color primary, int municipioId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Icon(Icons.person_off, size: 32, color: AppColors.pending),
          const SizedBox(height: 8),
          const Text(
            'No hay alcalde registrado para este municipio',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _guardando ? null : () => _registrarNuevoAlcalde(municipioId),
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('Registrar nuevo alcalde'),
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              side: BorderSide(color: primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaAlcaldes(List<Usuario> alcaldes, Color primary, int municipioId) {
    return Column(
      children: [
        ...alcaldes.map((a) {
          final isSelected = _alcaldeSeleccionado?.idUsuario == a.idUsuario;
          return GestureDetector(
            onTap: () {
              setState(() => _alcaldeSeleccionado = a);
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? primary.withValues(alpha: 0.1)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? primary : AppColors.divider,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isSelected
                        ? primary.withValues(alpha: 0.2)
                        : AppColors.divider,
                    child: Icon(
                      Icons.person,
                      size: 18,
                      color: isSelected ? primary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.nombre,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? primary : AppColors.textPrimary,
                          ),
                        ),
                        if ((a.celular ?? '').isNotEmpty)
                          Text(
                            a.celular!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if ((a.correo ?? '').isNotEmpty)
                          Text(
                            a.correo!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, size: 20, color: primary),
                ],
              ),
            ),
          );
        }),
        GestureDetector(
          onTap: _guardando ? null : () => _registrarNuevoAlcalde(municipioId),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: primary.withValues(alpha: 0.1),
                  child: Icon(Icons.add, size: 18, color: primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Registrar nuevo alcalde',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _bannerExpanded = false;
                    _alcaldeSeleccionado = null;
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: (_alcaldeSeleccionado == null || _guardando)
                    ? null
                    : _asignarAlcaldeSeleccionado,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.divider,
                  disabledForegroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text('Confirmar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _seccion02() {
    return _DocSeccion(
      numero: '02',
      titulo: 'Información total población afectada y damnificada',
      children: [
        _kvGrid([
          _kv('Población afectada',
              edan.totalPoblacionAfectada > 0 ? '${edan.totalPoblacionAfectada}' : '0'),
          _kv('Familias afectadas',
              edan.totalFamiliasAfectadas > 0 ? '${edan.totalFamiliasAfectadas}' : '0'),
          _kv('Familias damnificadas',
              edan.totalFamiliasDamnificadas > 0 ? '${edan.totalFamiliasDamnificadas}' : '0'),
        ]),
      ],
    );
  }

  Widget _seccion03() {
    final locs = edan.localidades.where((l) => l.impPoblacion).toList();
    return _DocSeccion(
      numero: '03',
      titulo: 'Impacto en la población',
      children: [
        _subtitulo('Impacto en la población'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ip = l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0] : null;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              if (ip != null) ...[
                _kvGrid([
                  _kv('Fallecidos', '${ip.fallecidos}'),
                  _kv('Heridos', '${ip.heridos}'),
                  _kv('Desaparecidos', '${ip.desaparecidos}'),
                ]),
                _tablaConScroll(
                  headers: ['Grupo etario', 'Fallecidos', 'Heridos', 'Desaparecidos', 'Obs.'],
                  rows: ip.gruposEtarios.map((g) => [
                    _v(g.rango),
                    '${g.fallecidos}',
                    '${g.heridos}',
                    '${g.desaparecidos}',
                    g.observaciones.trim().isNotEmpty ? g.observaciones : '-',
                  ]).toList(),
                  totals: _calcularTotalesPoblacion(ip.gruposEtarios),
                ),
              ],
            ]);
          }),
        _subtitulo('Necesidades primera respuesta'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final nr = entry.value.necesidadPrimeraRespuesta;
            return _bloqueLocalidad(i, entry.value.etiquetaLugar, [
              _tablaConScroll(
                headers: ['Necesidad', 'SI', 'NO'],
                rows: [
                  ['Búsqueda', nr?.busqueda == true ? '✓' : '', nr?.busqueda == false ? '✓' : ''],
                  ['Salvamento', nr?.salvamento == true ? '✓' : '', nr?.salvamento == false ? '✓' : ''],
                  ['Evacuación', nr?.evacuacion == true ? '✓' : '', nr?.evacuacion == false ? '✓' : ''],
                ],
              ),
              if (nr?.observaciones != null && nr!.observaciones.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones', nr.observaciones)]),
            ]);
          }),
      ],
    );
  }

  List<String>? _calcularTotalesPoblacion(List<EdanGrupoEtario> grupos) {
    int fallecidos = 0, heridos = 0, desaparecidos = 0;
    for (final g in grupos) {
      fallecidos += g.fallecidos;
      heridos += g.heridos;
      desaparecidos += g.desaparecidos;
    }
    if (fallecidos == 0 && heridos == 0 && desaparecidos == 0) return null;
    return ['TOTAL', '$fallecidos', '$heridos', '$desaparecidos', ''];
  }

  bool get _aplicaNecesidadesSalud {
    final t = (edan.tipoEventoNombre ?? '')
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

  Widget _seccion04() {
    final locs = edan.localidades.where((l) => l.impSalud).toList();
    return _DocSeccion(
      numero: '04',
      titulo: 'Impacto en la salud',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ns = l.necesidadSalud;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _subtitulo('Daños en servicios de salud (${l.establecimientosSalud.length})'),
              if (l.establecimientosSalud.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['N°', 'Nombre', 'Comunidad', 'Nivel', 'Daño P', 'Daño T', 'Médicos', 'Enfermeras', 'Otros'],
                  rows: l.establecimientosSalud.asMap().entries.map((e) => [
                    '${e.key + 1}',
                    _v(e.value.nombreEstablecimiento),
                    _v(e.value.comunidad),
                    _v(e.value.nivelAtencion),
                    e.value.danoParcial ? '✓' : '',
                    e.value.danoTotal ? '✓' : '',
                    '${e.value.medicosAfectados}',
                    '${e.value.enfermerasAfectados}',
                    '${e.value.otrosAfectados}',
                  ]).toList(),
                  totals: _calcularTotalesSalud(l.establecimientosSalud),
                ),
              if (_aplicaNecesidadesSalud) ...[
                _subtitulo('Necesidades en salud'),
                _tags([if (ns?.botiquines ?? false) 'Botiquín']),
                _kvGrid([
                  if ((ns?.numeroPersonas ?? 0) > 0)
                    _kv('Número de personas (atención inmediata)', '${ns?.numeroPersonas ?? 0}'),
                  if (ns?.otrasNecesidades != null && ns!.otrasNecesidades.trim().isNotEmpty)
                    _kv('Otras necesidades', ns.otrasNecesidades),
                  if (ns?.observaciones != null && ns!.observaciones.trim().isNotEmpty)
                    _kv('Observaciones', ns.observaciones),
                ]),
              ],
              ...l.establecimientosSalud.map((s) => _FotosDe(
                fotos: s.fotos,
                servidor: s.fotografia,
                coordenadaLat: s.coordenadaLat,
                coordenadaLon: s.coordenadaLon,
                seccion: 'Salud',
              )),
            ]);
          }),
      ],
    );
  }

  List<String>? _calcularTotalesSalud(List<EdanEstablecimientoSalud> items) {
    int med = 0, enf = 0, otros = 0;
    for (final s in items) {
      med += s.medicosAfectados;
      enf += s.enfermerasAfectados;
      otros += s.otrosAfectados;
    }
    if (med == 0 && enf == 0 && otros == 0) return null;
    return ['', 'TOTAL', '', '', '', '', '$med', '$enf', '$otros'];
  }

  Widget _seccion05() {
    final locs = edan.localidades.where((l) => l.impInfraestructura).toList();
    return _DocSeccion(
      numero: '05',
      titulo: 'Impacto en infraestructuras',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _subtitulo('Vías y puentes (${l.danosViales.length})'),
              if (l.danosViales.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['Vía', 'Tramo', 'Daño P', 'Daño T', 'Km'],
                  rows: l.danosViales.map((d) => [
                    _v(d.viaPuente),
                    _v(d.tramo),
                    d.danoParcial ? '✓' : '',
                    d.danoTotal ? '✓' : '',
                    d.kmDanio > 0
                        ? '${d.kmDanio == d.kmDanio.roundToDouble() ? d.kmDanio.toInt() : d.kmDanio}'
                        : '-',
                  ]).toList(),
                  totals: _calcularTotalesViales(l.danosViales),
                ),
              ...l.danosViales.map((d) => _FotosDe(
                fotos: d.fotos,
                servidor: d.fotografia,
                coordenadaLat: d.coordenadaLat,
                coordenadaLon: d.coordenadaLon,
                seccion: 'Vías y puentes',
              )),
              _subtitulo('Infraestructura pública (${l.danosInfraPublica.length})'),
              if (l.danosInfraPublica.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['N°', 'Comunidad', 'Tipo', 'Daño P', 'Daño T'],
                  rows: l.danosInfraPublica.asMap().entries.map((e) => [
                    '${e.key + 1}',
                    _v(e.value.comunidad),
                    _v(e.value.tipoEstructura),
                    e.value.danoParcial ? '✓' : '',
                    e.value.danoTotal ? '✓' : '',
                  ]).toList(),
                ),
              ...l.danosInfraPublica.map((d) => _FotosDe(
                fotos: d.fotos,
                servidor: d.fotografia,
                coordenadaLat: d.coordenadaLat,
                coordenadaLon: d.coordenadaLon,
                seccion: 'Infraestructura pública',
              )),
            ]);
          }),
      ],
    );
  }

  List<String>? _calcularTotalesViales(List<EdanDanoVial> items) {
    double km = 0;
    for (final d in items) {
      km += d.kmDanio;
    }
    if (km == 0) return null;
    return ['', 'TOTAL', '', '', km == km.roundToDouble() ? '${km.toInt()}' : km.toStringAsFixed(1)];
  }

  Widget _seccion06() {
    final locs = edan.localidades.where((l) => l.impServicios).toList();
    return _DocSeccion(
      numero: '06',
      titulo: 'Impacto en servicios básicos',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _tablaConScroll(
                headers: ['Servicio', 'Daño P', 'Daño T', 'Necesidades', 'Obs.'],
                rows: l.serviciosBasicos.where((s) => s.tieneDatos).map((s) => [
                  s.etiqueta,
                  s.danoParcial ? '✓' : '',
                  s.danoTotal ? '✓' : '',
                  s.necesidadesInmediatas.trim().isNotEmpty ? s.necesidadesInmediatas : '-',
                  s.observaciones.trim().isNotEmpty ? s.observaciones : '-',
                ]).toList(),
              ),
            ]);
          }),
      ],
    );
  }

  Widget _seccion07() {
    final locs = edan.localidades.where((l) => l.impEducacion).toList();
    return _DocSeccion(
      numero: '07',
      titulo: 'Impacto en educación',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _subtitulo('Unidades educativas (${l.unidadesEducativas.length})'),
              if (l.unidadesEducativas.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['N°', 'Nombre', 'Comunidad', 'Daño P', 'Daño T', 'Susp.', 'Material', 'Albergue', 'Est.', 'Prof.', 'Admin.', 'Total', 'Obs.'],
                  rows: l.unidadesEducativas.asMap().entries.map((e) => [
                    '${e.key + 1}',
                    _v(e.value.nombreEstablecimiento),
                    _v(e.value.comunidad),
                    e.value.danoParcial ? '✓' : '',
                    e.value.danoTotal ? '✓' : '',
                    e.value.suspensionClases == true ? '✓' : '',
                    e.value.perdidaMaterial == true ? '✓' : '',
                    e.value.funcionaAlbergue == true ? '✓' : '',
                    '${e.value.estudiantes}',
                    '${e.value.profesores}',
                    '${e.value.administrativos}',
                    '${e.value.totalAfectados}',
                    e.value.observaciones.trim().isNotEmpty ? e.value.observaciones : '-',
                  ]).toList(),
                  totals: _calcularTotalesEducacion(l.unidadesEducativas),
                ),
              ...l.unidadesEducativas.map((u) => _FotosDe(
                fotos: u.fotos,
                servidor: u.fotografia,
                coordenadaLat: u.coordenadaLat,
                coordenadaLon: u.coordenadaLon,
                seccion: 'Educación',
              )),
            ]);
          }),
      ],
    );
  }

  List<String>? _calcularTotalesEducacion(List<EdanDanoUnidadEducativa> items) {
    int est = 0, prof = 0, admin = 0;
    for (final u in items) {
      est += u.estudiantes;
      prof += u.profesores;
      admin += u.administrativos;
    }
    if (est == 0 && prof == 0 && admin == 0) return null;
    return ['', 'TOTAL', '', '', '', '', '', '', '$est', '$prof', '$admin', '${est + prof + admin}', ''];
  }

  Widget _seccion08() {
    final locs = edan.localidades.where((l) => l.impVivienda).toList();
    return _DocSeccion(
      numero: '08',
      titulo: 'Impacto en viviendas',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              if (l.danosVivienda.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['Comunidad', 'Viv. Parcial', 'Viv. Total', 'Necesidades', 'Obs.'],
                  rows: l.danosVivienda.map((v) => [
                    _v(v.comunidad),
                    v.danoParcial > 0 ? '${v.danoParcial}' : '0',
                    v.danoTotal > 0 ? '${v.danoTotal}' : '0',
                    v.necesidadesInmediatas.trim().isNotEmpty ? v.necesidadesInmediatas : '-',
                    v.observaciones.trim().isNotEmpty ? v.observaciones : '-',
                  ]).toList(),
                  totals: _calcularTotalesVivienda(l.danosVivienda),
                ),
              ...l.danosVivienda.map((v) => _FotosDe(
                fotos: v.fotos,
                servidor: v.fotografia,
                coordenadaLat: v.coordenadaLat,
                coordenadaLon: v.coordenadaLon,
                seccion: 'Viviendas',
              )),
            ]);
          }),
      ],
    );
  }

  List<String>? _calcularTotalesVivienda(List<EdanDanoVivienda> items) {
    int parcial = 0, total = 0;
    for (final v in items) {
      parcial += v.danoParcial;
      total += v.danoTotal;
    }
    if (parcial == 0 && total == 0) return null;
    return ['TOTAL', '$parcial', '$total', '', ''];
  }

  Widget _seccion09() {
    final locs = edan.localidades.where((l) => l.impAgropecuario).toList();
    return _DocSeccion(
      numero: '09',
      titulo: 'Impacto agropecuario',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _subtitulo('Daños en agricultura'),
              if (l.danosAgricultura.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['Cultivo', 'Has. Afectadas', 'Has. Perdidas', 'Necesidades', 'Obs.'],
                  rows: l.danosAgricultura.map((a) => [
                    _v(a.tipoCultivo),
                    '${a.hectareasAfectadas}',
                    '${a.hectareasPerdidas}',
                    a.necesidadesInmediatas.trim().isNotEmpty ? a.necesidadesInmediatas : '-',
                    a.observaciones.trim().isNotEmpty ? a.observaciones : '-',
                  ]).toList(),
                  totals: _calcularTotalesAgricultura(l.danosAgricultura),
                ),
              ...l.danosAgricultura.map((a) => _FotosDe(
                fotos: a.fotos,
                servidor: a.fotografia,
                coordenadaLat: a.coordenadaLat,
                coordenadaLon: a.coordenadaLon,
                seccion: 'Agricultura',
              )),
              _subtitulo('Daños pecuarios'),
              if (l.danosPecuarios.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['Especie', 'Raza', 'Afectados', 'Muertos', 'Necesidades'],
                  rows: l.danosPecuarios.map((p) => [
                    _v(p.especie),
                    _v(p.raza),
                    '${p.animalesAfectados}',
                    '${p.animalesMuertos}',
                    p.necesidadesInmediatas.trim().isNotEmpty ? p.necesidadesInmediatas : '-',
                  ]).toList(),
                  totals: _calcularTotalesPecuarios(l.danosPecuarios),
                ),
              ...l.danosPecuarios.map((p) => _FotosDe(
                fotos: p.fotos,
                servidor: p.fotografia,
                coordenadaLat: p.coordenadaLat,
                coordenadaLon: p.coordenadaLon,
                seccion: 'Pecuarios',
              )),
              _subtitulo('Infraestructura productiva'),
              if (l.infraProductiva.isEmpty)
                _vacio()
              else
                _tablaConScroll(
                  headers: ['Tipo', 'Parcial (#)', 'Total (#)'],
                  rows: l.infraProductiva.map((x) => [
                    _v(x.tipo),
                    x.danoParcial > 0 ? '${x.danoParcial}' : '0',
                    x.danoTotal > 0 ? '${x.danoTotal}' : '0',
                  ]).toList(),
                  totals: _calcularTotalesInfraProd(l.infraProductiva),
                ),
              ...l.infraProductiva.map((x) => _FotosDe(
                fotos: x.fotos,
                servidor: x.fotografia,
                coordenadaLat: x.coordenadaLat,
                coordenadaLon: x.coordenadaLon,
                seccion: 'Infraestructura productiva',
              )),
            ]);
          }),
      ],
    );
  }

  List<String>? _calcularTotalesAgricultura(List<EdanDanoAgricultura> items) {
    int af = 0, per = 0;
    for (final a in items) {
      af += a.hectareasAfectadas;
      per += a.hectareasPerdidas;
    }
    if (af == 0 && per == 0) return null;
    return ['TOTAL', '$af', '$per', '', ''];
  }

  List<String>? _calcularTotalesPecuarios(List<EdanDanoPecuario> items) {
    int af = 0, mu = 0;
    for (final p in items) {
      af += p.animalesAfectados;
      mu += p.animalesMuertos;
    }
    if (af == 0 && mu == 0) return null;
    return ['TOTAL', '', '$af', '$mu', ''];
  }

  List<String>? _calcularTotalesInfraProd(List<EdanInfraProductiva> items) {
    int parcial = 0, total = 0;
    for (final x in items) {
      parcial += x.danoParcial;
      total += x.danoTotal;
    }
    if (parcial == 0 && total == 0) return null;
    return ['TOTAL', '$parcial', '$total'];
  }

  Widget _seccion10() {
    final locs = edan.localidades.where((l) => l.impProteccion).toList();
    return _DocSeccion(
      numero: '10',
      titulo: 'Impacto en protección',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _tablaConScroll(
                headers: ['Grupo', 'Mujeres', 'Hombres', 'Total', 'Apoyo Psic.', 'Repos. Doc.', 'Obs.'],
                rows: l.proteccion.asMap().entries.map((e) => [
                  EdanLocalidad.etiquetasProteccion[e.key],
                  '${e.value.mujeres}',
                  '${e.value.hombres}',
                  '${e.value.total}',
                  e.value.apoyoPsicologico == true ? '✓' : e.value.apoyoPsicologico == false ? '✗' : '-',
                  e.value.reposicionDocumentos == true ? '✓' : e.value.reposicionDocumentos == false ? '✗' : '-',
                  e.value.observaciones.trim().isNotEmpty ? e.value.observaciones : '-',
                ]).toList(),
                totals: _calcularTotalesProteccion(l.proteccion),
              ),
            ]);
          }),
      ],
    );
  }

  List<String>? _calcularTotalesProteccion(List<EdanGrupoVulnerable> items) {
    int muj = 0, hom = 0;
    for (final g in items) {
      muj += g.mujeres;
      hom += g.hombres;
    }
    if (muj == 0 && hom == 0) return null;
    return ['TOTAL', '$muj', '$hom', '${muj + hom}', '', '', ''];
  }

  Widget _seccion11() {
    final locs = edan.localidades.where((l) => l.impNecesidades).toList();
    return _DocSeccion(
      numero: '11',
      titulo: 'Necesidades humanitarias',
      children: [
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final n = l.necesidadHumanitaria ?? EdanNecesidadHumanitaria();
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _tablaConScroll(
                headers: ['Necesidad', 'SI', 'NO'],
                rows: [
                  ['Alimentos', n.alimentos ? '✓' : '', !n.alimentos ? '✓' : ''],
                  ['Refugio / vivienda', n.refugioVivienda ? '✓' : '', !n.refugioVivienda ? '✓' : ''],
                  ['Ropa de cama', n.ropaCama ? '✓' : '', !n.ropaCama ? '✓' : ''],
                  ['Artículos de higiene', n.articulosHigiene ? '✓' : '', !n.articulosHigiene ? '✓' : ''],
                  ['Artículos de cocina', n.articulosCocina ? '✓' : '', !n.articulosCocina ? '✓' : ''],
                  ['Prendas de vestir', n.prendasVestir ? '✓' : '', !n.prendasVestir ? '✓' : ''],
                  ['Herramientas', n.herramientas ? '✓' : '', !n.herramientas ? '✓' : ''],
                  ['Almacenamiento de agua', n.almacenamientoAgua ? '✓' : '', !n.almacenamientoAgua ? '✓' : ''],
                  ['Baños', n.banos ? '✓' : '', !n.banos ? '✓' : ''],
                ],
              ),
              if (n.obsAlimentos.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Alimentos', n.obsAlimentos)]),
              if (n.obsRefugioVivienda.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Refugio / vivienda', n.obsRefugioVivienda)]),
              if (n.obsRopaCama.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Ropa de cama', n.obsRopaCama)]),
              if (n.obsArticulosHigiene.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Artículos de higiene', n.obsArticulosHigiene)]),
              if (n.obsArticulosCocina.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Artículos de cocina', n.obsArticulosCocina)]),
              if (n.obsPrendasVestir.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Prendas de vestir', n.obsPrendasVestir)]),
              if (n.obsHerramientas.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Herramientas', n.obsHerramientas)]),
              if (n.obsAlmacenamientoAgua.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Almacenamiento de agua', n.obsAlmacenamientoAgua)]),
              if (n.obsBanos.trim().isNotEmpty)
                _kvGrid([_kv('Observaciones · Baños', n.obsBanos)]),
            ]);
          }),
      ],
    );
  }

  Widget _seccion13() {
    final r = edan.responsable;
    final token = AuthService.instance.currentToken;
    return _DocSeccion(
      numero: '13',
      titulo: 'Responsable',
      children: [
        _kvGrid([
          _kv('Nombre', _v(r.nombre)),
          _kv('Cargo', _v(r.cargo)),
          _kv('Fono', _v(r.fono)),
          _kv('Correo', _v(r.correo)),
          _kv('Carnet', _v(token?.carnet)),
          _kv('Comunidad', _v(token?.comunidad)),
          _kv('Departamento', _v(token?.departamentoNombre)),
          _kv('Provincia', _v(token?.provinciaNombre)),
          _kv('Municipio', _v(token?.municipioNombre)),
        ]),
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
              'Declaración jurada: La información presentada en este '
              'formulario EDAN tiene carácter de declaración jurada. La '
              'información proporcionada debe ser correcta y será verificada '
              'por las autoridades correspondientes.',
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

  // --- Helper widgets ---

  String _v(String? s) => (s == null || s.trim().isEmpty) ? '-' : s;

  Widget _vacio() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'Sin registros.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _kv(String label, String value) {
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
          value,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _kvGrid(List<Widget> fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: fields,
      ),
    );
  }

  Widget _subtitulo(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _bloqueLocalidad(int index, String nombre, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
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
            'Lugar ${index + 1}${nombre.trim().isNotEmpty ? ' · ${nombre.trim()}' : ''}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _tags(List<String> tags) {
    if (tags.isEmpty) return _vacio();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: tags
            .map((t) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _tablaConScroll({
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? totals,
  }) {
    final needsScroll = headers.length > 3;
    final table = Table(
      columnWidths: _buildColumnWidths(headers.length),
      children: [
        TableRow(
          children: headers.map((h) => _headerCell(h)).toList(),
        ),
        ...rows.map((row) => TableRow(
              children: row.map((cell) => _dataCell(cell)).toList(),
            )),
        if (totals != null)
          TableRow(
            children: totals.map((cell) => _totalCell(cell)).toList(),
          ),
      ],
    );

    if (needsScroll) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 64),
              child: table,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: table,
      ),
    );
  }

  Map<int, TableColumnWidth> _buildColumnWidths(int count) {
    if (count <= 3) {
      return {for (var i = 0; i < count; i++) i: const FlexColumnWidth()};
    }
    return {
      0: const FixedColumnWidth(36),
      for (var i = 1; i < count; i++) i: const FixedColumnWidth(80),
    };
  }

  Widget _headerCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(
          right: BorderSide(color: Colors.white24),
          bottom: BorderSide(color: Colors.white24),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _dataCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.divider),
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: text == '✓'
              ? AppColors.aprobado
              : AppColors.textPrimary,
          fontWeight: text == '✓' ? FontWeight.w800 : FontWeight.w400,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _totalCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const BoxDecoration(
        color: AppColors.primaryDark,
        border: Border(
          right: BorderSide(color: Colors.white24),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// --- Section container widget ---

class _DocSeccion extends StatelessWidget {
  final String numero;
  final String titulo;
  final List<Widget> children;

  const _DocSeccion({
    required this.numero,
    required this.titulo,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    numero,
                    style: const TextStyle(
                      color: Colors.white,
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
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

// --- Photos widget (identical to v1) ---

class _FotosDe extends StatelessWidget {
  final List<EdanFoto> fotos;
  final String? servidor;
  final double coordenadaLat;
  final double coordenadaLon;
  final String? seccion;

  const _FotosDe({
    required this.fotos,
    this.servidor,
    this.coordenadaLat = 0,
    this.coordenadaLon = 0,
    this.seccion,
  });

  String _fotoUrl(String serverPath) =>
      '${ApiConfig.baseUrl}/upload/descargar/${Uri.encodeComponent(serverPath)}';

  Map<String, String> get _fotoHeaders => {
        'Authorization':
            'Bearer ${AuthService.instance.currentToken?.accessToken ?? ''}',
      };

  Widget _imagenDeFoto(EdanFoto? foto, {BoxFit fit = BoxFit.cover}) {
    if (foto != null &&
        foto.ruta.trim().isNotEmpty &&
        File(foto.ruta).existsSync()) {
      return Image.file(
        File(foto.ruta),
        fit: fit,
        errorBuilder: (_, _, _) => _fotoPlaceholder(),
      );
    }
    final server = servidor;
    if (server != null && server.trim().isNotEmpty) {
      return Image.network(
        _fotoUrl(server),
        headers: _fotoHeaders,
        fit: fit,
        errorBuilder: (_, _, _) => _fotoPlaceholder(),
      );
    }
    return _fotoPlaceholder();
  }

  Widget _fotoPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 28,
        color: AppColors.textSecondary,
      ),
    );
  }

  void _verFotoFullscreen(BuildContext context, EdanFoto? foto) {
    final lat = (foto != null && foto.latitud != 0)
        ? foto.latitud
        : coordenadaLat;
    final lon = (foto != null && foto.longitud != 0)
        ? foto.longitud
        : coordenadaLon;
    final precision = foto?.precision ?? 0;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogCtx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: _imagenDeFoto(foto, fit: BoxFit.contain),
                ),
              ),
            ),
            if (seccion != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Respaldo - $seccion',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
            ),
            if (lat != 0 || lon != 0)
              Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(dialogCtx).padding.bottom + 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (precision > 0)
                        Text(
                          '±${precision.toStringAsFixed(0)}m',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = servidor;
    final tieneRemota =
        server != null && server.trim().isNotEmpty;
    if (fotos.isEmpty && !tieneRemota) return const SizedBox.shrink();

    final List<EdanFoto?> fotosAMostrar =
        fotos.isNotEmpty ? fotos : [null];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: fotosAMostrar.map((foto) {
          final lat = (foto != null && foto.latitud != 0)
              ? foto.latitud
              : coordenadaLat;
          final lon = (foto != null && foto.longitud != 0)
              ? foto.longitud
              : coordenadaLon;
          final precision = foto?.precision ?? 0;
          return GestureDetector(
            onTap: () => _verFotoFullscreen(context, foto),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: _imagenDeFoto(foto),
                  ),
                ),
                if (lat != 0 || lon != 0) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 96,
                    child: Text(
                      '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
                      '${precision > 0 ? ' ±${precision.round()}m' : ''}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
