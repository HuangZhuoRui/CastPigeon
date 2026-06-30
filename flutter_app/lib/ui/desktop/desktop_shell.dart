part of '../cast_pigeon_home.dart';

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.api,
    required this.snapshot,
    required this.themeController,
    required this.selected,
    required this.onSelect,
    required this.showPairingSheet,
    required this.onStartPairing,
    required this.onClosePairing,
  });

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;
  final ThemeController themeController;
  final AppTab selected;
  final ValueChanged<AppTab> onSelect;
  final bool showPairingSheet;
  final VoidCallback onStartPairing;
  final VoidCallback onClosePairing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Row(
          children: [
            _DesktopSidebar(
              snapshot: snapshot,
              themeController: themeController,
              selected: selected,
              onSelect: onSelect,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: switch (selected) {
                AppTab.dashboard => _DesktopDashboardPage(
                  api: api,
                  snapshot: snapshot,
                ),
                AppTab.history => _MacHistoryPage(api: api, snapshot: snapshot),
                AppTab.settings => _MacDevicesPage(
                  api: api,
                  snapshot: snapshot,
                  onStartPairing: onStartPairing,
                ),
                AppTab.info => _MacUpdatesPage(api: api, snapshot: snapshot),
              },
            ),
          ],
        ),
        if (showPairingSheet)
          _MacPairingSheetOverlay(
            api: api,
            snapshot: snapshot,
            onClose: onClosePairing,
          ),
      ],
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.snapshot,
    required this.themeController,
    required this.selected,
    required this.onSelect,
  });

  final CastPigeonSnapshot snapshot;
  final ThemeController themeController;
  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final active = snapshot.workMode != WorkMode.idle;
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 248,
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _BrandLogo(size: 36, borderRadius: 8),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('投鸽', style: _titleStyle(context)),
                    Text(
                      snapshot.localDeviceName,
                      style: _captionStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final tab in AppTab.values) ...[
            _DesktopNavButton(
              tab: tab,
              selected: selected == tab,
              onTap: () => onSelect(tab),
            ),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surfaceCardColor(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _outlineColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xff4caf50)
                            : const Color(0xff9aa5a0),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        snapshot.workModeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mediumStyle(context),
                      ),
                    ),
                    _ThemePreferenceSelector(themeController: themeController),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  snapshot.connectionStateLabel,
                  style: _captionStyle(context),
                ),
                const SizedBox(height: 6),
                Text(
                  snapshot.localDeviceHash,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _captionStyle(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavButton extends StatelessWidget {
  const _DesktopNavButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                tab.icon,
                size: 20,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tab.desktopTitle,
                  style: _mediumStyle(context).copyWith(
                    color: selected ? colors.primary : colors.onSurface,
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
