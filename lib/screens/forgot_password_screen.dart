import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/reporte_provider.dart';
import '../services/api_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../services/app_logger_ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _carnetController = TextEditingController();
  final _celularController = TextEditingController();
  final _comunidadController = TextEditingController();
  final _nuevaContrasenaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _step1Complete = false;
  bool _isLoading = false;
  int? _idUsuario;

  int? _selectedDepartamento;
  int? _selectedProvincia;
  int? _selectedMunicipio;

  final _api = ApiService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReporteProvider>().loadGeography();
    });
  }

  @override
  void dispose() {
    _carnetController.dispose();
    _celularController.dispose();
    _comunidadController.dispose();
    _nuevaContrasenaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _handleVerifyIdentity() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final idUsuario = await _api.verificarIdentidad(
        carnet: _carnetController.text.trim(),
        celular: _celularController.text.trim(),
        idDepartamento: _selectedDepartamento!,
        idProvincia: _selectedProvincia!,
        idMunicipio: _selectedMunicipio!,
        comunidad: _comunidadController.text.trim().toLowerCase(),
      );

      if (mounted) {
        setState(() {
          _idUsuario = idUsuario;
          _step1Complete = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAppSnackBar(context, 
          SnackBar(
            content: Text(
              e.toString().contains('no coinciden')
                  ? 'Los datos no coinciden con ningún usuario registrado'
                  : 'Error al verificar identidad',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleChangePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _api.cambiarContrasena(
        idUsuario: _idUsuario!,
        nuevaContrasena: _nuevaContrasenaController.text.trim(),
      );

      if (mounted) {
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Contraseña actualizada correctamente'),
            backgroundColor: AppColors.completed,
          ),
        );
        Navigator.of(context).pop({
          'carnet': _carnetController.text.trim(),
          'contrasena': _nuevaContrasenaController.text.trim(),
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAppSnackBar(context, 
          const SnackBar(
            content: Text('Error al cambiar la contraseña'),
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
            title: const Text('Recuperar contraseña'),
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
                    Icon(
                      Icons.lock_reset,
                      size: 64,
                      color: palette.primary,
                    ),
                const SizedBox(height: 16),
                const Text(
                  'Recuperar contraseña',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verifique su identidad para cambiar la contraseña',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (!_step1Complete) ...[
                  _buildSectionTitle('Verificar identidad'),
                  const SizedBox(height: 12),
                  CustomTextField(
                    label: 'Carnet de identidad',
                    hint: 'Ingrese su carnet',
                    controller: _carnetController,
                    keyboardType: TextInputType.text,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingrese su carnet';
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
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingrese su celular';
                      }
                      return null;
                    },
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
                            validator: (value) {
                              if (value == null) {
                                return 'Seleccione un departamento';
                              }
                              return null;
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
                            validator: (value) {
                              if (value == null) {
                                return 'Seleccione una provincia';
                              }
                              return null;
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
                            validator: (value) {
                              if (value == null) {
                                return 'Seleccione un municipio';
                              }
                              return null;
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
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingrese su comunidad';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  CustomButton(
                    text: 'Verificar identidad',
                    onPressed: _handleVerifyIdentity,
                    isLoading: _isLoading,
                  ),
                ],
                if (_step1Complete) ...[
                  _buildSectionTitle('Nueva contraseña'),
                  const SizedBox(height: 12),
                  CustomTextField(
                    label: 'Nueva contraseña',
                    hint: 'Ingrese una contraseña',
                    controller: _nuevaContrasenaController,
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
                      if (value != _nuevaContrasenaController.text) {
                        return 'Las contraseñas no coinciden';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  CustomButton(
                    text: 'Cambiar contraseña',
                    onPressed: _handleChangePassword,
                    isLoading: _isLoading,
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Volver al inicio de sesión',
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
}
