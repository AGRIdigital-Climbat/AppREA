import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/edan_registro_v2.dart';
import '../../../../services/edan/edan_store.dart';
import 'edan_boton_sacar_foto.dart';

/// Resultado de la hoja de captura/edición de una vivienda 1:N.
class EdanViviendaSheetResult {
  final EdanViviendaTipo tipoDano;
  final double coordenadaLat;
  final double coordenadaLon;
  final String? fotografia;
  final List<EdanFoto> fotos;

  const EdanViviendaSheetResult({
    required this.tipoDano,
    required this.coordenadaLat,
    required this.coordenadaLon,
    required this.fotografia,
    required this.fotos,
  });
}

/// Hoja inferior para capturar los datos de una vivienda del detalle 1:N de
/// `danos-vivienda`: **tipo de daño (TOTAL/PARCIAL) + coordenadas + foto**.
///
/// Está modelada sobre la hoja de respaldo de foto ([EdanBotonSacarFoto]) y le
/// añade el selector de tipo de daño. Con [store] (V2) la foto se registra en
/// `fotografias`/`cola_fotos` con `tipo_entidad='vivienda'` (dueña = uuid de la
/// vivienda) para que el motor la suba por el sub-recurso `…/viviendas`.
class EdanViviendaSheet {
  EdanViviendaSheet._();

  static Future<EdanViviendaSheetResult?> mostrar(
    BuildContext context, {
    required EdanVivienda vivienda,
    EdanStore? store,
    String tipoEntidad = 'vivienda',
    String seccion = 'Viviendas',
    bool esNuevo = false,
  }) {
    return showModalBottomSheet<EdanViviendaSheetResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetVivienda(
        vivienda: vivienda,
        store: store,
        tipoEntidad: tipoEntidad,
        seccion: seccion,
        esNuevo: esNuevo,
      ),
    );
  }
}

class _SheetVivienda extends StatefulWidget {
  final EdanVivienda vivienda;
  final EdanStore? store;
  final String tipoEntidad;
  final String seccion;

  /// `true` cuando la vivienda es nueva: la hoja abre **sin tipo de daño
  /// seleccionado** y el usuario debe elegirlo.
  final bool esNuevo;

  const _SheetVivienda({
    required this.vivienda,
    this.store,
    required this.tipoEntidad,
    required this.seccion,
    required this.esNuevo,
  });

  @override
  State<_SheetVivienda> createState() => _SheetViviendaState();
}

class _SheetViviendaState extends State<_SheetVivienda> {
  static const double _precisionMinima = 30;

  late EdanViviendaTipo? _tipo;
  final List<EdanFoto> _fotos = [];
  String? _fotoPath;

  double? _lat;
  double? _lon;
  double _prec = 0;

  bool _capturando = false;
  bool _reintentar = false;
  bool _sacando = false;

  // Windows: entrada manual de coordenadas.
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _coordFormKey = GlobalKey<FormState>();
  static bool get _isWindows => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    // Vivienda nueva: sin tipo de daño preseleccionado (el usuario debe elegir).
    _tipo = widget.esNuevo ? null : widget.vivienda.tipoDano;
    _fotoPath = widget.vivienda.fotografia;
    _lat = widget.vivienda.coordenadaLat == 0 && widget.vivienda.coordenadaLon == 0
        ? null
        : widget.vivienda.coordenadaLat;
    _lon = widget.vivienda.coordenadaLat == 0 && widget.vivienda.coordenadaLon == 0
        ? null
        : widget.vivienda.coordenadaLon;

