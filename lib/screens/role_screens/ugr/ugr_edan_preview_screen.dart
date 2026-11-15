import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../config/api_config.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../models/usuario.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/database_helper.dart';
import 'crear_usuario_screen.dart';
import 'ugr_edan_localidad_preview_screen.dart';
import 'ugr_recurso_upload_screen.dart';
import 'ugr_route.dart';
import '../../../services/app_logger_ui.dart';

class UgrEdanPreviewScreen extends StatefulWidget {
  final Edan edan;

  const UgrEdanPreviewScreen({
    super.key,
    required this.edan,
  });

  @override
  State<UgrEdanPreviewScreen> createState() => _UgrEdanPreviewScreenState();
}

class _UgrEdanPreviewScreenState extends State<UgrEdanPreviewScreen> {
  bool _guardando = false;
  bool _bannerExpanded = false;
  Future<List<Usuario>>? _alcaldesListFuture;
  bool _localidadesExpanded = false;
  List<Map<String, dynamic>> _documentosEdan = [];
  bool _cargandoDocumentos = false;

  Edan get edan => widget.edan;

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

  Future<void> _cargarDocumentosEdan() async {
    final idEdan = edan.idEdan;
    if (idEdan == null || !ConnectivityService().isConnected) return;
    if (mounted) setState(() => _cargandoDocumentos = true);
    try {
      final docs = await ApiService.instance.listarDocumentosEdan(idEdan);
      if (mounted) {
        setState(() {
          _documentosEdan = docs;
          _cargandoDocumentos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoDocumentos = false);
    }
  }

  Future<void> _navegarSubirDocumento() async {
    final idEdan = edan.idEdan;
    if (idEdan == null) return;
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UgrRecursoUploadScreen(edan: edan),
      ),
    );
    if (resultado == true && mounted) {
      _cargarDocumentosEdan();
    }
  }

