import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../config/role_router.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReporteProvider>().loadGeography();
    });
  }

  @override
  void dispose() {
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
        ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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
                  'Complete los datos para registrarse',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
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
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Correo electrónico',
                  hint: 'Ej. usuario@correo.com',
                  controller: _correoController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Cargo',
                  hint: 'Ej. Responsable Local',
                  controller: _cargoController,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Consumer<ReporteProvider>(
                  builder: (context, reporteProvider, child) {
                    return Column(
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: _selectedDepartamento,
                          decoration: InputDecoration(
                            labelText: 'Departamento',
                            border: const OutlineInputBorder(),
                            suffixIcon: reporteProvider.isLoading
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
                                : null,
                          ),
                          items: reporteProvider.departamentos.map((dep) {
                            return DropdownMenuItem(
                              value: dep.id,
                              child: Text(dep.nombre),
                            );
                          }).toList(),
                          onChanged: reporteProvider.isLoading
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
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedProvincia,
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
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedMunicipio,
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
                          'Importante: Toda la información proporcionada debe ser correcta y será verificada por las autoridades correspondientes.',
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
                      onPressed: _handleRegister,
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
