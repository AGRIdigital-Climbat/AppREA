import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../models/edan.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_helper.dart';
import 'ugr_edan_form_screen.dart';
import 'ugr_edan_preview_screen.dart';

class UgrEdanListScreen extends StatefulWidget {
  const UgrEdanListScreen({super.key});

  @override
  State<UgrEdanListScreen> createState() => _UgrEdanListScreenState();
}

class _UgrEdanListScreenState extends State<UgrEdanListScreen> {
  List<Edan> _edanes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarEdanes();
  }

  Future<void> _cargarEdanes() async {
    setState(() => _loading = true);
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) {
        setState(() => _edanes = []);
        return;
      }
      final edanes = await DatabaseHelper.instance.getEdans(userId);
      if (!mounted) return;
      setState(() => _edanes = edanes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _edanes = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '-';
    try {
      final dt = DateTime.parse(fecha);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return fecha;
    }
  }

  Color _estadoColor(String estado) {
    return switch (estado) {
      'borrador' => AppColors.pending,
      'enviado' => AppColors.aprobado,
      'observado' => AppColors.rechazado,
      _ => AppColors.textSecondary,
    };
  }

  IconData _estadoIcon(String estado) {
    return switch (estado) {
      'borrador' => Icons.edit_note,
      'enviado' => Icons.check_circle,
      'observado' => Icons.warning_amber,
      _ => Icons.file_present,
    };
  }

  String _estadoLabel(String estado) {
    return switch (estado) {
      'borrador' => 'Borrador',
      'enviado' => 'Enviado',
      'observado' => 'Observado',
      _ => estado,
    };
  }

  void _abrirEdan(Edan edan) {
    final sincronizado = edan.sincronizado;
    if (sincronizado) {
      _verEdan(edan);
    } else {
      _editarEdan(edan);
    }
  }

  void _editarEdan(Edan edan) async {
    final result = await Navigator.push<Edan>(
      context,
      MaterialPageRoute(
        builder: (_) => UgrEdanFormScreen(edanAEditar: edan),
      ),
    );
    if (result != null && mounted) {
      _cargarEdanes();
    }
  }

  void _verEdan(Edan edan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UgrEdanPreviewScreen(edan: edan),
      ),
    );
  }

  void _eliminarEdan(Edan edan) async {
    if (edan.sincronizado) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede eliminar un EDAN sincronizado'),
          backgroundColor: AppColors.rechazado,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar EDAN'),
        content: Text(
          '¿Estás seguro de eliminar este borrador?\n\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.rechazado),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await DatabaseHelper.instance.deleteEdan(edan.idLocal!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('EDAN eliminado'),
          backgroundColor: AppColors.aprobado,
        ),
      );
      _cargarEdanes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al eliminar'),
          backgroundColor: AppColors.rechazado,
        ),
      );
    }
  }

  void _crearNuevoEdan() async {
    final result = await Navigator.push<Edan>(
      context,
      MaterialPageRoute(
        builder: (_) => const UgrEdanFormScreen(),
      ),
    );
    if (result != null && mounted) {
      _cargarEdanes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Mis EDAN',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _edanes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_open_outlined,
                        size: 64,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay EDAN guardados',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Crea tu primer EDAN para comenzar',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _edanes.length,
                  itemBuilder: (_, i) {
                    final e = _edanes[i];
                    final sincronizado = e.sincronizado;
                    final esBorrador = e.estado == 'borrador';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _abrirEdan(e),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _estadoIcon(e.estado),
                                    size: 20,
                                    color: _estadoColor(e.estado),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      e.codigoEdan.isNotEmpty
                                          ? e.codigoEdan
                                          : 'EDAN sin código',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _estadoColor(e.estado)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _estadoLabel(e.estado),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _estadoColor(e.estado),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Fecha: ${_fmtFecha(e.fechaLlenado)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      e.municipioNombre ?? 'Sin municipio',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (esBorrador)
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _editarEdan(e),
                                        icon: const Icon(Icons.edit, size: 18),
                                        label: const Text('Editar'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: primary,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!esBorrador && !sincronizado)
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _verEdan(e),
                                        icon:
                                            const Icon(Icons.visibility, size: 18),
                                        label: const Text('Ver'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: primary,
                                          side: const BorderSide(color: AppColors.divider),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (sincronizado)
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _verEdan(e),
                                        icon:
                                            const Icon(Icons.visibility, size: 18),
                                        label: const Text('Previsualizar'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.textSecondary,
                                          side: const BorderSide(color: AppColors.divider),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  if (esBorrador)
                                    IconButton(
                                      onPressed: () => _eliminarEdan(e),
                                      icon: const Icon(Icons.delete_outline),
                                      color: AppColors.rechazado,
                                      tooltip: 'Eliminar',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearNuevoEdan,
        backgroundColor: primary,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo EDAN'),
      ),
    );
  }
}
