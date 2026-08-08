import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../config/theme.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/custom_text_field.dart';

class CrearUsuarioScreen extends StatefulWidget {
  final int? idMunicipio;
  final int? idProvincia;
  final int? idDepartamento;

  const CrearUsuarioScreen({
    super.key,
    this.idMunicipio,
    this.idProvincia,
    this.idDepartamento,
  });

  @override
  State<CrearUsuarioScreen> createState() => _CrearUsuarioScreenState();
}

class _CrearUsuarioScreenState extends State<CrearUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _nombreController = TextEditingController();
  final _celularController = TextEditingController();
  final _carnetController = TextEditingController();
  final _comunidadController = TextEditingController();
  final _correoController = TextEditingController();
  final _cargoController = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _usuarioController.dispose();
    _contrasenaController.dispose();
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

    setState(() => _loading = true);

    try {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear usuario: $e'),
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
        title: const Text('Nuevo Usuario Alcalde'),
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
              const SizedBox(height: 24),
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
              CustomTextField(
                label: 'Carnet',
                controller: _carnetController,
                hint: 'Ej: 1234567',
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Cargo',
                controller: _cargoController,
                hint: 'Ej: Alcalde Municipal',
              ),
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
