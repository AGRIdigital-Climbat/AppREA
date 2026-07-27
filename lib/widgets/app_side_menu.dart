import 'package:flutter/material.dart';
import '../config/theme.dart';

class SideMenuItem {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  final String? sectionTitle;
  final bool showDivider;

  const SideMenuItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    this.sectionTitle,
    this.showDivider = false,
  });
}

class AppSideMenu extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final int selectedIndex;
  final ValueChanged<int> onItemTap;
  final String userName;
  final String roleName;
  final List<SideMenuItem> items;
  final VoidCallback onLogout;

  const AppSideMenu({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.selectedIndex,
    required this.onItemTap,
    required this.userName,
    required this.roleName,
    required this.items,
    required this.onLogout,
  });

  @override
  State<AppSideMenu> createState() => _AppSideMenuState();
}

class _AppSideMenuState extends State<AppSideMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: widget.isExpanded ? 260 : 64,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: const Border(
          right: BorderSide(
            color: AppColors.divider,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(child: _buildMenuItems()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: EdgeInsets.symmetric(
        horizontal: widget.isExpanded ? 16 : 0,
        vertical: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFC0392B), Color(0xFFE74C3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
      ),
      child: widget.isExpanded ? _buildExpandedHeader() : _buildCollapsedHeader(),
    );
  }

  Widget _buildExpandedHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.shield,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SINAGER-SAT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.userName,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.roleName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedHeader() {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.shield,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'REA',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItems() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: _buildItems(),
    );
  }

  List<Widget> _buildItems() {
    final widgets = <Widget>[];

    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final isSelected = i == widget.selectedIndex;

      if (item.sectionTitle != null) {
        if (i > 0) {
          widgets.add(const SizedBox(height: 8));
        }
        if (widget.isExpanded) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              child: Text(
                item.sectionTitle!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 1.2,
                ),
              ),
            ),
          );
        } else {
          widgets.add(const SizedBox(height: 8));
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                height: 1,
                color: AppColors.divider,
              ),
            ),
          );
        }
      }

      if (item.showDivider && i > 0) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Container(
              height: 1,
              color: AppColors.divider,
            ),
          ),
        );
      }

      widgets.add(_buildItemTile(item, isSelected, i));
    }

    return widgets;
  }

  Widget _buildItemTile(SideMenuItem item, bool isSelected, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onItemTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: EdgeInsets.symmetric(
              horizontal: widget.isExpanded ? 12 : 0,
              vertical: widget.isExpanded ? 10 : 10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: widget.isExpanded
                ? _buildExpandedItem(item, isSelected)
                : _buildCollapsedItem(item, isSelected),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedItem(SideMenuItem item, bool isSelected) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSelected ? item.activeIcon : item.icon,
            size: 20,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            item.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
        if (isSelected)
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  Widget _buildCollapsedItem(SideMenuItem item, bool isSelected) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSelected ? item.activeIcon : item.icon,
            size: 20,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.title,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.primary : const Color(0xFF9CA3AF),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onLogout,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isExpanded ? 12 : 0,
              vertical: 10,
            ),
            child: widget.isExpanded
                ? Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Cerrar sesion',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Salir',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFEF4444),
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
