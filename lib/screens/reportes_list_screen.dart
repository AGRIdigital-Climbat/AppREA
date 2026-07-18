import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/reporte_provider.dart';
import '../widgets/reporte_card.dart';
import 'reporte_detail_screen.dart';

class ReportesListScreen extends StatefulWidget {
  const ReportesListScreen({super.key});

  @override
  State<ReportesListScreen> createState() => _ReportesListScreenState();
}

class _ReportesListScreenState extends State<ReportesListScreen> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _buildReportesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildFilterChip('Todos', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('Pendientes', 'pending'),
          const SizedBox(width: 8),
          _buildFilterChip('Sincronizados', 'synced'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return Expanded(
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _filterStatus = value;
          });
        },
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildReportesList() {
    return Consumer<ReporteProvider>(
      builder: (context, reporteProvider, child) {
        if (reporteProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          );
        }

        var reportes = reporteProvider.reportes;

        if (_filterStatus == 'pending') {
          reportes = reportes.where((r) => !r.sincronizado).toList();
        } else if (_filterStatus == 'synced') {
          reportes = reportes.where((r) => r.sincronizado).toList();
        }

        if (reportes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 80,
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No hay reportes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _filterStatus == 'all'
                      ? 'Cree su primer reporte de evento adverso'
                      : 'No hay reportes con este filtro',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await reporteProvider.loadReportes();
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: reportes.length,
            itemBuilder: (context, index) {
              final reporte = reportes[index];
              return ReporteCard(
                reporte: reporte,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReporteDetailScreen(reporte: reporte),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
