import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/connectivity_provider.dart';
import '../../widgets/perfil_tab.dart';

class UgrScreen extends StatefulWidget {
  const UgrScreen({super.key});

  @override
  State<UgrScreen> createState() => _UgrScreenState();
}

class _UgrScreenState extends State<UgrScreen> {
  int _selectedIndex = 0;
  bool _isProfileEditing = false;
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
                            color: isOnline
                                ? AppColors.completed
                                : AppColors.error,
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
                                color: isOnline
                                    ? Colors.white
                                    : AppColors.error,
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
                    _buildPlaceholder(Icons.home_outlined, 'Reportes'),
                    _buildPlaceholder(Icons.list_outlined, 'Historial'),
                    _buildPlaceholder(
                      Icons.location_city_outlined,
                      'Municipio',
                    ),
                    _buildPerfilTab(),
                  ],
                ),
              ),
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
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home),
                    label: 'Reportes',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.list_outlined),
                    activeIcon: Icon(Icons.list),
                    label: 'Historial',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.location_city_outlined),
                    activeIcon: Icon(Icons.location_city),
                    label: 'Municipio',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outlined),
                    activeIcon: Icon(Icons.person),
                    label: 'Perfil',
                  ),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildPerfilTab() {
    return PerfilTab(
      key: _perfilTabKey,
    );
  }

  String _getTabTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Reportes';
      case 1:
        return 'Historial';
      case 2:
        return 'Municipio';
      case 3:
        return 'Perfil';
      default:
        return 'Reportes';
    }
  }

  Widget _buildPlaceholder(IconData icon, String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Palettes.edan.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Disponible próximamente',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