    if (_isWindows) {
      if (widget.vivienda.coordenadaLat != 0) {
        _latCtrl.text = widget.vivienda.coordenadaLat.toStringAsFixed(6);
      }
      if (widget.vivienda.coordenadaLon != 0) {
        _lonCtrl.text = widget.vivienda.coordenadaLon.toStringAsFixed(6);
      }
    } else if (_lat == null && _lon == null) {
      // Móvil: se solicitan coordenadas GPS frescas al abrir la hoja.
      _capturarCoordenadas();
    }
    _hidratarFotos();
  }

  /// Rehidrata la foto existente de la vivienda desde `fotografias` (V2) para
  /// recuperar su `uuid_fotografia`; así, al re-tomar la foto, `capturarFoto`
  /// purga el registro previo en vez de duplicarlo, y la miniatura muestra el
  /// archivo local aunque sólo se conociera `vivienda.fotografia` (ruta).
  Future<void> _hidratarFotos() async {
    final store = widget.store;
    final uuid = widget.vivienda.uuidRegistro;
    if (store == null || uuid == null || uuid.isEmpty) return;
    try {
      final fotos = await store.cargarFotosDeEntidad(widget.tipoEntidad, uuid);
      if (!mounted || fotos.isEmpty) return;
      setState(() {
        _fotos
          ..clear()
          ..addAll(fotos);
        final rutaLocal = fotos.first.ruta;
        if (rutaLocal.isNotEmpty) _fotoPath = rutaLocal;
      });
    } catch (_) {
      // Silencioso: si falla, se conserva el fallback `vivienda.fotografia`.
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  bool get _tieneFoto =>
      _fotos.isNotEmpty || (_fotoPath != null && _fotoPath!.isNotEmpty);

  bool get _coordsListas => _isWindows
      ? (_latCtrl.text.isNotEmpty && _lonCtrl.text.isNotEmpty)
      : (_lat != null && _lon != null);

  bool _validarCoordenadasWindows() {
    if (!_coordFormKey.currentState!.validate()) return false;
    _lat = double.parse(_latCtrl.text.trim());
    _lon = double.parse(_lonCtrl.text.trim());
    _prec = 10.0;
    return true;
  }

  Future<void> _capturarCoordenadas() async {
    if (_capturando) return;
    setState(() {
      _capturando = true;
      _reintentar = false;
    });
    final pos = await EdanBotonSacarFoto.capturarCoordenadas(
      context,
      precisionMinima: _precisionMinima,
    );
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
        _prec = pos.accuracy;
        _capturando = false;
      });
    } else {
      setState(() {
        _reintentar = true;
        _capturando = false;
      });
    }
  }

  /// Toma (o re-toma) la foto sin cerrar la hoja; actualiza coords y foto.
  Future<void> _tomarFoto() async {
    if (_isWindows) {
      if (!_validarCoordenadasWindows()) return;
    } else {
      setState(() => _capturando = true);
      final pos = await EdanBotonSacarFoto.capturarCoordenadas(
        context,
        precisionMinima: _precisionMinima,
      );
      if (!mounted) return;
      if (pos == null) {
        setState(() {
          _capturando = false;
          _reintentar = true;
        });
        return;
      }
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
        _prec = pos.accuracy;
        _capturando = false;
      });
    }

    final lat = _lat;
    final lon = _lon;
    if (lat == null || lon == null) return;

    setState(() => _sacando = true);
    final ok = await EdanBotonSacarFoto.capturarFoto(
      fotos: _fotos,
      latitud: lat,
      longitud: lon,
      precision: _prec,
      store: widget.store,
      uuidRegistro: widget.vivienda.uuidRegistro,
      tipoEntidad: widget.tipoEntidad,
    );
    if (!mounted) return;
    setState(() {
      _sacando = false;
      if (ok && _fotos.isNotEmpty) _fotoPath = _fotos.first.ruta;
    });
  }

  void _abrirMenuFotoExistente() {
    showModalBottomSheet<void>(
      context: context,
      builder: (menuCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: AppColors.textPrimary),
              title: const Text('Ver foto actual'),
              onTap: () {
                Navigator.of(menuCtx).pop();
                EdanBotonSacarFoto.verFotoCompleta(
                  context,
                  fotos: _fotos,
                  fotografia: _fotos.isEmpty ? _fotoPath : null,
                  coordenadaLat: _lat ?? 0,
                  coordenadaLon: _lon ?? 0,
                  seccion: widget.seccion,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: AppColors.completed),
              title: const Text('Re-tomar foto'),
              subtitle: const Text('Se recapturarán las coordenadas por seguridad'),
              onTap: () {
                Navigator.of(menuCtx).pop();
                _tomarFoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text('Cancelar'),
              onTap: () => Navigator.of(menuCtx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _onSacarFoto() {
    if (_sacando) return;
    if (_isWindows) {
      if (!_validarCoordenadasWindows()) return;
    } else if (_lat == null || _lon == null) {
      return;
    }
    if (_tieneFoto) {
      _abrirMenuFotoExistente();
      return;
    }
    _tomarFoto();
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: AppColors.error,
        ),
      );
  }

  void _guardar() {
    // Windows: valida y normaliza las coordenadas manuales antes que nada.
    if (_isWindows && !_validarCoordenadasWindows()) {
      _aviso('Completá latitud y longitud válidas.');
      return;
    }

    // Nunca aceptar la hoja con campos incompletos.
    final faltantes = <String>[];
    if (_tipo == null) faltantes.add('tipo de daño');
    if (!_coordsListas) faltantes.add('coordenadas');
    if (!_tieneFoto) faltantes.add('foto');

    if (faltantes.isNotEmpty) {
      _aviso('Completá: ${faltantes.join(", ")}.');
      return;
    }

    Navigator.of(context).pop(
      EdanViviendaSheetResult(
        tipoDano: _tipo!,
        coordenadaLat: _lat ?? 0,
        coordenadaLon: _lon ?? 0,
        fotografia: _fotoPath,
        fotos: List<EdanFoto>.of(_fotos),
      ),
    );
  }

  Widget _campoTitulo(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.home_outlined,
                            color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Vivienda',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _campoTitulo('Tipo de daño'),
                  const SizedBox(height: 6),
                  RadioGroup<EdanViviendaTipo>(
                    groupValue: _tipo,
                    onChanged: (v) => setState(() => _tipo = v),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioListTile<EdanViviendaTipo>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('TOTAL'),
                          value: EdanViviendaTipo.total,
                          activeColor: AppColors.primary,
                        ),
                        RadioListTile<EdanViviendaTipo>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('PARCIAL'),
                          value: EdanViviendaTipo.parcial,
                          activeColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _campoTitulo('Coordenadas'),
                  const SizedBox(height: 8),
                  _coordenadasCard(),
                  const SizedBox(height: 16),
                  _campoTitulo('Foto'),
                  const SizedBox(height: 8),
                  _fotoCard(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _guardar,
                          child: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coordenadasCard() {
    if (_isWindows) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Form(
          key: _coordFormKey,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Latitud',
                    hintText: 'ej: -16.500000',
                    prefixIcon: const Icon(Icons.north, size: 16),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Req.';
                    final n = double.tryParse(v.trim());
                    if (n == null) return 'Inválido';
                    if (n < -90 || n > 90) return '-90 a 90';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _lonCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Longitud',
                    hintText: 'ej: -68.000000',
                    prefixIcon: const Icon(Icons.east, size: 16),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Req.';
                    final n = double.tryParse(v.trim());
                    if (n == null) return 'Inválido';
                    if (n < -180 || n > 180) return '-180 a 180';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Widget contenido;
    if (_capturando) {
      contenido = const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Capturando ubicación…',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      );
    } else if (_lat != null && _lon != null) {
      contenido = Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.completed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_lat!.toStringAsFixed(6)}, ${_lon!.toStringAsFixed(6)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_prec > 0)
            Text(
              '±${_prec.toStringAsFixed(0)}m',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      );
    } else {
      contenido = Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.rejected, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'No se pudo obtener la ubicación',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          if (_reintentar)
            TextButton(
              onPressed: _capturarCoordenadas,
              child: const Text('Reintentar'),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: (_lat != null && _lon != null)
            ? AppColors.completed.withValues(alpha: 0.10)
            : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (_lat != null && _lon != null)
              ? AppColors.completed.withValues(alpha: 0.4)
              : AppColors.divider,
        ),
      ),
      child: contenido,
    );
  }

  Widget _fotoCard() {
    final bool completa = _tieneFoto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: completa
            ? AppColors.completed.withValues(alpha: 0.08)
            : AppColors.pending.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: completa
              ? AppColors.completed.withValues(alpha: 0.4)
              : AppColors.pending.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (completa)
                EdanFotoMiniatura(
                  foto: _fotos.isNotEmpty ? _fotos.first : null,
                  fotografia: _fotoPath,
                  width: 56,
                  height: 56,
                  onTap: () => EdanBotonSacarFoto.verFotoCompleta(
                    context,
                    fotos: _fotos,
                    fotografia: _fotos.isEmpty ? _fotoPath : null,
                    coordenadaLat: _lat ?? 0,
                    coordenadaLon: _lon ?? 0,
                    seccion: widget.seccion,
                  ),
                  onRetomar: () => _onSacarFoto(),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.pending.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_camera_outlined,
                      color: AppColors.pending, size: 24),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  completa
                      ? 'Foto capturada'
                      : 'Sin foto — es importante adjuntar evidencia',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: completa ? AppColors.completed : AppColors.pending,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.completed,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.closed.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (_coordsListas && !_sacando) ? _onSacarFoto : null,
              icon: _sacando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      _isWindows
                          ? Icons.image_outlined
                          : Icons.photo_camera_outlined,
                      size: 20,
                    ),
              label: Text(
                _isWindows
                    ? (completa ? 'Cambiar imagen' : 'Seleccionar imagen')
                    : (completa ? 'Editar foto' : 'Sacar foto'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
