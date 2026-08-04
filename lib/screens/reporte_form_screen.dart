import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import '../models/reporte_offline.dart';
import '../services/auth_service.dart';
import '../services/permission_service.dart';
import '../services/location_service.dart';
import '../services/image_service.dart';
import '../providers/reporte_provider.dart';
import '../widgets/custom_text_field.dart';
import 'reporte_preview_screen.dart';

class ReporteFormScreen extends StatefulWidget {
  final ReporteOffline? reporte;

  const ReporteFormScreen({super.key, this.reporte});

  @override
  State<ReporteFormScreen> createState() => _ReporteFormScreenState();
}

class _ReporteFormScreenState extends State<ReporteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _comunidadController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _fechaController = TextEditingController();
  final _horaController = TextEditingController();
  final _departamentoController = TextEditingController();
  final _provinciaController = TextEditingController();
  final _municipioController = TextEditingController();

  int? _selectedDepartamento;
  int? _selectedProvincia;
  int? _selectedMunicipio;
  int? _selectedTipoEvento;
  DateTime _fechaEvento = DateTime.now();
  int? _horaNumero;
  bool? _esPM;
  double? _latitud;
  double? _longitud;
  double? _precision;
  bool _obteniendoCoords = false;
  bool _coordsManual = false;
  bool _coordsError = false;
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final List<String> _imagenes = [];
  final List<int> _categoriasSeleccionadas = [];

  final ImagePicker _picker = ImagePicker();
  @override
  void initState() {
    super.initState();

    if (widget.reporte != null) {
      _loadFromReporte(widget.reporte!);
    } else {
      _fechaController.text =
          '${_fechaEvento.day}/${_fechaEvento.month}/${_fechaEvento.year}';
      _horaController.text = '';
      _loadProfileData();
    }
  }

  void _loadFromReporte(ReporteOffline r) {
    _selectedDepartamento = r.departamentoId;
    _selectedProvincia = r.provinciaId;
    _selectedMunicipio = r.municipioId;
    _departamentoController.text = r.departamentoNombre ?? '';
    _provinciaController.text = r.provinciaNombre ?? '';
    _municipioController.text = r.municipioNombre ?? '';
    _comunidadController.text = r.comunidad;
    _selectedTipoEvento = r.tipoEventoId;
    _descripcionController.text = r.descripcion ?? '';
    _latitud = r.coordenadaLat;
    _longitud = r.coordenadaLon;
    _coordsManual = r.coordenadaLat != null;

    if (r.imagenes != null && r.imagenes!.isNotEmpty) {
      _imagenes.addAll(r.imagenes!);
    }
    if (r.categorias != null) {
      _categoriasSeleccionadas.addAll(r.categorias!);
    }

    try {
      _fechaEvento = DateTime.parse(r.fechaEvento);
      _fechaController.text =
          '${_fechaEvento.day}/${_fechaEvento.month}/${_fechaEvento.year}';
    } catch (_) {
      _fechaController.text = r.fechaEvento;
    }

    if (r.horaEvento != null && r.horaEvento!.isNotEmpty) {
      _horaController.text = r.horaEvento!;
      final horaText = r.horaEvento!;
      final parts = horaText.split(':');
      if (parts.length >= 1) {
        final h24 = int.tryParse(parts[0]) ?? 0;
        if (h24 == 0) {
          _horaNumero = 12;
          _esPM = false;
        } else if (h24 == 12) {
          _horaNumero = 12;
          _esPM = true;
        } else if (h24 > 12) {
          _horaNumero = h24 - 12;
          _esPM = true;
        } else {
          _horaNumero = h24;
          _esPM = false;
        }
      }
    }

    if (_latitud != null) {
      _latController.text = _latitud!.toStringAsFixed(6);
    }
    if (_longitud != null) {
      _lonController.text = _longitud!.toStringAsFixed(6);
    }
  }

  void _loadProfileData() {
    final profile = AuthService.instance.getSavedProfile();
    final depId = profile['id_departamento'] as int?;
    final provId = profile['id_provincia'] as int?;
    final munId = profile['id_municipio'] as int?;
    if (profile.isNotEmpty) {
      _selectedDepartamento = depId;
      _selectedProvincia = provId;
      _selectedMunicipio = munId;
      _comunidadController.text = profile['comunidad'] as String? ?? '';
      _departamentoController.text = profile['departamento_nombre'] as String? ?? '';
      _provinciaController.text = profile['provincia_nombre'] as String? ?? '';
      _municipioController.text = profile['municipio_nombre'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _comunidadController.dispose();
    _descripcionController.dispose();
    _fechaController.dispose();
    _horaController.dispose();
    _departamentoController.dispose();
    _provinciaController.dispose();
    _municipioController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<void> _obtenerCoordenadasConPrecision() async {
    setState(() => _obteniendoCoords = true);
    final hasPermission = await PermissionService.requestLocationPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() => _obteniendoCoords = false);
        PermissionService.showPermissionDeniedDialog(context, 'ubicacion');
      }
      return;
    }

    final start = DateTime.now();
    const timeout = Duration(seconds: 45);
    double? bestLat, bestLon, bestAcc;

    while (DateTime.now().difference(start) < timeout && mounted) {
      final pos = await LocationService().getCurrentLocation();
      if (pos != null && mounted) {
        if (bestAcc == null || pos.accuracy < bestAcc) {
          bestLat = pos.latitude;
          bestLon = pos.longitude;
          bestAcc = pos.accuracy;
        }
        if (pos.accuracy <= 30) {
          setState(() {
            _latitud = pos.latitude;
            _longitud = pos.longitude;
            _precision = pos.accuracy;
            _obteniendoCoords = false;
            _coordsError = false;
          });
          return;
        }
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    if (!mounted) return;
    setState(() => _obteniendoCoords = false);

    if (bestAcc != null) {
      setState(() {
        _latitud = bestLat;
        _longitud = bestLon;
        _precision = bestAcc;
        _coordsError = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Precision alcanzada: ± ${bestAcc.toStringAsFixed(0)} m'),
          backgroundColor: AppColors.pending,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener la ubicacion'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaEvento,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _fechaEvento = picked;
        _fechaController.text =
            '${picked.day}/${picked.month}/${picked.year}';
      });
    }
  }

  void _onSelectHora(int? h) {
    setState(() {
      _horaNumero = h;
      _actualizarHoraController();
    });
  }

  void _onToggleAmpm(bool? pm) {
    setState(() {
      _esPM = _esPM == pm ? null : pm;
      _actualizarHoraController();
    });
  }

  void _actualizarHoraController() {
    if (_horaNumero != null && _esPM != null) {
      final h24 = _esPM!
          ? (_horaNumero == 12 ? 12 : _horaNumero! + 12)
          : (_horaNumero == 12 ? 0 : _horaNumero!);
      _horaController.text = '${h24.toString().padLeft(2, '0')}:00';
    } else {
      _horaController.text = '';
    }
  }

  Widget _ampmBtn(String label, bool isPM) {
    final selected = _esPM == isPM;
    return GestureDetector(
      onTap: () => _onToggleAmpm(isPM),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
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

  Future<void> _takePhoto() async {
    final hasPermission = await PermissionService.requestCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        PermissionService.showPermissionDeniedDialog(context, 'camara');
      }
      return;
    }
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (image != null) {
      final savedPath = await ImageService().saveImageLocally(image);
      setState(() {
        _imagenes
          ..clear()
          ..add(savedPath);
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      final savedPath = await ImageService().saveImageLocally(image);
      setState(() {
        _imagenes
          ..clear()
          ..add(savedPath);
      });
    }
  }

  void _goToPreview() {
    if (!_formKey.currentState!.validate()) return;
    if (_horaNumero == null || _esPM == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione la hora del evento'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (_latitud == null || _longitud == null) {
      setState(() => _coordsError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registre las coordenadas del evento'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportePreviewScreen(
          departamentoId: _selectedDepartamento ?? 0,
          provinciaId: _selectedProvincia ?? 0,
          municipioId: _selectedMunicipio ?? 0,
          comunidad: _comunidadController.text.trim(),
          departamentoNombre: _departamentoController.text,
          provinciaNombre: _provinciaController.text,
          municipioNombre: _municipioController.text,
          fechaEvento:
              '${_fechaEvento.year}-${_fechaEvento.month.toString().padLeft(2, '0')}-${_fechaEvento.day.toString().padLeft(2, '0')}',
          fechaEventoDisplay: _fechaController.text,
          horaEvento: _horaController.text,
          tipoEventoId: _selectedTipoEvento ?? 1,
          descripcion: _descripcionController.text.trim(),
          imagenes: _imagenes,
          categorias: _categoriasSeleccionadas,
          latitud: _latitud,
          longitud: _longitud,
          reporteExistente: widget.reporte,
        ),
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
              onPressed: _goToPreview,
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
    final userId = AuthService.instance.userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe iniciar sesión para guardar el borrador'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final reporteProvider = context.read<ReporteProvider>();
    final reporte = ReporteOffline(
      usuarioId: userId,
      departamentoId: _selectedDepartamento ?? 0,
      provinciaId: _selectedProvincia ?? 0,
      municipioId: _selectedMunicipio ?? 0,
      comunidad: _comunidadController.text.trim(),
      departamentoNombre: _departamentoController.text.isNotEmpty
          ? _departamentoController.text
          : null,
      provinciaNombre: _provinciaController.text.isNotEmpty
          ? _provinciaController.text
          : null,
      municipioNombre: _municipioController.text.isNotEmpty
          ? _municipioController.text
          : null,
      fechaEvento:
          '${_fechaEvento.year}-${_fechaEvento.month.toString().padLeft(2, '0')}-${_fechaEvento.day.toString().padLeft(2, '0')}',
      horaEvento: _horaController.text.isNotEmpty ? _horaController.text : null,
      tipoEventoId: _selectedTipoEvento ?? 1,
      coordenadaLat: _latitud,
      coordenadaLon: _longitud,
      descripcion: _descripcionController.text.trim().isEmpty
          ? null
          : _descripcionController.text.trim(),
      categorias: _categoriasSeleccionadas.isNotEmpty
          ? List.of(_categoriasSeleccionadas)
          : null,
      imagenes: _imagenes.isNotEmpty ? List.of(_imagenes) : null,
      esBorrador: true,
      fechaCreacion: DateTime.now(),
    );
    await reporteProvider.guardarBorrador(reporte);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Borrador guardado. Puede editarlo o enviarlo cuando quiera'),
        backgroundColor: Colors.orange,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.reporte != null ? 'Editar Reporte' : 'Nuevo Reporte',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: PaletteScope.of(context).primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Datos del Evento'),
              _buildSectionHint('Seleccione tipo, fecha y hora del suceso.'),
              const SizedBox(height: 12),
              _buildEventFields(),
              const SizedBox(height: 24),
              _buildSectionTitle('Descripcion'),
              _buildSectionHint('Detalle breve de lo ocurrido.'),
              const SizedBox(height: 12),
              _buildDescripcionField(),
              const SizedBox(height: 24),
              _buildSectionTitle('Ubicacion'),
              _buildSectionHint('Datos cargados de su perfil.'),
              const SizedBox(height: 12),
              _buildUbicacionSection(),
              const SizedBox(height: 24),
              _buildSectionTitle('Coordenadas GPS'),
              _buildSectionHint('Registre la coordenada o tome la ubicacion donde ocurrio el evento. (obligatorio)'),
              const SizedBox(height: 8),
              _buildCoordinatesSection(),
              const SizedBox(height: 24),
              _buildSectionTitle('Evidencia Fotografica'),
              _buildSectionHint('Capture o seleccione imagenes del evento.'),
              const SizedBox(height: 12),
              _buildPhotoSection(),
              const SizedBox(height: 24),
              _buildSectionTitle('Categorias de Afectacion'),
              _buildSectionHint('Seleccione a quienes afecto el evento.'),
              const SizedBox(height: 12),
              _buildCategoriesSection(),
              const SizedBox(height: 24),
              _buildVerifyBanner(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildActionsBar(),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildSectionHint(String hint) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        hint,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildEventFields() {
    return Column(
      children: [
        Consumer<ReporteProvider>(
          builder: (context, rp, child) {
            return DropdownButtonFormField<int>(
              initialValue: _selectedTipoEvento,
              decoration: InputDecoration(
                labelText: 'Tipo de Evento *',
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
                  borderSide: BorderSide(
                    color: PaletteScope.of(context).primary,
                    width: 2,
                  ),
                ),
              ),
              items: rp.tiposEvento.isEmpty
                  ? const [
                      DropdownMenuItem(value: 1, child: Text('Inundacion')),
                      DropdownMenuItem(value: 2, child: Text('Riada')),
                      DropdownMenuItem(value: 3, child: Text('Deslizamiento')),
                      DropdownMenuItem(value: 4, child: Text('Helada')),
                      DropdownMenuItem(value: 5, child: Text('Granizada')),
                      DropdownMenuItem(value: 6, child: Text('Sequia')),
                      DropdownMenuItem(value: 7, child: Text('Incendios')),
                      DropdownMenuItem(value: 8, child: Text('Otros')),
                    ]
                  : rp.tiposEvento
                      .map((t) => DropdownMenuItem(
                          value: t.idTipoEvento, child: Text(t.nombre)))
                      .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTipoEvento = value;
                });
              },
              validator: (value) {
                if (value == null) return 'Seleccione tipo de evento';
                return null;
              },
            );
          },
        ),
        const SizedBox(height: 16),
        CustomTextField(
          label: 'Fecha inicial del Evento *',
          controller: _fechaController,
          onTap: _selectDate,
          readOnly: true,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Seleccione fecha';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hora del Evento *',
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
                  child: DropdownButtonFormField<int?>(
                    initialValue: _horaNumero,
                    decoration: InputDecoration(
                      hintText: 'Hr',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
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
                          color: PaletteScope.of(context).primary,
                          width: 2,
                        ),
                      ),
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('--')),
                            for (int i = 1; i <= 12; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text('${i.toString().padLeft(2, '0')}:00'),
                              ),
                    ],
                    onChanged: _onSelectHora,
                  ),
                ),
                const SizedBox(width: 8),
                _ampmBtn('AM', false),
                const SizedBox(width: 4),
                _ampmBtn('PM', true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDescripcionField() {
    return CustomTextField(
      label: '',
      hint: 'Ej: Inundacion por desborde de rio en la zona baja...',
      controller: _descripcionController,
      maxLines: 4,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Ingrese una descripcion';
        }
        return null;
      },
    );
  }

  Widget _buildUbicacionSection() {
    final items = <({String label, String value})>[
      if (_departamentoController.text.isNotEmpty)
        (label: 'Departamento', value: _departamentoController.text),
      if (_provinciaController.text.isNotEmpty)
        (label: 'Provincia', value: _provinciaController.text),
      if (_municipioController.text.isNotEmpty)
        (label: 'Municipio', value: _municipioController.text),
      if (_comunidadController.text.isNotEmpty)
        (label: 'Comunidad', value: _comunidadController.text),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Ubicación registrada',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.completed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Perfil',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.completed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      '${e.label}:',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Complete su perfil para registrar ubicación.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordinatesSection() {
    final hasCoords = _latitud != null && _longitud != null;
    final coordsInvalid = _coordsError && !hasCoords;

    Color precColor() {
      if (_precision == null) return AppColors.textSecondary;
      return _precision! <= 30 ? AppColors.completed : AppColors.pending;
    }

    String precText() {
      if (_precision == null) return '';
      return ' ± ${_precision!.toStringAsFixed(0)} m';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: coordsInvalid ? AppColors.error : AppColors.divider,
          width: coordsInvalid ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToggleRow(),
          const SizedBox(height: 14),
          _coordDisplayRow(hasCoords, precColor(), precText()),
          const SizedBox(height: 14),
          if (_coordsManual) _manualInputs() else _gpsButton(hasCoords),
          if (coordsInvalid) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: AppColors.error,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Las coordenadas son obligatorias',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleRow() {
    return Row(
      children: [
        _toggleBtn('GPS', Icons.my_location, false),
        const SizedBox(width: 8),
        _toggleBtn('Manual', Icons.edit, true),
      ],
    );
  }

  Widget _toggleBtn(String label, IconData icon, bool isManual) {
    final selected = _coordsManual == isManual;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _coordsManual = isManual),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppColors.primary.withValues(alpha: 0.1) : null,
          foregroundColor: selected ? AppColors.primary : AppColors.textSecondary,
          side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _gpsButton(bool hasCoords) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _obteniendoCoords ? null : _obtenerCoordenadasConPrecision,
        icon: _obteniendoCoords
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary,
                ),
              )
            : const Icon(Icons.my_location, size: 18),
        label: Text(_obteniendoCoords
            ? 'Buscando precision < 30 m...'
            : hasCoords
                ? 'Obtener nuevas coordenadas'
                : 'Obtener coordenadas'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _coordDisplayRow(bool hasCoords, Color precColor, String precText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasCoords ? precColor.withValues(alpha: 0.08) : AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hasCoords ? precColor.withValues(alpha: 0.3) : AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            hasCoords ? Icons.location_on : Icons.location_off,
            size: 18,
            color: hasCoords ? precColor : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hasCoords
                ? RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      children: [
                        TextSpan(
                          text: '${_latitud!.toStringAsFixed(6)}, ${_longitud!.toStringAsFixed(6)}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: precColor),
                        ),
                        TextSpan(
                          text: precText,
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: precColor.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    'Sin coordenadas',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
          if (hasCoords)
            GestureDetector(
              onTap: () => setState(() {
                _latitud = null;
                _longitud = null;
                _precision = null;
                _latController.clear();
                _lonController.clear();
              }),
              child: const Icon(Icons.close, size: 18, color: AppColors.error),
            ),
        ],
      ),
    );
  }

  Widget _manualInputs() {
    return Row(
      children: [
        Expanded(
          child: CustomTextField(
            label: 'Latitud',
            hint: 'Ej: -16.500000',
            controller: _latController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onChanged: _aplicarManual,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: CustomTextField(
            label: 'Longitud',
            hint: 'Ej: -68.150000',
            controller: _lonController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onChanged: _aplicarManual,
          ),
        ),
      ],
    );
  }

  void _aplicarManual(String _) {
    final lat = double.tryParse(_latController.text.trim().replaceAll(',', '.'));
    final lon = double.tryParse(_lonController.text.trim().replaceAll(',', '.'));
    if (lat != null && lon != null) {
      setState(() {
        _latitud = lat;
        _longitud = lon;
        _precision = null;
        _coordsError = false;
      });
    }
  }

  Widget _buildPhotoSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tomar Foto'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeria'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
        if (_imagenes.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _imagenes.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_imagenes[index]),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: AppColors.surface,
                            child: const Icon(
                              Icons.broken_image,
                              size: 40,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 12,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _imagenes.removeAt(index);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoriesSection() {
    return Consumer<ReporteProvider>(
      builder: (context, rp, child) {
        final categorias = rp.categorias.isEmpty
            ? [
                {'id': 1, 'nombre': 'Ninas y Ninos'},
                {'id': 2, 'nombre': 'Adolescentes'},
                {'id': 3, 'nombre': 'Mujeres Lactantes'},
                {'id': 4, 'nombre': 'Mujeres Embarazadas'},
                {'id': 5, 'nombre': 'Adultos Mayores'},
                {'id': 6, 'nombre': 'Personas con Discapacidad'},
                {'id': 7, 'nombre': 'Personas con Enfermedad Inhabilitante'},
              ]
            : rp.categorias
                .map((c) => {'id': c.idCategoria, 'nombre': c.nombre})
                .toList();

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categorias.map((cat) {
            final isSelected = _categoriasSeleccionadas.contains(cat['id']);
            return FilterChip(
              label: Text(cat['nombre'] as String),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _categoriasSeleccionadas.add(cat['id'] as int);
                  } else {
                    _categoriasSeleccionadas.remove(cat['id']);
                  }
                });
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildVerifyBanner() {
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
          Icon(Icons.info_outline, color: AppColors.pending, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Importante: Toda la informacion proporcionada debe ser correcta y sera verificada por las autoridades correspondientes.',
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
}
