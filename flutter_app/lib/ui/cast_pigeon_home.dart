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
  double _mobilePagePosition = AppTab.dashboard.index.toDouble();
  bool _mobilePageDragging = false;
  StreamSubscription<CastPigeonSnapshot>? _subscription;

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _tab = tab;
      _mobilePageDragging = false;
      _mobilePagePosition = tab.index.toDouble();
    });
  }

  Widget _buildMobileTabSwitcher() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth;
        final lastPage = (AppTab.values.length - 1).toDouble();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            _mobilePageDragging = true;
          },
          onHorizontalDragUpdate: (details) {
            if (pageWidth <= 0) {
              return;
            }
            setState(() {
              _mobilePageDragging = true;
              _mobilePagePosition =
                  (_mobilePagePosition - details.delta.dx / pageWidth)
                      .clamp(0.0, lastPage)
                      .toDouble();
            });
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            var target = _mobilePagePosition.round();
            if (velocity.abs() > 520) {
              target = velocity < 0
                  ? _mobilePagePosition.floor() + 1
                  : _mobilePagePosition.ceil() - 1;
            }
            target = target.clamp(0, AppTab.values.length - 1);
            setState(() {
              _mobilePageDragging = false;
              _mobilePagePosition = target.toDouble();
              _tab = AppTab.values[target];
            });
          },
          onHorizontalDragCancel: () {
            setState(() {
              _mobilePageDragging = false;
              _mobilePagePosition = _tab.index.toDouble();
            });
          },
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _mobilePagePosition),
              duration: _mobilePageDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              builder: (context, position, child) {
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    _TranslatedMobilePage(
                      offsetX: 0 - position,
                      child: _DashboardPage(
                        api: widget.api,
                        snapshot: _snapshot,
                      ),
                    ),
                    _TranslatedMobilePage(
                      offsetX: 1 - position,
                      child: _HistoryPage(api: widget.api, snapshot: _snapshot),
                    ),
                    _TranslatedMobilePage(
                      offsetX: 2 - position,
                      child: _SettingsPage(
                        api: widget.api,
                        snapshot: _snapshot,
                      ),
                    ),
                    _TranslatedMobilePage(
                      offsetX: 3 - position,
                      child: _InfoPage(
                        api: widget.api,
                        snapshot: _snapshot,
                        themeController: widget.themeController,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _TranslatedMobilePage extends StatelessWidget {
  const _TranslatedMobilePage({required this.offsetX, required this.child});

  final double offsetX;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FractionalTranslation(
        translation: Offset(offsetX, 0),
        child: child,
      ),
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
    const radius = 24.0;
    final colors = Theme.of(context).colorScheme;
    final selectedColor = colors.primaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        widthFactor: 1,
        heightFactor: 1,
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
            padding: const EdgeInsets.all(5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tab in AppTab.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: 58,
                      height: 52,
                      decoration: BoxDecoration(
                        color: selected == tab
                            ? selectedColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(radius - 5),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(radius - 5),
                        child: InkWell(
                          onTap: () => onSelect(tab),
                          borderRadius: BorderRadius.circular(radius - 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                tab.icon,
                                size: 21,
                                color: selected == tab
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tab.mobileTitle,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: selected == tab
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                      fontWeight: selected == tab
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      height: 1,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
