import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/reporte_provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/sync_manager.dart';
import '../screens/login_screen.dart';

class PerfilTab extends StatefulWidget {
  final VoidCallback? onLogout;

  const PerfilTab({super.key, this.onLogout});

  @override
  State<PerfilTab> createState() => PerfilTabState();
}

class PerfilTabState extends State<PerfilTab> {
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _celularController = TextEditingController();
  final _comunidadController = TextEditingController();
  final _carnetController = TextEditingController();
  final _correoController = TextEditingController();
  final _cargoController = TextEditingController();
  final _usuarioController = TextEditingController();

  int? _selectedDepartamento;
  int? _selectedProvincia;
  int? _selectedMunicipio;
  String? _departamentoNombre;
  String? _provinciaNombre;
  String? _municipioNombre;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  void resetEditing() {
    if (_isEditing) {
      _loadProfile();
      setState(() => _isEditing = false);
    }
  }

  void _loadProfile() {
    final profile = AuthService.instance.getSavedProfile();
    _nombreController.text = profile['nombre'] as String? ?? '';
    _celularController.text = profile['celular'] as String? ?? '';
    _comunidadController.text = profile['comunidad'] as String? ?? '';
    _carnetController.text = profile['carnet'] as String? ?? '';
    _correoController.text = profile['correo'] as String? ?? '';
    _cargoController.text = profile['cargo'] as String? ?? '';
    _usuarioController.text = profile['usuario'] as String? ?? '';
    _selectedDepartamento = profile['id_departamento'] as int?;
    _selectedProvincia = profile['id_provincia'] as int?;
    _selectedMunicipio = profile['id_municipio'] as int?;
    _departamentoNombre = profile['departamento_nombre'] as String?;
    _provinciaNombre = profile['provincia_nombre'] as String?;
    _municipioNombre = profile['municipio_nombre'] as String?;

    if (_selectedDepartamento != null) {
      final rp = context.read<ReporteProvider>();
      rp.loadGeography();
      rp.loadProvincias(_selectedDepartamento!);
      if (_selectedProvincia != null) {
        rp.loadMunicipios(_selectedProvincia!, _selectedDepartamento!);
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _celularController.dispose();
    _comunidadController.dispose();
    _carnetController.dispose();
    _correoController.dispose();
    _cargoController.dispose();
    _usuarioController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final rp = context.read<ReporteProvider>();

    String? depNombre;
    String? provNombre;
    String? munNombre;

    if (_selectedDepartamento != null) {
      final dep = rp.departamentos.where((d) => d.id == _selectedDepartamento);
      if (dep.isNotEmpty) depNombre = dep.first.nombre;
    }
    if (_selectedProvincia != null) {
      final prov = rp.provincias.where((p) => p.id == _selectedProvincia);
      if (prov.isNotEmpty) provNombre = prov.first.nombre;
    }
    if (_selectedMunicipio != null) {
      final mun = rp.municipios.where((m) => m.id == _selectedMunicipio);
      if (mun.isNotEmpty) munNombre = mun.first.nombre;
    }

    await AuthService.instance.saveProfileLocally({
      'nombre': _nombreController.text.trim(),
      'celular': _celularController.text.trim(),
      'carnet': _carnetController.text.trim(),
      'comunidad': _comunidadController.text.trim(),
      'correo': _correoController.text.trim(),
      'cargo': _cargoController.text.trim(),
      'usuario': _usuarioController.text,
      'id_departamento': _selectedDepartamento,
      'departamento_nombre': depNombre,
      'id_provincia': _selectedProvincia,
      'provincia_nombre': provNombre,
      'id_municipio': _selectedMunicipio,
      'municipio_nombre': munNombre,
    });

    final userId = AuthService.instance.userId;
    var serverOk = true;
    if (userId != null) {
      try {
        await ApiService.instance.updateUsuario(
          userId,
          nombre: _nombreController.text.trim(),
          celular: _celularController.text.trim(),
          comunidad: _comunidadController.text.trim(),
          correo: _correoController.text.trim(),
          cargo: _cargoController.text.trim(),
          idDepartamento: _selectedDepartamento,
          idProvincia: _selectedProvincia,
          idMunicipio: _selectedMunicipio,
        );
      } catch (_) {
        serverOk = false;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serverOk
                ? 'Perfil actualizado exitosamente'
                : 'Cambios guardados localmente, no se pudo sincronizar con el servidor',
          ),
          backgroundColor:
              serverOk ? AppColors.completed : AppColors.error,
        ),
      );
      _loadProfile();
      setState(() => _isEditing = false);
    }

    setState(() => _isSaving = false);
  }

