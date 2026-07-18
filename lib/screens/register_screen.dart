import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _nombreController = TextEditingController();
  final _celularController = TextEditingController();
  final _comunidadController = TextEditingController();

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
    _usuarioController.dispose();
    _contrasenaController.dispose();
    _nombreController.dispose();
    _celularController.dispose();
    _comunidadController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      usuario: _usuarioController.text.trim(),
      contrasena: _contrasenaController.text,
      nombre: _nombreController.text.trim(),
      celular: _celularController.text.trim(),
      comunidad: _comunidadController.text.trim(),
      idDepartamento: _selectedDepartamento,
      idProvincia: _selectedProvincia,
      idMunicipio: _selectedMunicipio,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario registrado exitosamente'),
            backgroundColor: AppColors.completed,
          ),
        );
        Navigator.of(context).pop();
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
    return Scaffold(
      backgroundColor: AppColors.background,
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
                  label: 'Nombre completo',
                  hint: 'Ingrese su nombre',
                  controller: _nombreController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingrese su nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Usuario',
                  hint: 'Ingrese un usuario',
                  controller: _usuarioController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingrese un usuario';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Contraseña',
                  hint: 'Ingrese una contraseña',
                  controller: _contrasenaController,
                  obscureText: true,
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
                  label: 'Celular',
                  hint: 'Ingrese su celular',
                  controller: _celularController,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Comunidad',
                  hint: 'Ingrese su comunidad',
                  controller: _comunidadController,
                ),
                const SizedBox(height: 24),
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
                                    reporteProvider.loadMunicipios(value);
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
                  child: const Text(
                    '¿Ya tiene cuenta? Inicie sesión',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
