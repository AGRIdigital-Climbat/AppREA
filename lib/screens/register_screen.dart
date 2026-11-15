import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../config/role_router.dart';
import '../services/app_logger_ui.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contrasenaController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _nombreController = TextEditingController();
  final _celularController = TextEditingController();
  final _carnetController = TextEditingController();
  final _comunidadController = TextEditingController();
  final _correoController = TextEditingController();
  final _cargoController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  int? _selectedDepartamento;
  int? _selectedProvincia;
  int? _selectedMunicipio;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _contrasenaController,
      _confirmarController,
      _nombreController,
      _celularController,
      _carnetController,
      _comunidadController,
      _correoController,
      _cargoController,
    ]) {
      controller.addListener(_onFormChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReporteProvider>().loadGeography();
    });
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _isFormComplete {
    if (_nombreController.text.trim().isEmpty) return false;
    if (_carnetController.text.trim().isEmpty) return false;
    if (_contrasenaController.text.length < 6) return false;
    if (_confirmarController.text != _contrasenaController.text) return false;
    if (_celularController.text.trim().isEmpty) return false;
    if (_correoController.text.trim().isEmpty) return false;
    if (_cargoController.text.trim().isEmpty) return false;
    if (_comunidadController.text.trim().isEmpty) return false;
    if (_selectedDepartamento == null) return false;
    if (_selectedProvincia == null) return false;
    if (_selectedMunicipio == null) return false;
    return true;
  }

  @override
  void dispose() {
    for (final controller in [
      _contrasenaController,
      _confirmarController,
      _nombreController,
      _celularController,
      _carnetController,
      _comunidadController,
      _correoController,
      _cargoController,
    ]) {
      controller.removeListener(_onFormChanged);
    }
    _contrasenaController.dispose();
    _confirmarController.dispose();
    _nombreController.dispose();
    _celularController.dispose();
    _carnetController.dispose();
    _comunidadController.dispose();
    _correoController.dispose();
    _cargoController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final reporteProvider = context.read<ReporteProvider>();

    String? depNombre;
    String? provNombre;
    String? munNombre;

    if (_selectedDepartamento != null) {
      final dep = reporteProvider.departamentos
          .where((d) => d.id == _selectedDepartamento);
      if (dep.isNotEmpty) depNombre = dep.first.nombre;
    }
    if (_selectedProvincia != null) {
      final prov = reporteProvider.provincias
          .where((p) => p.id == _selectedProvincia);
      if (prov.isNotEmpty) provNombre = prov.first.nombre;
    }
    if (_selectedMunicipio != null) {
      final mun = reporteProvider.municipios
          .where((m) => m.id == _selectedMunicipio);
      if (mun.isNotEmpty) munNombre = mun.first.nombre;
    }

    final success = await authProvider.register(
      usuario: _carnetController.text.trim(),
      contrasena: _contrasenaController.text.trim(),
      nombre: _nombreController.text.trim(),
      celular: _celularController.text.trim(),
      carnet: _carnetController.text.trim(),
      comunidad: _comunidadController.text.trim(),
      correo: _correoController.text.trim(),
      cargo: _cargoController.text.trim(),
      idDepartamento: _selectedDepartamento,
      departamentoNombre: depNombre,
      idProvincia: _selectedProvincia,
      provinciaNombre: provNombre,
      idMunicipio: _selectedMunicipio,
      municipioNombre: munNombre,
    );

    if (mounted) {
      if (success) {
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Usuario registrado exitosamente'),
            backgroundColor: AppColors.completed,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => homeForRole(authProvider)),
          (route) => false,
        );
      } else {
        showAppSnackBar(context, 
          SnackBar(
            content: Text(authProvider.error ?? 'Error al registrar'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const palette = Palettes.sinager;
    return PaletteScope(
      palette: palette,
      child: Theme(
        data: AppTheme.buildTheme(palette),
        child: Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: const Text('Registro'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'Crear Cuenta',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Registro de Responsable Local — encargado de reportar el EDAN de su localidad o comunidad',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Si es UGR u otro cargo público, solicite su registro por otro canal.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                CustomTextField(
                  label: 'Nombre y apellido completo',
                  hint: 'Ej. Juan Perez',
                  controller: _nombreController,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingrese su nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Carnet de identidad (será tu usuario)',
                  hint: 'Solo número',
                  controller: _carnetController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingrese su carnet';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Este carnet será tu usuario para iniciar sesión',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Contraseña nueva',
                  hint: 'Min. 6 caracteres',
                  controller: _contrasenaController,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingrese una contraseña';
                    }
                    if (value.length < 6) {
                      return 'Mínimo 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Confirmar contraseña',
                  hint: 'Repita la contraseña',
                  controller: _confirmarController,
                  obscureText: _obscureConfirm,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirm = !_obscureConfirm);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirme la contraseña';
                    }
                    if (value != _contrasenaController.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Número de celular',
                  hint: 'Ej. 76000000',
                  controller: _celularController,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingrese su número de celular';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Correo electrónico',
                  hint: 'Ej. usuario@correo.com',
                  controller: _correoController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingrese su correo electrónico';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Cargo',
                  hint: 'Ej. Responsable Local',
                  controller: _cargoController,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingrese su cargo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Consumer<ReporteProvider>(
                  builder: (context, reporteProvider, child) {
                    return Column(
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Estos campos no representan tu lugar de residencia o nacimiento, '
                            'sino el lugar que representas: el departamento, provincia y municipio '
                            'donde desempeñarás tus funciones y registrarás la información.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedDepartamento,
                          validator: (value) => value == null ? 'Seleccione un departamento' : null,
decoration: InputDecoration(
                            labelText: 'Departamento',
                            border: const OutlineInputBorder(),
                            suffixIcon: reporteProvider.isLoadingGeografia
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : (reporteProvider.departamentos.isEmpty &&
                                        reporteProvider.geoError)
                                    ? IconButton(
                                        tooltip: 'Reintentar cargar departamentos',
                                        icon: const Icon(Icons.refresh),
                                        onPressed: () =>
                                            reporteProvider.loadGeography(),
                                      )
                                    : null,
                          ),
                          items: reporteProvider.departamentos.map((dep) {
                            return DropdownMenuItem(
                              value: dep.id,
                              child: Text(dep.nombre),
                            );
                          }).toList(),
                          onChanged: reporteProvider.isLoadingGeografia
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedDepartamento = value;
                                    _selectedProvincia = null;
                                    _selectedMunicipio = null;
                                  });
                                  if (value != null) {
                                    reporteProvider.loadProvincias(value);
                                  }
                                },
                        ),
                        if (reporteProvider.geoError &&
                            reporteProvider.departamentos.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    size: 14, color: AppColors.error),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Sin respuesta. Toca el icono para reintentar.',
                                    style: TextStyle(
                                        fontSize: 12, color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedProvincia,
                          validator: (value) => value == null ? 'Seleccione una provincia' : null,
decoration: InputDecoration(
                            labelText: 'Provincia',
                            border: const OutlineInputBorder(),
                            suffixIcon: reporteProvider.isLoadingProvincias
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : (_selectedDepartamento != null &&
                                        reporteProvider.provincias.isEmpty &&
                                        reporteProvider.provinciasError)
                                    ? IconButton(
                                        tooltip: 'Reintentar cargar provincias',
                                        icon: const Icon(Icons.refresh),
                                        onPressed: () => reporteProvider
                                            .loadProvincias(_selectedDepartamento!),
                                      )
                                    : null,
                          ),
                          items: reporteProvider.provincias.map((prov) {
                            return DropdownMenuItem(
                              value: prov.id,
                              child: Text(prov.nombre),
                            );
                          }).toList(),
                          onChanged: _selectedDepartamento == null ||
                                  reporteProvider.isLoadingProvincias
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedProvincia = value;
                                    _selectedMunicipio = null;
                                  });
                                  if (value != null) {
                                    reporteProvider.loadMunicipios(
                                      value,
                                      _selectedDepartamento!,
                                    );
                                  }
                                },
                        ),
                        if (_selectedDepartamento != null &&
                            reporteProvider.provinciasError &&
                            reporteProvider.provincias.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    size: 14, color: AppColors.error),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Sin respuesta. Toca el icono para reintentar.',
                                    style: TextStyle(
                                        fontSize: 12, color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedMunicipio,
                          validator: (value) => value == null ? 'Seleccione un municipio' : null,
decoration: InputDecoration(
                            labelText: 'Municipio',
                            border: const OutlineInputBorder(),
                            suffixIcon: reporteProvider.isLoadingMunicipios
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : (_selectedProvincia != null &&
                                        _selectedDepartamento != null &&
                                        reporteProvider.municipios.isEmpty &&
                                        reporteProvider.municipiosError)
                                    ? IconButton(
                                        tooltip: 'Reintentar cargar municipios',
                                        icon: const Icon(Icons.refresh),
                                        onPressed: () => reporteProvider
                                            .loadMunicipios(
                                          _selectedProvincia!,
                                          _selectedDepartamento!,
                                        ),
                                      )
                                    : null,
                          ),
                          items: reporteProvider.municipios.map((mun) {
                            return DropdownMenuItem(
                              value: mun.id,
                              child: Text(mun.nombre),
                            );
                          }).toList(),
                          onChanged: _selectedProvincia == null ||
                                  reporteProvider.isLoadingMunicipios
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedMunicipio = value;
                                  });
                                },
                        ),
                        if (_selectedProvincia != null &&
                            _selectedDepartamento != null &&
                            reporteProvider.municipiosError &&
                            reporteProvider.municipios.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    size: 14, color: AppColors.error),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Sin respuesta. Toca el icono para reintentar.',
                                    style: TextStyle(
                                        fontSize: 12, color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Comunidad',
                  hint: 'Ingrese su comunidad',
                  controller: _comunidadController,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingrese su comunidad';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.pending.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.pending.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.pending,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Importante: El reporte será validado por la Unidad de Gestión de Riesgos (UGR) antes de su envio oficial con los documentos de respaldo.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Consumer<AuthProvider>(
                  builder: (context, auth, child) {
                    return CustomButton(
                      text: 'Registrarse',
                      onPressed: _isFormComplete ? _handleRegister : null,
                      isLoading: auth.isLoading,
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    '¿Ya tiene cuenta? Inicie sesión',
                    style: TextStyle(
                      color: palette.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}
