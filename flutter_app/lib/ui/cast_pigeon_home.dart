import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/bridge/cast_pigeon_api.dart';
import '../core/theme/theme_controller.dart';

part 'common/ui_common.dart';
part 'desktop/desktop_dashboard.dart';
part 'desktop/desktop_devices.dart';
part 'desktop/desktop_history.dart';
part 'desktop/desktop_pairing.dart';
part 'desktop/desktop_shell.dart';
part 'desktop/desktop_updates.dart';
part 'dialogs/pairing_dialogs.dart';
part 'mobile/history_page.dart';
part 'mobile/mobile_pages.dart';
part 'mobile/settings_page.dart';
part 'pages/info_page.dart';
part 'widgets/history_cards.dart';
part 'widgets/release_card.dart';
part 'widgets/theme_preference_selector.dart';
part 'widgets/transfer_card.dart';

enum AppTab {
  dashboard('主页', '工作台', Icons.speed_rounded),
  history('发送历史', '历史记录', Icons.history_rounded),
  settings('控制台', '设备管理', Icons.devices_rounded),
  info('信息', '关于投鸽', Icons.info_rounded);

  const AppTab(this.mobileTitle, this.desktopTitle, this.icon);

  final String mobileTitle;
  final String desktopTitle;
  final IconData icon;
}

class CastPigeonHome extends StatefulWidget {
  const CastPigeonHome({
    super.key,
    required this.api,
    required this.themeController,
  });

  final CastPigeonApi api;
  final ThemeController themeController;

  @override
  State<CastPigeonHome> createState() => _CastPigeonHomeState();
}

class _CastPigeonHomeState extends State<CastPigeonHome> {
  CastPigeonSnapshot _snapshot = CastPigeonSnapshot.empty;
  AppTab _tab = AppTab.dashboard;
  bool _showMacPairingSheet = false;
  StreamSubscription<CastPigeonSnapshot>? _subscription;
  late final PageController _mobilePageController;

  @override
  void initState() {
    super.initState();
    _mobilePageController = PageController(initialPage: _tab.index);
    _subscription = widget.api.snapshotStream.listen((snapshot) {
      if (mounted) {
        final previousBoundHashes = _snapshot.boundDevices
            .map((device) => device.hash.toUpperCase())
            .toSet();
        final nextBoundHashes = snapshot.boundDevices
            .map((device) => device.hash.toUpperCase())
            .toSet();
        final pairingCompleted =
            _showMacPairingSheet &&
            nextBoundHashes.difference(previousBoundHashes).isNotEmpty;
        setState(() {
          _snapshot = snapshot;
          if (pairingCompleted) {
            _showMacPairingSheet = false;
          }
        });
      }
    });
    unawaited(widget.api.refresh());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _mobilePageController.dispose();
    widget.api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktopPlatform;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: isDesktop
            ? _DesktopShell(
                api: widget.api,
                snapshot: _snapshot,
                themeController: widget.themeController,
                selected: _tab,
                onSelect: _selectTab,
                showPairingSheet:
                    _showMacPairingSheet ||
                    _snapshot.pinDisplay != null ||
                    _snapshot.pinInputDevice != null,
                onStartPairing: () {
                  setState(() => _showMacPairingSheet = true);
                  unawaited(widget.api.startPairing());
                },
                onClosePairing: () {
                  setState(() => _showMacPairingSheet = false);
                  unawaited(widget.api.stop());
                },
              )
            : Stack(
                children: [
                  Positioned.fill(child: _buildMobileTabSwitcher()),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _BottomNavigationBar(
                      selected: _tab,
                      onSelect: _selectTab,
                    ),
                  ),
                  _SnapshotDialogs(api: widget.api, snapshot: _snapshot),
                ],
              ),
      ),
    );
  }

  void _selectTab(AppTab tab) {
    if (tab == _tab) {
      return;
    }
    setState(() => _tab = tab);
    if (!_isDesktopPlatform && _mobilePageController.hasClients) {
      unawaited(
        _mobilePageController.animateToPage(
          tab.index,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Widget _buildMobileTabSwitcher() {
    return PageView(
      controller: _mobilePageController,
      physics: const PageScrollPhysics(),
      onPageChanged: (index) {
        final nextTab = AppTab.values[index];
        if (nextTab != _tab) {
          setState(() => _tab = nextTab);
        }
      },
      children: [
        _DashboardPage(api: widget.api, snapshot: _snapshot),
        _HistoryPage(api: widget.api, snapshot: _snapshot),
        _SettingsPage(api: widget.api, snapshot: _snapshot),
        _InfoPage(
          api: widget.api,
          snapshot: _snapshot,
          themeController: widget.themeController,
        ),
      ],
    );
  }
}

bool get _isDesktopPlatform =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({required this.selected, required this.onSelect});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    const radius = 22.0;
    final colors = Theme.of(context).colorScheme;
    final selectedColor = colors.primaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.92),
          border: Border.all(color: _outlineColor(context)),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: _shadowColor(context),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final tab in AppTab.values)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 42,
                    decoration: BoxDecoration(
                      color: selected == tab
                          ? selectedColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(radius - 7),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      isSelected: selected == tab,
                      onPressed: () => onSelect(tab),
                      icon: Icon(tab.icon, size: 21),
                      color: colors.onSurfaceVariant,
                      selectedIcon: Icon(
                        tab.icon,
                        size: 21,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
