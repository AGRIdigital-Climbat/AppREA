import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/connectivity_provider.dart';
import '../../widgets/perfil_tab.dart';
import '../municipio_reportes_screen.dart';
import 'ugr/ugr_dashboard_tab.dart';
import 'ugr/ugr_edan_tab.dart';
import 'ugr/ugr_reportes_tab.dart';
import 'ugr/ugr_sheets.dart';

class UgrScreen extends StatefulWidget {
  const UgrScreen({super.key});

  @override
  State<UgrScreen> createState() => _UgrScreenState();
}

class _UgrScreenState extends State<UgrScreen> {
  int _selectedIndex = 0;
  bool _isProfileEditing = false;
  final _edanTabKey = GlobalKey<UgrEdanTabState>();
  final _perfilTabKey = GlobalKey<PerfilTabState>();

  @override
  Widget build(BuildContext context) {
    const palette = Palettes.edan;
    return PaletteScope(
      palette: palette,
      child: Theme(
        data: AppTheme.buildTheme(palette),
        child: Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: Text(_getTabTitle()),
            actions: [
              Consumer<ConnectivityProvider>(
                builder: (context, connectivity, child) {
                  final isOnline = connectivity.isConnected;
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isOnline ? AppColors.completed : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOnline ? AppColors.completed : AppColors.error,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOnline ? Icons.wifi : Icons.wifi_off,
                          size: 12,
                          color: isOnline ? Colors.white : AppColors.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isOnline ? 'En linea' : 'Sin conexion',
                          style: TextStyle(
                            fontSize: 11,
                            color: isOnline ? Colors.white : AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                const UgrDashboardTab(),
                const UgrReportesTab(),
                UgrEdanTab(key: _edanTabKey),
                const MunicipioReportesTab(),
                PerfilTab(key: _perfilTabKey),
              ],
            ),
          ),
          floatingActionButton: _buildFab(),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
                if (_isProfileEditing) {
                  _isProfileEditing = false;
                  _perfilTabKey.currentState?.resetEditing();
                }
              });
            },
            selectedItemColor: palette.primary,
            unselectedItemColor: AppColors.textSecondary,
            backgroundColor: AppColors.surface,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Inicio',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined),
                activeIcon: Icon(Icons.receipt_long),
                label: 'Reportes',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.assessment_outlined),
                activeIcon: Icon(Icons.assessment),
                label: 'EDAN',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: 'Mapa',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildFab() {
    switch (_selectedIndex) {
      case 0:
        return FloatingActionButton(
          onPressed: () => showUgrGlobalSearch(context),
          tooltip: 'Buscar',
          child: const Icon(Icons.search),
        );
      case 1:
        return null;
      case 2:
        return FloatingActionButton(
          onPressed: () => showUgrNuevoEdan(
            context,
            onGuardar: (edan) {
              _edanTabKey.currentState?.addEdan(edan);
            },
          ),
          tooltip: 'Nuevo EDAN',
          child: const Icon(Icons.add),
        );
      default:
        return null;
    }
  }

  String _getTabTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Inicio';
      case 1:
        return 'Reportes';
      case 2:
        return 'EDAN';
      case 3:
        return 'Mapa';
      case 4:
        return 'Perfil';
      default:
        return 'Inicio';
    }
  }
}
