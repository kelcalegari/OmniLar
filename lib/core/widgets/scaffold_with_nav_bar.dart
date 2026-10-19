import 'offline_sync_banner.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/responsive.dart';
import 'omni_logo.dart';
import 'smart_fab.dart';
import 'theme_toggle_button.dart';

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
            SizedBox(
              width: 152,
              child: NavigationRail(
                minWidth: 152,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _onTap,
                labelType: NavigationRailLabelType.all,
                leading: Column(
                  children: [
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OmniLogo.icon(width: 28, height: 28),
                            SizedBox(width: 8),
                            Text(
                              'Omni Lar',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: -0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SmartFAB(
                      isExtended: true,
                      currentTab: navigationShell.currentIndex,
                    ),
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
                  icon: Icon(Icons.shopping_cart_outlined),
                  selectedIcon: Icon(Icons.shopping_cart_rounded),
                  label: Text('Compras'),
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
              trailing: const Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Omni Cloud • Conectado',
                          child: Icon(Icons.circle, size: 8, color: Colors.green),
                        ),
                        SizedBox(width: 8),
                        ThemeToggleButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          VerticalDivider(
              width: 1,
              thickness: 1,
              color: Colors.grey.withValues(alpha: 0.15),
            ),
            Expanded(
              child: OfflineSyncHost(child: navigationShell),
            ),
          ],
        ),
      );
    }

    // Layout Mobile / Celular (NavigationBar inferior clássico)
    return Scaffold(
      body: OfflineSyncHost(child: navigationShell),
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
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart_rounded),
            label: 'Compras',
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
      floatingActionButton: SmartFAB(
        currentTab: navigationShell.currentIndex,
      ),
    );
  }
}
