import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import 'smart_fab.dart';

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = context.isWideScreen;

    if (isWide) {
      // Layout Desktop / PC / Tablet (NavigationRail lateral)
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onTap,
              labelType: NavigationRailLabelType.all,
              leading: Column(
                children: [
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.home_work_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Omni Lar',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: -0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SmartFAB(isExtended: true),
                  const SizedBox(height: 12),
                ],
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: Text('A Casa'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.checklist_rtl_outlined),
                  selectedIcon: Icon(Icons.checklist_rtl_rounded),
                  label: Text('Tarefas & Compras'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.calendar_today_outlined),
                  selectedIcon: Icon(Icons.calendar_today_rounded),
                  label: Text('Agenda'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.handshake_outlined),
                  selectedIcon: Icon(Icons.handshake_rounded),
                  label: Text('Pessoal'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.analytics_outlined),
                  selectedIcon: Icon(Icons.analytics_rounded),
                  label: Text('Relatórios'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: Text('Ajustes'),
                ),
              ],
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Colors.grey.withValues(alpha: 0.15),
            ),
            Expanded(
              child: navigationShell,
            ),
          ],
        ),
      );
    }

    // Layout Mobile / Celular (NavigationBar inferior clássico)
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'A Casa',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rtl_outlined),
            selectedIcon: Icon(Icons.checklist_rtl_rounded),
            label: 'Tarefas & Compras',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake_rounded),
            label: 'Pessoal',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Relatórios',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ajustes',
          ),
        ],
      ),
      floatingActionButton: const SmartFAB(),
    );
  }
}