  Future<void> _handleLogout() async {
    if (widget.onLogout != null) {
      widget.onLogout!.call();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text(
          'Esta seguro que desea cerrar sesion?\n\n'
          'Se eliminaran todos los datos locales del dispositivo '
          '(reportes, borradores, imagenes y catalogos).\n'
          'Al iniciar sesion nuevamente se recuperara toda la informacion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar sesion'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final auth = context.read<AuthProvider>();
      final reporte = context.read<ReporteProvider>();
      final nav = Navigator.of(context);
      reporte.clearData();
      SyncManager.instance.reset();
      await auth.logout();
      if (mounted) {
        nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
          child: CircularProgressIndicator(
              color: PaletteScope.of(context).primary));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _isEditing ? _buildEditForm() : _buildProfileView(),
    );
  }

  Widget _buildProfileView() {
    final name = _nombreController.text;
    final initials = name.isNotEmpty
        ? name.split(' ').map((s) => s.isNotEmpty ? s[0] : '').take(2).join()
        : 'U';

    return Column(
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: PaletteScope.of(context).primary,
          child: Text(
            initials.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _buildInfoCard([
          _infoRow('Usuario', _usuarioController.text),
          _infoRow('Carnet de identidad', _carnetController.text),
          _infoRow('Celular', _celularController.text),
          _infoRow('Correo', _correoController.text),
          _infoRow('Cargo', _cargoController.text),
          _infoRow('Comunidad', _comunidadController.text),
          _infoRow('Departamento', _departamentoNombre),
          _infoRow('Provincia', _provinciaNombre),
          _infoRow('Municipio', _municipioNombre),
          _infoRow('Rol', context.watch<AuthProvider>().rolName),
        ]),
        const SizedBox(height: 20),
        _buildOfflineDataButton(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() => _isEditing = true);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar perfil'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PaletteScope.of(context).primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, color: AppColors.error),
            label: const Text('Cerrar sesion',
                style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineDataButton() {
    return Consumer<ReporteProvider>(
      builder: (context, rp, child) {
        final estadosCount = rp.estados.length;
        final categoriasCount = rp.categorias.length;
        final tiposCount = rp.tiposEvento.length;
        final hasData = estadosCount > 0 || categoriasCount > 0 || tiposCount > 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.download_for_offline,
                      size: 20,
                      color: PaletteScope.of(context).primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Cargar datos para uso offline',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasData) ...[
                const SizedBox(height: 8),
                Text(
                  '$estadosCount estados  ·  $tiposCount tipos  ·  $categoriasCount categorias',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Cargando catalogos...'),
                        backgroundColor: AppColors.inProgress,
                      ),
                    );
                    final result = await rp.fetchAndCacheCatalogs();
                    if (context.mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${result['estados']} estados, ${result['tipos']} tipos y ${result['categorias']} categorias cargados',
                          ),
                          backgroundColor: AppColors.completed,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Actualizar catalogos'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PaletteScope.of(context).primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: rows
            .map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: row,
                ))
            .toList(),
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value?.isNotEmpty == true ? value! : '--',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Los cambios seran verificados.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionCard(
            'DATOS PERSONALES',
            [
              _buildTextField('Nombre completo', _nombreController, validator: (v) {
                if (v == null || v.isEmpty) return 'Ingrese su nombre';
                return null;
              }),
              const SizedBox(height: 12),
              _buildTextField('Celular', _celularController,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildTextField('Correo', _correoController,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _buildTextField('Cargo', _cargoController),
              const SizedBox(height: 12),
              _buildTextField('Comunidad', _comunidadController),
            ],
          ),
          const SizedBox(height: 16),
          Consumer<ReporteProvider>(
            builder: (context, rp, child) {
              return _buildSectionCard(
                'UBICACION GEOGRAFICA',
                [
                  DropdownButtonFormField<int>(
                    initialValue: rp.departamentos.any((d) => d.id == _selectedDepartamento)
                        ? _selectedDepartamento
                        : null,
                    decoration: _fieldDecoration('Departamento', rp.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null),
                    items: rp.departamentos
                        .map((dep) => DropdownMenuItem(
                            value: dep.id, child: Text(dep.nombre)))
                        .toList(),
                    onChanged: rp.isLoading
                        ? null
                        : (value) {
                            setState(() {
                              _selectedDepartamento = value;
                              _selectedProvincia = null;
                              _selectedMunicipio = null;
                            });
                            if (value != null) {
                              rp.loadProvincias(value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: rp.provincias.any((p) => p.id == _selectedProvincia)
                        ? _selectedProvincia
                        : null,
                    decoration: _fieldDecoration('Provincia', rp.isLoadingProvincias
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null),
                    items: rp.provincias
                        .map((prov) => DropdownMenuItem(
                            value: prov.id, child: Text(prov.nombre)))
                        .toList(),
                    onChanged: _selectedDepartamento == null || rp.isLoadingProvincias
                        ? null
                        : (value) {
                            setState(() {
                              _selectedProvincia = value;
                              _selectedMunicipio = null;
                            });
                            if (value != null) {
                              rp.loadMunicipios(value, _selectedDepartamento!);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: rp.municipios.any((m) => m.id == _selectedMunicipio)
                        ? _selectedMunicipio
                        : null,
                    decoration: _fieldDecoration('Municipio', rp.isLoadingMunicipios
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null),
                    items: rp.municipios
                        .map((mun) => DropdownMenuItem(
                            value: mun.id, child: Text(mun.nombre)))
                        .toList(),
                    onChanged: _selectedProvincia == null || rp.isLoadingMunicipios
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
          _buildSectionCard(
            'IDENTIFICACION',
            [
              _buildTextField('Usuario', _usuarioController, enabled: false),
              const SizedBox(height: 12),
              _buildTextField('Carnet de identidad', _carnetController, enabled: false),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PaletteScope.of(context).primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _loadProfile();
                    setState(() => _isEditing = false);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PaletteScope.of(context).primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, Widget? suffixIcon) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: PaletteScope.of(context).primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      suffixIcon: suffixIcon,
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: enabled ? const Color(0xFFF7F8FA) : AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: PaletteScope.of(context).primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
