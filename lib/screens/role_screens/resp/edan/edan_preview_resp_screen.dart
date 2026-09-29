import 'package:flutter/material.dart';
import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../services/edan/edan_localidades_envio_v2_service.dart';
import 'edan_resumen_page.dart';

/// Pantalla de previsualización del EDAN.
///
/// Envuelve [EdanResumenPage] en un Scaffold con AppBar y barra de
/// acciones condicional según el modo:
///
/// - **RESP** (`modoUGR: false`): "Volver" + "Enviar" (pop con `true`).
/// - **UGR** (`modoUGR: true`): "Rechazar" / "Aprobar" vía callbacks.
class EdanPreviewRespScreen extends StatefulWidget {
  final EdanLocalidad localidad;

  /// Si es `true`, muestra botones de Aprobar/Rechazar en vez de Enviar.
  final bool modoUGR;

  /// Callback llamado al presionar "Aprobar" (solo modo UGR).
  /// Debe hacer la llamada API y mutar el estado de la localidad.
  final Future<void> Function()? onAprobar;

  /// Callback llamado al presionar "Rechazar" (solo modo UGR).
  /// Debe hacer la llamada API y mutar el estado de la localidad.
  final Future<void> Function()? onRechazar;

  const EdanPreviewRespScreen({
    super.key,
    required this.localidad,
    this.modoUGR = false,
    this.onAprobar,
    this.onRechazar,
  });

  @override
  State<EdanPreviewRespScreen> createState() => _EdanPreviewRespScreenState();
}

class _EdanPreviewRespScreenState extends State<EdanPreviewRespScreen> {
  bool _procesando = false;
  bool _cargandoSecciones = true;
  String? _errorCarga;

  EdanLocalidad get _localidad => widget.localidad;

  @override
  void initState() {
    super.initState();
    _cargarSecciones();
  }

  Future<void> _cargarSecciones() async {
    try {
      final sincV2 = EdanLocalidadesEnvioV2Service();
      await sincV2.cargarSeccionesDesdeSQLite(_localidad);
      // Resincroniza los flags imp_* desde localidad_secciones_activas (misma
      // lógica que EdanDocumentoService.construirDocumento) para que la vista
      // previa refleje exactamente lo que se envía en el JSON.
      await _sincronizarFlagsActivas();
      if (mounted) {
        setState(() {
          _cargandoSecciones = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorCarga = e.toString();
          _cargandoSecciones = false;
        });
      }
    }
  }

  Future<void> _sincronizarFlagsActivas() async {
    // Fuente de verdad única: `localidad_secciones_activas` en SQLite (misma
    // lógica que `construirDocumento`, el wizard y los items del dashboard).
    await EdanLocalidadesEnvioV2Service()
        .aplicarFlagsDesdeSeccionesActivas(_localidad);
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;

    if (_cargandoSecciones) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _localidad.nombre.isNotEmpty
                ? _localidad.nombre
                : 'Vista previa EDAN',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cargando secciones...'),
            ],
          ),
        ),
      );
    }

    if (_errorCarga != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _localidad.nombre.isNotEmpty
                ? _localidad.nombre
                : 'Vista previa EDAN',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text('Error al cargar secciones'),
              const SizedBox(height: 8),
              Text(_errorCarga!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final seccionesCompletas =
        EdanResumenPage.calcularSeccionesCompletas(_localidad);
    final tieneDatos = seccionesCompletas.values.any((v) => v);
    final completo = EdanResumenPage.formularioCompleto(_localidad);
    final incompletos = seccionesCompletas.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _localidad.nombre.isNotEmpty
              ? _localidad.nombre
              : 'Vista previa EDAN',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _procesando ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: EdanResumenPage(
          localidad: _localidad,
          seccionesCompletas: seccionesCompletas,
        ),
      ),
      bottomNavigationBar: _buildBottomBar(primary, incompletos, tieneDatos, completo),
    );
  }

  Widget _buildBottomBar(
      Color primary, List<String> incompletos, bool tieneDatos, bool completo) {
    // Solo mostrar botones de acción si el estado es borrador (id=1) o rechazadoUgr (id=4)
    final puedeAccionar = _localidad.estadoLocalidad == UgrLocalidadEstado.borrador ||
        _localidad.estadoLocalidad == UgrLocalidadEstado.rechazadoUgr;
    if (!puedeAccionar && !widget.modoUGR) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (incompletos.isNotEmpty)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.pending.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.pending.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.pending),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Secciones incompletas: ${incompletos.join(", ")}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.pending,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (incompletos.isNotEmpty) const SizedBox(height: 10),
            if (widget.modoUGR)
              _buildUGRButtons(primary)
            else
              _buildRESPButtons(primary, tieneDatos, completo),
          ],
        ),
      ),
    );
  }

  // ────────────────────── Modo RESP ──────────────────────

  Widget _buildRESPButtons(Color primary, bool tieneDatos, bool completo) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed:
                _procesando ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              side: BorderSide(color: primary, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(0, 50),
            ),
            child: const Text('Volver'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Tooltip(
            message: completo ? '' : 'Faltan secciones por completar',
            child: ElevatedButton(
              onPressed: (_procesando || !tieneDatos || !completo)
                  ? null
                  : () => _confirmarEnvio(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.divider,
                disabledForegroundColor: AppColors.textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(0, 50),
              ),
              child: _procesando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enviar'),
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────── Modo UGR ──────────────────────

  Widget _buildUGRButtons(Color primary) {
    final tieneRechazar = widget.onRechazar != null;
    final tieneAprobar = widget.onAprobar != null;

    if (!tieneRechazar && !tieneAprobar) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _procesando ? null : () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            minimumSize: const Size(0, 50),
          ),
          child: const Text('Cerrar'),
        ),
      );
    }

    return Row(
      children: [
        if (tieneRechazar)
          Expanded(
            child: OutlinedButton(
              onPressed: _procesando ? null : () => _confirmarAccion('Rechazar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.rechazado,
                side: const BorderSide(color: AppColors.rechazado, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(0, 50),
              ),
              child: _procesando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.rechazado))
                  : const Text('Rechazar'),
            ),
          ),
        if (tieneRechazar && tieneAprobar) const SizedBox(width: 12),
        if (tieneAprobar)
          Expanded(
            child: ElevatedButton(
              onPressed: _procesando ? null : () => _confirmarAccion('Aprobar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.aprobado,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(0, 50),
              ),
              child: _procesando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Aprobar'),
            ),
          ),
      ],
    );
  }

  // ────────────────────── Diálogos ──────────────────────

  void _confirmarEnvio(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            size: 48, color: Color(0xFFF59E0B)),
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
    ).then((confirmado) {
      if (confirmado == true && mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  void _confirmarAccion(String accion) {
    final esAprobar = accion == 'Aprobar';
    final color = esAprobar ? AppColors.aprobado : AppColors.rechazado;
    final icono =
        esAprobar ? Icons.check_circle : Icons.cancel;

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icono, size: 48, color: color),
        title: Text('$accion localidad'),
        content: Text(
          '¿Está seguro de que desea $accion esta localidad?',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: color),
            child: Text(accion),
          ),
        ],
      ),
    ).then((confirmado) async {
      if (confirmado == true && mounted) {
        setState(() => _procesando = true);
        try {
          if (esAprobar) {
            await widget.onAprobar?.call();
          } else {
            await widget.onRechazar?.call();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Localidad ${accion.toLowerCase()}'),
                backgroundColor: color,
              ),
            );
            Navigator.of(context).pop(true);
          }
        } catch (e) {
          if (mounted) {
            setState(() => _procesando = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      }
    });
  }
}
