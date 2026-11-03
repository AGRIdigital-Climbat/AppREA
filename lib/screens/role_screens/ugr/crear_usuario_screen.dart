import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../models/usuario.dart';
import '../../../../services/api_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../services/app_logger_ui.dart';

class CrearUsuarioScreen extends StatefulWidget {
  final int? idMunicipio;
  final int? idProvincia;
  final int? idDepartamento;
  final Usuario? usuario;

  const CrearUsuarioScreen({
    super.key,
    this.idMunicipio,
    this.idProvincia,
    this.idDepartamento,
    this.usuario,
  });

  @override
  State<CrearUsuarioScreen> createState() => _CrearUsuarioScreenState();
}

class _CrearUsuarioScreenState extends State<CrearUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _confirmarContrasenaController = TextEditingController();
  final _nombreController = TextEditingController();
  final _celularController = TextEditingController();
  final _carnetController = TextEditingController();
  final _comunidadController = TextEditingController();
  final _correoController = TextEditingController();
  final _cargoController = TextEditingController();

  bool get _modoEdicion => widget.usuario != null;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    if (u != null) {
      _nombreController.text = u.nombre;
      _celularController.text = u.celular ?? '';
      _carnetController.text = u.carnet ?? '';
      _comunidadController.text = u.comunidad ?? '';
      _correoController.text = u.correo ?? '';
    }
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _contrasenaController.dispose();
    _confirmarContrasenaController.dispose();
    _nombreController.dispose();
    _celularController.dispose();
    _carnetController.dispose();
    _comunidadController.dispose();
    _correoController.dispose();
    _cargoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    if (!ConnectivityService().isConnected) {
      if (!mounted) return;
      showAppSnackBar(context, 
        const SnackBar(
          content: Text('Sin conexión. Verifica tu red y reintenta.'),
          backgroundColor: AppColors.pending,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      if (_modoEdicion) {
        final actualizado = await ApiService.instance.updateUsuario(
          widget.usuario!.idUsuario,
          nombre: _nombreController.text.trim(),
          celular: _celularController.text.trim().isEmpty
              ? null
              : _celularController.text.trim(),
          comunidad: _comunidadController.text.trim().isEmpty
              ? null
              : _comunidadController.text.trim(),
          correo: _correoController.text.trim(),
          idDepartamento: widget.idDepartamento,
          idProvincia: widget.idProvincia,
          idMunicipio: widget.idMunicipio,
        );
        if (!mounted) return;
        Navigator.pop(context, actualizado);
        return;
      }

      final usuario = await ApiService.instance.createUsuario(
        usuario: _usuarioController.text.trim(),
        contrasena: _contrasenaController.text.trim(),
        nombre: _nombreController.text.trim(),
        celular: _celularController.text.trim().isEmpty
            ? null
            : _celularController.text.trim(),
        carnet: _carnetController.text.trim().isEmpty
            ? null
            : _carnetController.text.trim(),
        comunidad: _comunidadController.text.trim().isEmpty
            ? null
            : _comunidadController.text.trim(),
        correo: _correoController.text.trim().isEmpty
            ? null
            : _correoController.text.trim(),
        cargo: _cargoController.text.trim().isEmpty
            ? null
            : _cargoController.text.trim(),
        idDepartamento: widget.idDepartamento,
        idProvincia: widget.idProvincia,
        idMunicipio: widget.idMunicipio,
        idRol: 8,
      );

      if (!mounted) return;
      Navigator.pop(context, usuario.idUsuario);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 
        SnackBar(
          content: Text(
              '${_modoEdicion ? 'Error al actualizar usuario' : 'Error al crear usuario'}: ${ApiService.traducirError(e)}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_modoEdicion ? 'Editar Alcalde' : 'Nuevo Usuario Alcalde'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_modoEdicion) ...[
              _subtitulo('Datos de acceso'),
              CustomTextField(
                label: 'Usuario *',
                controller: _usuarioController,
                hint: 'Ej: alcalde.lapaz',
                textCapitalization: TextCapitalization.none,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Contraseña *',
                controller: _contrasenaController,
                hint: 'Mínimo 6 caracteres',
                obscureText: true,
                validator: (v) => v == null || v.trim().length < 6
                    ? 'Mínimo 6 caracteres'
                    : null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Confirmar contraseña *',
                controller: _confirmarContrasenaController,
                hint: 'Repite la contraseña',
                obscureText: true,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (v.trim() != _contrasenaController.text.trim()) {
                    return 'Las contraseñas no coinciden';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recuerda informar al alcalde sobre estas credenciales '
                        '(usuario y contraseña) para que pueda acceder a la app.',
                        style: TextStyle(
                          fontSize: 12,
                          color: primary.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            _subtitulo('Datos personales'),
              CustomTextField(
                label: 'Nombre completo *',
                controller: _nombreController,
                hint: 'Ej: Juan Pérez',
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Celular',
                controller: _celularController,
                hint: 'Ej: 70700000',
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(20),
                ],
              ),
              const SizedBox(height: 12),
              if (!_modoEdicion) ...[
                CustomTextField(
                  label: 'Carnet',
                  controller: _carnetController,
                  hint: 'Ej: 1234567',
                ),
                const SizedBox(height: 12),
              ],
              CustomTextField(
                label: 'Comunidad',
                controller: _comunidadController,
                hint: 'Ej: La Paz',
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Correo',
                controller: _correoController,
                hint: 'Ej: alcalde@municipio.gob.bo',
                keyboardType: TextInputType.emailAddress,
              ),
              if (!_modoEdicion) ...[
                const SizedBox(height: 12),
                CustomTextField(
                  label: 'Cargo',
                  controller: _cargoController,
                  hint: 'Ej: Alcalde Municipal',
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _loading ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subtitulo(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
