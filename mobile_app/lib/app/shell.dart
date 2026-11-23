import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/notifications/notifications.dart';
import '../ui/brand.dart';
import 'theme.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _tabs = [
  _Tab('Inicio', Icons.home_outlined, Icons.home_rounded),
  _Tab('Buscar', Icons.search, Icons.search),
  _Tab('Guardados', Icons.favorite_border, Icons.favorite),
  _Tab('Alertas', Icons.notifications_none, Icons.notifications),
  _Tab('Perfil', Icons.person_outline, Icons.person),
];

/// Contenedor de las pestañas principales con la barra de navegación flotante.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Los logos de tienda aparecen en casi todas las pantallas: se cargan una vez al inicio
    // para que no aparezcan vacíos al desplazarse.
    if (_precached) return;
    _precached = true;
    for (final e in storeBrands.entries) {
      if (e.value.hasLogo) precacheImage(AssetImage('assets/stores/${e.key}.png'), context);
    }
  }

  StatefulNavigationShell get shell => widget.shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBody: true,
        body: shell,
        bottomNavigationBar: _FloatingNav(
          index: shell.currentIndex,
          // Tocar la pestaña activa vuelve a su pantalla inicial.
          onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        ),
      );
}

class _FloatingNav extends ConsumerWidget {
  const _FloatingNav({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Color(0x660B1F4D), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -12)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              _NavItem(tab: _tabs[i], selected: i == index, dot: i == 3 && unread > 0, onTap: () => onTap(i)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.selected, required this.dot, required this.onTap});

  final _Tab tab;
  final bool selected;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ink : const Color(0xFFAAB6D6);
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 50,
          padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 12),
          decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? tab.activeIcon : tab.icon, color: color, size: 23),
                  if (dot)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.magenta,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? Colors.white : AppColors.ink, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(tab.label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Espacio al final de las listas para que la barra flotante no tape el contenido.
const navBarClearance = 104.0;