  Future<void> _confirmarConsolidacion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.layers, color: AppColors.aprobado, size: 48),
        title: const Text('Consolidar EDAN'),
        content: const Text(
          '¿Confirmar la consolidación de las localidades seleccionadas en un EDAN?',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.aprobado),
            child: const Text('Consolidar'),
          ),
        ],
      ),
    );
    if (confirmado == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarDocumentosEdan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    edan.completarResponsableDesdeCache();
    for (final l in edan.localidades) {
      l.deduplicarSecciones();
    }

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
          if (_seccionTieneDatos(3)) _seccion03(),
          if (_seccionTieneDatos(4)) _seccion04(),
          if (_seccionTieneDatos(5)) _seccion05(),
          if (_seccionTieneDatos(6)) _seccion06(),
          if (_seccionTieneDatos(7)) _seccion07(),
          if (_seccionTieneDatos(8)) _seccion08(),
          if (_seccionTieneDatos(9)) _seccion09(),
          if (_seccionTieneDatos(10)) _seccion10(),
          if (_seccionTieneDatos(11)) _seccion11(),
          _seccion13(),
          const SizedBox(height: 12),
          _buildDeclaracion(),
          const SizedBox(height: 16),
          _buildLocalidadesExpandible(primary),
          const SizedBox(height: 12),
          _buildDocumentosVinculados(primary),
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
            if (edan.idEdan == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirmarConsolidacion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.aprobado,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 56),
                  ),
                  child: const Text('Consolidar'),
                ),
              )
            else if (edan.idEdan != null &&
                (edan.idEstado == 1 || edan.estado.trim().toLowerCase() == 'borrador'))
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(0, 56),
                      ),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 56),
                  ),
                  child: const Text('Cerrar'),
                ),
              ),
          ],
        ),
      ),
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
          final isSelected = a.idUsuario == edan.idUsuarioAlcalde;
          return GestureDetector(
            onTap: _guardando ? null : () => _asignarAlcalde(a),
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
                  GestureDetector(
                    onTap: _guardando ? null : () => _editarAlcalde(a),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: isSelected ? primary : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle, size: 20, color: primary),
                  ],
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
      ],
    );
  }

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
          showAppSnackBar(context, 
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
          _cargarAlcaldes();
        });
        await _guardarAlcalde();
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, 
            SnackBar(
              content: Text('Error al obtener datos del usuario: ${ApiService.traducirError(e)}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _asignarAlcalde(Usuario u) async {
    setState(() {
      edan
        ..idUsuarioAlcalde = u.idUsuario
        ..nombreAlcalde = u.nombre
        ..fonoAlcalde = u.celular ?? '';
      _bannerExpanded = false;
    });
    await _guardarAlcalde();
  }

  Future<void> _editarAlcalde(Usuario u) async {
    if (!ConnectivityService().isConnected) {
      if (mounted) {
        showAppSnackBar(context, 
          const SnackBar(content: Text('Sin conexión. Verifica tu red y reintenta.'), backgroundColor: AppColors.pending),
        );
      }
      return;
    }
    final actualizado = await Navigator.of(context).push<Usuario>(
      ugrRoute(CrearUsuarioScreen(
        usuario: u,
        idMunicipio: edan.idMunicipio,
        idDepartamento: edan.idDepartamento,
        idProvincia: edan.idProvincia,
      )),
    );
    if (actualizado == null || !mounted) return;
    setState(() => _cargarAlcaldes());
    if (edan.idUsuarioAlcalde == actualizado.idUsuario) {
      setState(() {
        edan
          ..nombreAlcalde = actualizado.nombre
          ..fonoAlcalde = actualizado.celular ?? '';
      });
      await _guardarAlcalde();
    }
  }

  Future<void> _guardarAlcalde() async {
    final edanId = edan.idEdan ?? edan.idServer;
    if (edanId == null) return;
    if (edan.idUsuario != null && edan.idUsuario != AuthService.instance.userId) {
      if (mounted) {
        showAppSnackBar(context, 
          const SnackBar(content: Text('Solo el creador puede editar este EDAN.'), backgroundColor: AppColors.pending),
        );
      }
      return;
    }
    if (!ConnectivityService().isConnected) {
      if (edan.idLocal != null) {
        await DatabaseHelper.instance.updateEdan(edan);
        if (mounted) {
          showAppSnackBar(context, 
            const SnackBar(content: Text('Alcalde guardado localmente. Se sincronizará cuando haya conexión.'), backgroundColor: AppColors.pending),
          );
          setState(() {});
        }
      } else {
        if (mounted) {
          showAppSnackBar(context, 
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
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Alcalde asignado correctamente'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
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
          showAppSnackBar(context, 
            const SnackBar(content: Text('EDAN marcado para eliminar. Se procesará al sincronizar.'), backgroundColor: AppColors.pending),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          showAppSnackBar(context, 
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
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('EDAN deshecho correctamente. Localidades liberadas.'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
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
        ],
      ),
    );
  }

  Widget _seccion01() {
    return _DocSeccion(
      numero: '01',
      titulo: 'Datos generales',
      children: [
        _dg([
          _campoAlcaldeInline(),
          _df('Departamento', _v(edan.departamentoNombre)),
          _df('Provincia', _v(edan.provinciaNombre)),
          _df('Municipio', _v(edan.municipioNombre)),
          _df('Fecha llenado', _v(edan.fechaLlenado)),
          _df('Fecha evento', _v(edan.fechaEvento)),
          _df('Hora evento', _v(edan.horaEvento)),
          _df('Tipo de evento', _v(edan.tipoEventoNombre)),
          _df('Lugares afectados',
              edan.localidadesAfectadas > 0 ? '${edan.localidadesAfectadas}' : '-'),
        ]),
        _buildTablaLocalidadesInline(),
      ],
    );
  }

  Widget _buildTablaLocalidadesInline() {
    final localidades = edan.localidades;
    if (localidades.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sh('Localidades incluidas (${localidades.length})'),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Nombre',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Tipo',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Municipio',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...localidades.asMap().entries.map((entry) {
                final i = entry.key;
                final l = entry.value;
                final esUltimo = i == localidades.length - 1;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: esUltimo
                          ? BorderSide.none
                          : const BorderSide(color: AppColors.divider, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          l.nombre.isNotEmpty ? l.nombre : '-',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          l.tipoLocalidad.isNotEmpty ? l.tipoLocalidad : '-',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          l.municipioNombre ?? '-',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  bool _seccionTieneDatos(int numSeccion) {
    for (final l in edan.localidades) {
      switch (numSeccion) {
        case 3:
          if (l.grupPoblacion) return true;
        case 4:
          if (l.grupSalud) return true;
        case 5:
          if (l.grupInfraestructura) return true;
        case 6:
          if (l.grupServicios) return true;
        case 7:
          if (l.grupEducacion) return true;
        case 8:
          if (l.grupVivienda) return true;
        case 9:
          if (l.grupAgropecuario) return true;
        case 10:
          if (l.grupProteccion) return true;
        case 11:
          if (l.grupNecesidades) return true;
      }
    }
    return false;
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
                  return Padding(
                    padding: const EdgeInsets.all(12),
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

  Widget _seccion02() {
    final totalPoblacion = edan.localidades.fold<int>(
        0, (suma, l) => suma + l.totalPoblacionAfectada);
    final totalFamiliasAfectadas = edan.localidades.fold<int>(
        0, (suma, l) => suma + l.totalFamiliasAfectadas);
    final totalFamiliasDamnificadas = edan.localidades.fold<int>(
        0, (suma, l) => suma + l.totalFamiliasDamnificadas);
    return _DocSeccion(
      numero: '02',
      titulo: 'Información total población afectada y damnificada',
      children: [
        _dg([
          _df('Población afectada',
              totalPoblacion > 0 ? '$totalPoblacion' : '0'),
          _df('Familias afectadas',
              totalFamiliasAfectadas > 0 ? '$totalFamiliasAfectadas' : '0'),
          _df('Familias damnificadas',
              totalFamiliasDamnificadas > 0 ? '$totalFamiliasDamnificadas' : '0'),
        ]),
      ],
    );
  }

  Widget _seccion03() {
    final locs = edan.localidades
        .where((l) => l.impImpactoPoblacion || l.impPrimeraRespuesta)
        .toList();
    /// Suma totals across all localidades con impacto en población
    final totalFallecidos = locs.fold<int>(0, (s, l) {
      final ip = l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0] : EdanImpactoPoblacion();
      return s + ip.fallecidos;
    });
    final totalHeridos = locs.fold<int>(0, (s, l) {
      final ip = l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0] : EdanImpactoPoblacion();
      return s + ip.heridos;
    });
    final totalDesaparecidos = locs.fold<int>(0, (s, l) {
      final ip = l.impactoPoblacion.isNotEmpty ? l.impactoPoblacion[0] : EdanImpactoPoblacion();
      return s + ip.desaparecidos;
    });
    return _DocSeccion(
      numero: '03',
      titulo: 'Impacto en la población',
      children: [
        _dg([
          _df('Fallecidos', totalFallecidos > 0 ? '$totalFallecidos' : '0'),
          _df('Heridos', totalHeridos > 0 ? '$totalHeridos' : '0'),
          _df('Desaparecidos', totalDesaparecidos > 0 ? '$totalDesaparecidos' : '0'),
        ]),
        _sh('Impacto en la población'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ip = _primerImpactoPoblacionConDatos(l.impactoPoblacion);
            // Set EXACTO de 4 grupos del catálogo (§20.10.E): en la vista
            // se ven siempre los 4, los vacíos en 0. Sin grupos anidados
            // (documento legacy plano) cada fila con datos aporta su rango.
            final grupos = EdanGrupoEtario.completarSet4([
              if (ip != null)
                if (ip.gruposEtarios.isNotEmpty)
                  ...ip.gruposEtarios
                else
                  for (final p in l.impactoPoblacion
                      .where((p) => p.tieneDatosGlobales))
                    EdanGrupoEtario(
                      rango: p.grupoEtario,
                      fallecidos: p.fallecidos,
                      heridos: p.heridos,
                      desaparecidos: p.desaparecidos,
                      observaciones: p.observaciones,
                      marcado: true,
                      idGrupoEtarioCatalogo:
                          EdanGrupoEtario.resolverIdGrupoEtario(p.grupoEtario),
                    ),
            ]);
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              if (ip != null) ...[
                _dg([
                  _df('Fallecidos', '${ip.fallecidos}'),
                  _df('Heridos', '${ip.heridos}'),
                  _df('Desaparecidos', '${ip.desaparecidos}'),
                ]),
                ...grupos.map((g) => _tb([
                      _tbRow('Grupo etario', _v(g.rango)),
                      _tbRow('Fallecidos', '${g.fallecidos}'),
                      _tbRow('Heridos', '${g.heridos}'),
                      _tbRow('Desaparecidos', '${g.desaparecidos}'),
                      if (g.observaciones.trim().isNotEmpty)
                        _tbRow('Observaciones', _v(g.observaciones)),
                    ])),
              ],
            ]);
          }),
        _sh('Necesidades primera respuesta'),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final nr = entry.value.necesidadPrimeraRespuesta;
            return _bloqueLocalidad(i, entry.value.etiquetaLugar, [
              _tags([
                if (nr?.busqueda ?? false) 'Búsqueda',
                if (nr?.salvamento ?? false) 'Salvamento',
                if (nr?.evacuacion ?? false) 'Evacuación',
              ]),
              if (nr?.observaciones != null && nr!.observaciones.trim().isNotEmpty)
                _df('Observaciones', nr.observaciones),
            ]);
          }),
      ],
    );
  }

  /// Retorna el primer registro de impacto poblacion que tiene al menos un valor > 0,
/// o null si la lista está vacía.
  EdanImpactoPoblacion? _primerImpactoPoblacionConDatos(
      List<EdanImpactoPoblacion> lista) {
    for (final ip in lista) {
      if (ip.fallecidos > 0 || ip.heridos > 0 || ip.desaparecidos > 0) {
        return ip;
      }
    }
    return null;
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
    final locs = edan.localidades
        .where((l) => l.impSaludEstablecimientos || l.impNecesidadSalud)
        .toList();
    /// Totales a nivel de EDAN
    final totalEstablecimientos = locs.fold<int>(0, (s, l) => s + l.establecimientosSalud.length);
    final totalMedicos = locs.fold<int>(0, (s, l) {
      final count = l.establecimientosSalud.fold<int>(0, (sum, s) => sum + s.medicosAfectados);
      return s + count;
    });
    final totalEnfermeras = locs.fold<int>(0, (s, l) {
      final count = l.establecimientosSalud.fold<int>(0, (sum, s) => sum + s.enfermerasAfectados);
      return s + count;
    });
    final totalOtros = locs.fold<int>(0, (s, l) {
      final count = l.establecimientosSalud.fold<int>(0, (sum, s) => sum + s.otrosAfectados);
      return s + count;
    });
    return _DocSeccion(
      numero: '04',
      titulo: 'Impacto en la salud',
      children: [
        _dg([
          _df('Establecimientos', totalEstablecimientos > 0 ? '$totalEstablecimientos' : '0'),
          _df('Médicos', totalMedicos > 0 ? '$totalMedicos' : '0'),
          _df('Enfermeras', totalEnfermeras > 0 ? '$totalEnfermeras' : '0'),
          _df('Otros', totalOtros > 0 ? '$totalOtros' : '0'),
        ]),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final ns = l.necesidadSalud;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Daños en servicios de salud (${l.establecimientosSalud.length})'),
              if (l.establecimientosSalud.isEmpty)
                _vacio()
              else
                ...l.establecimientosSalud.map((s) => _tb([
                      _tbRow('Nombre', _v(s.nombreEstablecimiento)),
                      _tbRow('Comunidad', _v(s.comunidad)),
                      _tbRow('Nivel', _v(s.nivelAtencion)),
                      _tags([
                        if (s.danoParcial) 'Daño parcial',
                        if (s.danoTotal) 'Daño total',
                      ]),
                      _tbRow('Médicos', '${s.medicosAfectados}'),
                      _tbRow('Enfermeras', '${s.enfermerasAfectados}'),
                      _tbRow('Otros', '${s.otrosAfectados}'),
                      _FotosDe(
                        fotos: s.fotos,
                        servidor: s.fotografia,
                        coordenadaLat: s.coordenadaLat,
                        coordenadaLon: s.coordenadaLon,
                        seccion: 'Salud',
                      ),
                    ])),
              if (_aplicaNecesidadesSalud) ...[
                _sh('Necesidades en salud'),
                _tags([if (ns?.botiquines ?? false) 'Botiquín']),
                if ((ns?.numeroPersonas ?? 0) > 0)
                  _df('Número de personas (atención inmediata)',
                      '${ns?.numeroPersonas ?? 0}'),
                if (ns?.otrasNecesidades != null && ns!.otrasNecesidades.trim().isNotEmpty)
                  _df('Otras necesidades', ns.otrasNecesidades),
                if (ns?.observaciones != null && ns!.observaciones.trim().isNotEmpty)
                  _df('Observaciones', ns.observaciones),
              ],
            ]);
          }),
      ],
    );
  }

  Widget _seccion05() {
    final locs = edan.localidades.where((l) =>
        l.danosViales.isNotEmpty ||
        l.danosInfraPublica.isNotEmpty).toList();
    /// Totales a nivel de EDAN
    final totalVias = locs.fold<int>(0, (s, l) => s + l.danosViales.length);
    final totalKm = locs.fold<double>(0, (s, l) {
      final sum = l.danosViales.fold<double>(0, (sum2, d) => sum2 + d.kmDanio);
      return s + sum;
    });
    final totalInfra = locs.fold<int>(0, (s, l) => s + l.danosInfraPublica.length);
    return _DocSeccion(
      numero: '05',
      titulo: 'Impacto en infraestructuras',
      children: [
        _dg([
          _df('Vías y puentes', totalVias > 0 ? '$totalVias' : '0'),
          _df('Km dañados', totalKm > 0 ? totalKm.toStringAsFixed(1) : '0'),
          _df('Infraestructura pública', totalInfra > 0 ? '$totalInfra' : '0'),
        ]),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Vías y puentes (${l.danosViales.length})'),
              if (l.danosViales.isEmpty)
                _vacio()
              else
                ...l.danosViales.map((d) => _tb([
                      _tbRow('Vía', _v(d.viaPuente)),
                      _tbRow('Tramo', _v(d.tramo)),
                      _tags([
                        if (d.danoParcial) 'Parcial',
                        if (d.danoTotal) 'Total',
                      ]),
                      if (d.kmDanio > 0)
                        _tbRow('Km dañados',
                            '${d.kmDanio == d.kmDanio.roundToDouble() ? d.kmDanio.toInt() : d.kmDanio}'),
                      _FotosDe(
                        fotos: d.fotos,
                        servidor: d.fotografia,
                        coordenadaLat: d.coordenadaLat,
                        coordenadaLon: d.coordenadaLon,
                        seccion: 'Vías y puentes',
                      ),
                    ])),
              _sh('Infraestructura pública (${l.danosInfraPublica.length})'),
              if (l.danosInfraPublica.isEmpty)
                _vacio()
              else
                ...l.danosInfraPublica.map((d) => _tb([
                      _tbRow('Comunidad', _v(d.comunidad)),
                      _tbRow('Tipo', _v(d.tipoEstructura)),
                      _tags([
                        if (d.danoParcial) 'Parcial',
                        if (d.danoTotal) 'Total',
                      ]),
                      _FotosDe(
                        fotos: d.fotos,
                        servidor: d.fotografia,
                        coordenadaLat: d.coordenadaLat,
                        coordenadaLon: d.coordenadaLon,
                        seccion: 'Infraestructura pública',
                      ),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion06() {
    final locs = edan.localidades.where((l) =>
        l.serviciosBasicos.any((s) => s.tieneDatos)).toList();
    /// Totales a nivel de EDAN
    final totalServicios = locs.fold<int>(0, (s, l) => s + l.serviciosBasicos.length);
    return _DocSeccion(
      numero: '06',
      titulo: 'Impacto en servicios básicos',
      children: [
        _dg([
          _df('Servicios con datos', totalServicios > 0 ? '$totalServicios' : '0'),
        ]),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              ...l.serviciosBasicos.map((s) => _tb([
                      _tbRow('Servicio', s.etiqueta),
                      _tags([
                        if (s.danoParcial) 'Parcial',
                        if (s.danoTotal) 'Total',
                      ]),
                      if (s.necesidadesInmediatas.trim().isNotEmpty)
                        _tbRow('Necesidades inmediatas',
                            _v(s.necesidadesInmediatas)),
                      if (s.observaciones.trim().isNotEmpty)
                        _tbRow('Observaciones', _v(s.observaciones)),
                      _FotosDe(
                        fotos: s.fotos,
                        servidor: s.fotografia,
                        coordenadaLat: s.coordenadaLat,
                        coordenadaLon: s.coordenadaLon,
                        seccion: 'Servicios básicos',
                      ),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion07() {
    final locs = edan.localidades.where((l) => l.grupEducacion).toList();
    /// Totales a nivel de EDAN
    final totalUnidades = locs.fold<int>(0, (s, l) => s + l.unidadesEducativas.length);
    final totalEstudiantes = locs.fold<int>(0, (s, l) {
      final sum = l.unidadesEducativas.fold<int>(0, (sum2, u) => sum2 + u.estudiantes);
      return s + sum;
    });
    final totalProfesores = locs.fold<int>(0, (s, l) {
      final sum = l.unidadesEducativas.fold<int>(0, (sum2, u) => sum2 + u.profesores);
      return s + sum;
    });
    final totalAdmin = locs.fold<int>(0, (s, l) {
      final sum = l.unidadesEducativas.fold<int>(0, (sum2, u) => sum2 + u.administrativos);
      return s + sum;
    });
    return _DocSeccion(
      numero: '07',
      titulo: 'Impacto en educación',
      children: [
        _dg([
          _df('Unidades educativas', totalUnidades > 0 ? '$totalUnidades' : '0'),
          _df('Estudiantes', totalEstudiantes > 0 ? '$totalEstudiantes' : '0'),
          _df('Profesores', totalProfesores > 0 ? '$totalProfesores' : '0'),
          _df('Administrativos', totalAdmin > 0 ? '$totalAdmin' : '0'),
        ]),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Unidades educativas (${l.unidadesEducativas.length})'),
              if (l.unidadesEducativas.isEmpty)
                _vacio()
              else
                ...l.unidadesEducativas.map((u) => _tb([
                      _tbRow('Nombre', _v(u.nombreEstablecimiento)),
                      _tbRow('Comunidad', _v(u.comunidad)),
                      _tags([
                        if (u.danoParcial) 'Parcial',
                        if (u.danoTotal) 'Total',
                        if (u.suspensionClases == true) 'Suspensión de clases',
                        if (u.perdidaMaterial == true) 'Pérdida de material educativo',
                        if (u.funcionaAlbergue == true) 'Funciona como albergue',
                      ]),
                      if (u.estudiantes > 0 ||
                          u.profesores > 0 ||
                          u.administrativos > 0) ...[
                        _tbRow('Estudiantes', '${u.estudiantes}'),
                        _tbRow('Profesores', '${u.profesores}'),
                        _tbRow('Administrativos', '${u.administrativos}'),
                        _tbRow('Total afectados', '${u.totalAfectados}'),
                      ],
                      if (u.observaciones.trim().isNotEmpty)
                        _tbRow('Observaciones', _v(u.observaciones)),
                      _FotosDe(
                        fotos: u.fotos,
                        servidor: u.fotografia,
                        coordenadaLat: u.coordenadaLat,
                        coordenadaLon: u.coordenadaLon,
                        seccion: 'Educación',
                      ),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion08() {
    final locs = edan.localidades.where((l) => l.grupVivienda).toList();
    /// Totales a nivel de EDAN
    final totalViviendas = locs.fold<int>(0, (s, l) => s + l.danosVivienda.length);
    final totalDanoParcial = locs.fold<int>(0, (s, l) {
      final count = l.danosVivienda.fold<int>(0, (sum, v) => sum + (v.danoParcial > 0 ? 1 : 0));
      return s + count;
    });
    final totalDanoTotal = locs.fold<int>(0, (s, l) {
      final count = l.danosVivienda.fold<int>(0, (sum, v) => sum + (v.danoTotal > 0 ? 1 : 0));
      return s + count;
    });
    return _DocSeccion(
      numero: '08',
      titulo: 'Impacto en viviendas',
      children: [
        _dg([
          _df('Viviendas dañadas', totalViviendas > 0 ? '$totalViviendas' : '0'),
          _df('Dano parcial', totalDanoParcial > 0 ? '$totalDanoParcial' : '0'),
          _df('Dano total', totalDanoTotal > 0 ? '$totalDanoTotal' : '0'),
        ]),
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
                ...l.danosVivienda.map((v) => _tb([
                      _tbRow('Comunidad', _v(v.comunidad)),
                      _tags([
                        if (v.danoParcial > 0) 'Parcial',
                        if (v.danoTotal > 0) 'Total',
                      ]),
                      if (v.danoParcial > 0)
                        _tbRow('Parcial', '${v.danoParcial} viviendas'),
                      if (v.danoTotal > 0)
                        _tbRow('Total', '${v.danoTotal} viviendas'),
                      if (v.necesidadesInmediatas.trim().isNotEmpty)
                        _tbRow('Necesidades inmediatas', v.necesidadesInmediatas),
                      if (v.observaciones.trim().isNotEmpty)
                        _tbRow('Observaciones', v.observaciones),
                      _FotosDe(
                        fotos: v.fotos,
                        servidor: v.fotografia,
                        coordenadaLat: v.coordenadaLat,
                        coordenadaLon: v.coordenadaLon,
                        seccion: 'Viviendas',
                      ),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion09() {
    final locs = edan.localidades.where((l) => l.grupAgropecuario).toList();
    /// Totales a nivel de EDAN
    final totalCultivos = locs.fold<int>(0, (s, l) => s + l.danosAgricultura.length);
    final totalAnimalesAfectados = locs.fold<int>(0, (s, l) {
      final count = l.danosPecuarios.fold<int>(0, (sum, p) => sum + p.animalesAfectados);
      return s + count;
    });
    final totalAnimalesMuertos = locs.fold<int>(0, (s, l) {
      final count = l.danosPecuarios.fold<int>(0, (sum, p) => sum + p.animalesMuertos);
      return s + count;
    });
    final totalInfraProductiva = locs.fold<int>(0, (s, l) => s + l.infraProductiva.length);
    return _DocSeccion(
      numero: '09',
      titulo: 'Impacto agropecuario',
      children: [
        _dg([
          _df('Cultivos dañados', totalCultivos > 0 ? '$totalCultivos' : '0'),
          _df('Animales afectados', totalAnimalesAfectados > 0 ? '$totalAnimalesAfectados' : '0'),
          _df('Animales muertos', totalAnimalesMuertos > 0 ? '$totalAnimalesMuertos' : '0'),
          _df('Infraestructura productiva', totalInfraProductiva > 0 ? '$totalInfraProductiva' : '0'),
        ]),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _sh('Daños en agricultura'),
              if (l.danosAgricultura.isEmpty)
                _vacio()
              else
                ...l.danosAgricultura.map((a) => _tb([
                      _tbRow('Cultivo', _v(a.tipoCultivo)),
                      _dg([
                        _df('Has afectadas', '${a.hectareasAfectadas}'),
                        _df('Has perdidas', '${a.hectareasPerdidas}'),
                      ]),
                      if (a.necesidadesInmediatas.trim().isNotEmpty)
                        _tbRow('Necesidades', a.necesidadesInmediatas),
                      _FotosDe(
                        fotos: a.fotos,
                        servidor: a.fotografia,
                        coordenadaLat: a.coordenadaLat,
                        coordenadaLon: a.coordenadaLon,
                        seccion: 'Agricultura',
                      ),
                    ])),
              _sh('Daños pecuarios'),
              if (l.danosPecuarios.isEmpty)
                _vacio()
              else
                ...l.danosPecuarios.map((p) => _tb([
                      _tbRow('Especie', _v(p.especie)),
                      _tbRow('Raza', _v(p.raza)),
                      _dg([
                        _df('Afectados', '${p.animalesAfectados}'),
                        _df('Muertos', '${p.animalesMuertos}'),
                      ]),
                      _FotosDe(
                        fotos: p.fotos,
                        servidor: p.fotografia,
                        coordenadaLat: p.coordenadaLat,
                        coordenadaLon: p.coordenadaLon,
                        seccion: 'Pecuarios',
                      ),
                    ])),
              _sh('Infraestructura productiva'),
              if (l.infraProductiva.isEmpty)
                _vacio()
              else
                ...l.infraProductiva.map((x) => _tb([
                      _tbRow('Tipo', _v(x.tipo)),
                      _tags([
                        if (x.danoParcial > 0) 'Parcial',
                        if (x.danoTotal > 0) 'Total',
                      ]),
                      if (x.danoParcial > 0)
                        _tbRow('Parcial', '${x.danoParcial} infraestructuras'),
                      if (x.danoTotal > 0)
                        _tbRow('Total', '${x.danoTotal} infraestructuras'),
                      _FotosDe(
                        fotos: x.fotos,
                        servidor: x.fotografia,
                        coordenadaLat: x.coordenadaLat,
                        coordenadaLon: x.coordenadaLon,
                        seccion: 'Infraestructura productiva',
                      ),
                    ])),
            ]);
          }),
      ],
    );
  }

  Widget _seccion10() {
    final locs = edan.localidades.where((l) => l.grupProteccion).toList();
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
              ..._filasProteccionFiltradas(l.proteccion),
            ]);
          }),
      ],
    );
  }

  /// Set EXACTO de 8 grupos vulnerables del catálogo (§20.11): en la vista
  /// se ven siempre los 8, los vacíos en 0 y los apoyos como Sí/No/—.
  List<Widget> _filasProteccionFiltradas(List<EdanGrupoVulnerable> grupos) {
    String siNo(bool? v) => v == null ? '—' : (v ? 'Sí' : 'No');
    return EdanGrupoVulnerable.completarSet8(grupos).map((g) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _tb([
        _tbRow(
            'Grupo',
            _v((g.nombreGrupo?.trim().isNotEmpty ?? false)
                ? g.nombreGrupo
                : EdanLocalidad.nombreGrupoVulnerablePorId(
                    g.idGrupoVulnerable))),
        _dg([
          _df('Mujeres', '${g.mujeres}'),
          _df('Hombres', '${g.hombres}'),
          _df('Total', '${g.total}'),
        ]),
        _dg([
          _df('¿Apoyo psicológico?', siNo(g.apoyoPsicologico)),
          _df('¿Reposición de documento?', siNo(g.reposicionDocumentos)),
        ]),
        if (g.observaciones.trim().isNotEmpty)
          _tbRow('Observaciones', g.observaciones),
      ]),
    )).toList();
  }

  Widget _seccion11() {
    final locs =
        edan.localidades.where((l) => l.impNecesidadHumanitaria).toList();
    /// Totales a nivel de EDAN
    final totalLocalidades = locs.length;
    final totalConAlimentos = locs.where((l) => l.necesidadHumanitaria?.alimentos ?? false).length;
    final totalConRefugio = locs.where((l) => l.necesidadHumanitaria?.refugioVivienda ?? false).length;
    final totalConRopaCama = locs.where((l) => l.necesidadHumanitaria?.ropaCama ?? false).length;
    final totalConAgua = locs.where((l) => l.necesidadHumanitaria?.almacenamientoAgua ?? false).length;
    final totalConBanios = locs.where((l) => l.necesidadHumanitaria?.banos ?? false).length;
    return _DocSeccion(
      numero: '11',
      titulo: 'Necesidades humanitarias',
      children: [
        _dg([
          _df('Localidades', totalLocalidades > 0 ? '$totalLocalidades' : '0'),
          _df('Con alimentos', totalConAlimentos > 0 ? '$totalConAlimentos' : '0'),
          _df('Con refugio/vivienda', totalConRefugio > 0 ? '$totalConRefugio' : '0'),
          _df('Con ropa de cama', totalConRopaCama > 0 ? '$totalConRopaCama' : '0'),
          _df('Con almacenamiento agua', totalConAgua > 0 ? '$totalConAgua' : '0'),
          _df('Con baños', totalConBanios > 0 ? '$totalConBanios' : '0'),
        ]),
        if (locs.isEmpty)
          _vacio()
        else
          ...locs.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final n = l.necesidadHumanitaria ?? EdanNecesidadHumanitaria();
            return _bloqueLocalidad(i, l.etiquetaLugar, [
              _tags([
                if (n.alimentos) 'Alimentos',
                if (n.refugioVivienda) 'Refugio / vivienda',
                if (n.ropaCama) 'Ropa de cama',
                if (n.articulosHigiene) 'Artículos de higiene',
                if (n.articulosCocina) 'Artículos de cocina',
                if (n.prendasVestir) 'Prendas de vestir',
                if (n.herramientas) 'Herramientas',
                if (n.almacenamientoAgua) 'Almacenamiento de agua',
                if (n.banos) 'Baños',
              ]),
              if (n.obsAlimentos.trim().isNotEmpty)
                _df('Observaciones · Alimentos', n.obsAlimentos),
              if (n.obsRefugioVivienda.trim().isNotEmpty)
                _df('Observaciones · Refugio / vivienda', n.obsRefugioVivienda),
              if (n.obsRopaCama.trim().isNotEmpty)
                _df('Observaciones · Ropa de cama', n.obsRopaCama),
              if (n.obsArticulosHigiene.trim().isNotEmpty)
                _df('Observaciones · Artículos de higiene', n.obsArticulosHigiene),
              if (n.obsArticulosCocina.trim().isNotEmpty)
                _df('Observaciones · Artículos de cocina', n.obsArticulosCocina),
              if (n.obsPrendasVestir.trim().isNotEmpty)
                _df('Observaciones · Prendas de vestir', n.obsPrendasVestir),
              if (n.obsHerramientas.trim().isNotEmpty)
                _df('Observaciones · Herramientas', n.obsHerramientas),
              if (n.obsAlmacenamientoAgua.trim().isNotEmpty)
                _df('Observaciones · Almacenamiento de agua', n.obsAlmacenamientoAgua),
              if (n.obsBanos.trim().isNotEmpty)
                _df('Observaciones · Baños', n.obsBanos),
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
        _dg([
          _df('Nombre', _v(r.nombre)),
          _df('Cargo', _v(r.cargo)),
          _df('Fono', _v(r.fono)),
          _df('Correo', _v(r.correo)),
          _df('Carnet', _v(token?.carnet)),
          _df('Comunidad', _v(token?.comunidad)),
          _df('Departamento', _v(token?.departamentoNombre)),
          _df('Provincia', _v(token?.provinciaNombre)),
          _df('Municipio', _v(token?.municipioNombre)),
        ]),
      ],
    );
  }

  Widget _buildLocalidadesExpandible(Color primary) {
    final localidades = edan.localidades;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      // Material transparente entre el fondo decorado del Container y los
      // `ListTile` de las localidades: sin el Material intermedio, el color del
      // BoxDecoration tapaba el fondo y el ripple de la fila (aviso del
      // framework "ListTile background color or ink splashes may be invisible").
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _localidadesExpanded = !_localidadesExpanded),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.location_on, color: Colors.white, size: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Localidades (${localidades.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _localidadesExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            if (_localidadesExpanded) ...[
              const SizedBox(height: 12),
              if (localidades.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Sin localidades registradas.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                )
              else
                ...localidades.asMap().entries.map((entry) {
                  final l = entry.value;
                  final estadoLabel = l.estadoLocalidad?.label ?? 'Sin estado';
                  final estadoColor = _localidadEstadoColor(estadoLabel.toLowerCase());
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: estadoColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        l.etiquetaLugar.isNotEmpty ? l.etiquetaLugar : 'Localidad ${entry.key + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        estadoLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: estadoColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onTap: () => _verDetalleLocalidad(l),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Color _localidadEstadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'aprobado ugr':
      case 'aprobado':
        return AppColors.aprobado;
      case 'rechazado ugr':
      case 'rechazado':
        return AppColors.rechazado;
      case 'enviado ugr':
      case 'enviado':
        return AppColors.inProgress;
      case 'borrador':
        return AppColors.pending;
      default:
        return AppColors.textSecondary;
    }
  }

  void _verDetalleLocalidad(EdanLocalidad localidad) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UgrEdanLocalidadPreviewScreen(localidad: localidad),
      ),
    );
  }

  Widget _buildDocumentosVinculados(Color primary) {
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
                child: const Center(
                  child: Icon(Icons.folder, color: Colors.white, size: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Documentos vinculados (${_documentosEdan.length})',
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
          if (_cargandoDocumentos)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_documentosEdan.isEmpty)
            Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Sin documentos vinculados.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _navegarSubirDocumento,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Subir primer documento'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else ...[
            ..._documentosEdan.map((doc) {
              final nombre = doc['nombre_documento'] ?? doc['nombreDocumento'] ?? 'documento.pdf';
              final tipoRaw = doc['tipo_documento'] ?? doc['tipo'];
              final tipo = tipoRaw is Map ? (tipoRaw['nombre'] ?? '') : (tipoRaw ?? '');
              final fecha = doc['fecha_documento'] ?? doc['fechaDocumento'] ?? '';
              final firmaRaw = doc['tiene_firma_digital'];
              final bool? tieneFirma = firmaRaw is bool
                  ? firmaRaw
                  : firmaRaw is num
                      ? firmaRaw == 1
                      : firmaRaw is String
                          ? firmaRaw.toLowerCase() == 'true'
                          : null;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, color: AppColors.error, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$nombre',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [if ('$tipo'.isNotEmpty) tipo, if ('$fecha'.isNotEmpty) fecha].join(' · '),
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          if (tieneFirma != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (tieneFirma
                                        ? AppColors.aprobado
                                        : AppColors.pending)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tieneFirma
                                        ? Icons.verified_user
                                        : Icons.error_outline,
                                    size: 11,
                                    color: tieneFirma
                                        ? AppColors.aprobado
                                        : AppColors.pending,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    tieneFirma ? 'Firmado' : 'Sin firma',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: tieneFirma
                                          ? AppColors.aprobado
                                          : AppColors.pending,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.visibility, size: 18),
                      color: primary,
                      onPressed: () => _abrirDocumento(doc),
                      tooltip: 'Ver',
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, size: 18),
                      color: AppColors.textSecondary,
                      onPressed: () => _descargarDocumento(doc),
                      tooltip: 'Descargar',
                    ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: AppColors.error,
                        onPressed: () => _confirmarEliminarDocumento(doc),
                        tooltip: 'Eliminar',
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _navegarSubirDocumento,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Subir PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _abrirDocumento(Map<String, dynamic> doc) async {
    try {
      final idDoc = doc['id_documento'] ?? doc['idDocumento'];
      if (idDoc == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/documentos_edan');
      await cacheDir.create(recursive: true);
      final file = File('${cacheDir.path}/$idDoc.pdf');

      if (!await file.exists()) {
        final bytes = await ApiService.instance.descargarDocRepositorio(idDoc);
        await file.writeAsBytes(bytes);
      }

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        showAppSnackBar(context, 
          SnackBar(
            content: Text('No se pudo abrir: ${result.message}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(
            content: Text('Error al abrir documento: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _descargarDocumento(Map<String, dynamic> doc) async {
    try {
      final idDoc = doc['id_documento'] ?? doc['idDocumento'];
      if (idDoc == null) return;
      final bytes = await ApiService.instance.descargarDocRepositorio(idDoc);
      final dir = await getApplicationDocumentsDirectory();
      final fileName = doc['nombre_documento'] ?? doc['nombreDocumento'] ?? 'documento_$idDoc.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(
            content: Text('Documento descargado: $fileName'),
            backgroundColor: AppColors.aprobado,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(
            content: Text('Error al descargar: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _confirmarEliminarDocumento(Map<String, dynamic> doc) {
    final nombre = doc['nombre_documento'] ?? doc['nombreDocumento'] ?? 'este documento';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 48),
        title: const Text('Eliminar documento'),
        content: Text('¿Eliminar "$nombre"?\n\nEl archivo se eliminará permanentemente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // El borrado debe correr DESPUES del teardown de la ruta del
              // dialogo: actuar en el mismo frame del pop disparaba el
              // assert `_dependents.isEmpty`.
              await WidgetsBinding.instance.endOfFrame;
              await _eliminarDocumento(doc);
            },
            child: const Text('Eliminar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarDocumento(Map<String, dynamic> doc) async {
    final idDoc = doc['id_documento'] ?? doc['idDocumento'];
    if (idDoc == null) return;
    if (!ConnectivityService().isConnected) {
      if (mounted) {
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Sin conexión. No se puede eliminar.'),
            backgroundColor: AppColors.pending,
          ),
        );
      }
      return;
    }
    try {
      await ApiService.instance.eliminarDocRepositorioHard(idDoc);
      if (mounted) {
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Documento eliminado.'),
            backgroundColor: AppColors.aprobado,
          ),
        );
        _cargarDocumentosEdan();
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 
          SnackBar(
            content: Text('Error al eliminar: ${ApiService.traducirError(e)}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
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

  Widget _df(String label, String value) {
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

  Widget _dg(List<Widget> fields) {
    return Wrap(
      spacing: 20,
      runSpacing: 10,
      children: fields,
    );
  }

  Widget _tbRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tb(List<Widget> rows) {
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
        children: rows,
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

  Widget _sh(String title) {
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
}

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
