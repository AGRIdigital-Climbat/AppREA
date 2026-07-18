import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import '../providers/reporte_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../models/reporte_offline.dart';
import '../services/permission_service.dart';
import '../services/location_service.dart';
import '../services/image_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';

class ReporteFormScreen extends StatefulWidget {
  const ReporteFormScreen({super.key});

  @override
  State<ReporteFormScreen> createState() => _ReporteFormScreenState();
}

class _ReporteFormScreenState extends State<ReporteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _comunidadController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _fechaController = TextEditingController();
  final _horaController = TextEditingController();

  int? _selectedDepartamento;
  int? _selectedProvincia;
  int? _selectedMunicipio;
  int? _selectedTipoEvento;
  DateTime _fechaEvento = DateTime.now();
  TimeOfDay _horaEvento = TimeOfDay.now();
  double? _latitud;
  double? _longitud;
  final List<String> _imagenes = [];
  final List<int> _categoriasSeleccionadas = [];
  bool _isSubmitting = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fechaController.text =
        '${_fechaEvento.day}/${_fechaEvento.month}/${_fechaEvento.year}';
    _horaController.text =
        '${_horaEvento.hour.toString().padLeft(2, '0')}:${_horaEvento.minute.toString().padLeft(2, '0')}';
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _comunidadController.dispose();
    _descripcionController.dispose();
    _fechaController.dispose();
    _horaController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    final hasPermission = await PermissionService.requestLocationPermission();
    if (hasPermission) {
      final position = await LocationService().getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _latitud = position.latitude;
          _longitud = position.longitude;
        });
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaEvento,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
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

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaEvento,
    );
    if (picked != null) {
      setState(() {
        _horaEvento = picked;
        _horaController.text =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _takePhoto() async {
    final hasPermission = await PermissionService.requestCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        PermissionService.showPermissionDeniedDialog(context, 'cámara');
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
        _imagenes.add(savedPath);
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final images = await _picker.pickMultiImage(
      imageQuality: 80,
    );

    for (final image in images.take(5 - _imagenes.length)) {
      final savedPath = await ImageService().saveImageLocally(image);
      setState(() {
        _imagenes.add(savedPath);
      });
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDepartamento == null ||
        _selectedProvincia == null ||
        _selectedMunicipio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione departamento, provincia y municipio'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final authProvider = context.read<AuthProvider>();
    final reporteProvider = context.read<ReporteProvider>();

    final reporte = ReporteOffline(
      usuarioId: authProvider.userId!,
      departamentoId: _selectedDepartamento!,
      provinciaId: _selectedProvincia!,
      municipioId: _selectedMunicipio!,
      comunidad: _comunidadController.text.trim(),
      fechaEvento:
          '${_fechaEvento.year}-${_fechaEvento.month.toString().padLeft(2, '0')}-${_fechaEvento.day.toString().padLeft(2, '0')}',
      horaEvento: _horaController.text,
      tipoEventoId: _selectedTipoEvento ?? 1,
      coordenadaLat: _latitud,
      coordenadaLon: _longitud,
      descripcion: _descripcionController.text.trim(),
      categorias:
          _categoriasSeleccionadas.isNotEmpty ? _categoriasSeleccionadas : null,
      imagenes: _imagenes.isNotEmpty ? _imagenes : null,
      fechaCreacion: DateTime.now(),
    );

    await reporteProvider.crearReporte(reporte);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<ConnectivityProvider>().isConnected
                ? 'Reporte enviado exitosamente'
                : 'Reporte guardado localmente',
          ),
          backgroundColor: AppColors.completed,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Nuevo Reporte'),
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
              _buildSectionTitle('Ubicación'),
              const SizedBox(height: 16),
              _buildLocationFields(),
              const SizedBox(height: 24),
              _buildSectionTitle('Datos del Evento'),
              const SizedBox(height: 16),
              _buildEventFields(),
              const SizedBox(height: 24),
              _buildSectionTitle('Evidencia Fotográfica'),
              const SizedBox(height: 16),
              _buildPhotoSection(),
              const SizedBox(height: 24),
              _buildSectionTitle('Categorías de Afectación'),
              const SizedBox(height: 16),
              _buildCategoriesSection(),
              const SizedBox(height: 32),
              CustomButton(
                text: 'Enviar Reporte',
                onPressed: _submitReport,
                isLoading: _isSubmitting,
                icon: Icons.send,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
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

  Widget _buildLocationFields() {
    return Consumer<ReporteProvider>(
      builder: (context, reporteProvider, child) {
        return Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: _selectedDepartamento,
              decoration: const InputDecoration(
                labelText: 'Departamento *',
                border: OutlineInputBorder(),
              ),
              items: reporteProvider.departamentos.map((dep) {
                return DropdownMenuItem(
                  value: dep.id,
                  child: Text(dep.nombre),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDepartamento = value;
                  _selectedProvincia = null;
                  _selectedMunicipio = null;
                });
                if (value != null) {
                  reporteProvider.loadProvincias(value);
                }
              },
              validator: (value) {
                if (value == null) return 'Seleccione un departamento';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _selectedProvincia,
              decoration: const InputDecoration(
                labelText: 'Provincia *',
                border: OutlineInputBorder(),
              ),
              items: reporteProvider.provincias.map((prov) {
                return DropdownMenuItem(
                  value: prov.id,
                  child: Text(prov.nombre),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedProvincia = value;
                  _selectedMunicipio = null;
                });
                if (value != null) {
                  reporteProvider.loadMunicipios(value);
                }
              },
              validator: (value) {
                if (value == null) return 'Seleccione una provincia';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _selectedMunicipio,
              decoration: const InputDecoration(
                labelText: 'Municipio *',
                border: OutlineInputBorder(),
              ),
              items: reporteProvider.municipios.map((mun) {
                return DropdownMenuItem(
                  value: mun.id,
                  child: Text(mun.nombre),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMunicipio = value;
                });
              },
              validator: (value) {
                if (value == null) return 'Seleccione un municipio';
                return null;
              },
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Comunidad *',
              hint: 'Nombre de la comunidad',
              controller: _comunidadController,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingrese la comunidad';
                }
                return null;
              },
            ),
            if (_latitud != null && _longitud != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.completed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: AppColors.completed,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ubicación: ${_latitud!.toStringAsFixed(4)}, ${_longitud!.toStringAsFixed(4)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.completed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEventFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                label: 'Fecha *',
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
            ),
            const SizedBox(width: 16),
            Expanded(
              child: CustomTextField(
                label: 'Hora',
                controller: _horaController,
                onTap: _selectTime,
                readOnly: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _selectedTipoEvento,
          decoration: const InputDecoration(
            labelText: 'Tipo de Evento *',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Inundación')),
            DropdownMenuItem(value: 2, child: Text('Riada')),
            DropdownMenuItem(value: 3, child: Text('Deslizamiento')),
            DropdownMenuItem(value: 4, child: Text('Helada')),
            DropdownMenuItem(value: 5, child: Text('Granizada')),
            DropdownMenuItem(value: 6, child: Text('Sequía')),
            DropdownMenuItem(value: 7, child: Text('Incendios')),
            DropdownMenuItem(value: 8, child: Text('Otros')),
          ],
          onChanged: (value) {
            setState(() {
              _selectedTipoEvento = value;
            });
          },
          validator: (value) {
            if (value == null) return 'Seleccione tipo de evento';
            return null;
          },
        ),
        const SizedBox(height: 16),
        CustomTextField(
          label: 'Descripción',
          hint: 'Describa el evento...',
          controller: _descripcionController,
          maxLines: 4,
        ),
      ],
    );
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
                label: const Text('Galería'),
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
                        image: DecorationImage(
                          image: NetworkImage(_imagenes[index]),
                          fit: BoxFit.cover,
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
    final categorias = [
      {'id': 1, 'nombre': 'Niñas y Niños'},
      {'id': 2, 'nombre': 'Adolescentes'},
      {'id': 3, 'nombre': 'Mujeres Lactantes'},
      {'id': 4, 'nombre': 'Mujeres Embarazadas'},
      {'id': 5, 'nombre': 'Adultos Mayores'},
      {'id': 6, 'nombre': 'Personas con Discapacidad'},
      {'id': 7, 'nombre': 'Personas con Enfermedad Inhabilitante'},
    ];

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
  }
}
