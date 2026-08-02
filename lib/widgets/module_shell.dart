import 'package:flutter/material.dart';
import '../config/theme.dart';

class ModuleTab {
  final String title;
  final IconData icon;
  final IconData activeIcon;
  final WidgetBuilder builder;
  final Widget? fab;

  const ModuleTab({
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.builder,
    this.fab,
  });
}

class ModuleShell extends StatefulWidget {
  final String moduleName;
  final List<ModuleTab> tabs;
  final double bottomPadding;

  const ModuleShell({
    super.key,
    required this.moduleName,
    required this.tabs,
    this.bottomPadding = 100,
  });

  @override
  State<ModuleShell> createState() => _ModuleShellState();
}

class _ModuleShellState extends State<ModuleShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final currentTab = widget.tabs[_selectedIndex];

    return Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(
            index: _selectedIndex,
            children: widget.tabs
                .map((tab) => tab.builder(context))
                .toList(),
          ),
        ),
        if (currentTab.fab != null)
          Positioned(
            bottom: 80,
            right: 16,
            child: currentTab.fab!,
          ),
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) {
                  setState(() => _selectedIndex = index);
                },
                backgroundColor: Colors.white,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.textSecondary,
                type: BottomNavigationBarType.fixed,
                elevation: 0,
                items: widget.tabs
                    .map(
                      (tab) => BottomNavigationBarItem(
                        icon: Icon(tab.icon),
                        activeIcon: Icon(tab.activeIcon),
                        label: tab.title,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
