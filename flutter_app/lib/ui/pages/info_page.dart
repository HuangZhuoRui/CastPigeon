part of '../cast_pigeon_home.dart';

class _InfoPage extends StatelessWidget {
  const _InfoPage({
    required this.api,
    required this.snapshot,
    required this.themeController,
  });

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 112),
      children: [
        Center(
          child: Column(
            children: [
              const _BrandLogo(size: 104, borderRadius: 22),
              const SizedBox(height: 16),
              Text(
                '投鸽',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  '超越屏幕边界，让数据像信鸽一样自由翱翔',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '当前版本 ${snapshot.update.currentVersion}',
                style: _subtleStyle(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _InfoActionCard(
          icon: Icons.download_rounded,
          title: '版本更新',
          subtitle: snapshot.update.latestRelease == null
              ? '检查安装包、更新日志和历史版本'
              : '发现新版本 ${snapshot.update.latestRelease!.versionName}',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  _AndroidUpdatePage(api: api, initialSnapshot: snapshot),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _InfoActionCard(
          icon: Icons.palette_rounded,
          title: '外观设置',
          subtitle: '选择浅色、深色或跟随系统',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  _AppearanceSettingsPage(themeController: themeController),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoActionCard extends StatelessWidget {
  const _InfoActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(context)),
                const SizedBox(height: 2),
                Text(subtitle, style: _subtleStyle(context)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _AndroidUpdatePage extends StatefulWidget {
  const _AndroidUpdatePage({required this.api, required this.initialSnapshot});

  final CastPigeonApi api;

  final CastPigeonSnapshot initialSnapshot;

  @override
  State<_AndroidUpdatePage> createState() => _AndroidUpdatePageState();
}

class _AndroidUpdatePageState extends State<_AndroidUpdatePage> {
  late CastPigeonSnapshot _snapshot = widget.initialSnapshot;
  StreamSubscription<CastPigeonSnapshot>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.api.snapshotStream.listen((snapshot) {
      if (mounted) {
        setState(() => _snapshot = snapshot);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('版本更新')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('当前版本', style: _titleStyle(context)),
                          Text(
                            snapshot.update.currentVersion,
                            style: _subtleStyle(context),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => unawaited(widget.api.checkUpdate()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('检查更新'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (snapshot.update.latestRelease == null)
                  Text(
                    snapshot.update.message.isBlank
                        ? '当前没有可用更新。'
                        : snapshot.update.message,
                    style: _subtleStyle(context),
                  )
                else
                  _ReleaseCard(
                    api: widget.api,
                    title:
                        '发现新版本 ${snapshot.update.latestRelease!.versionName}',
                    release: snapshot.update.latestRelease!,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('历史更新', style: _titleStyle(context))),
              TextButton(
                onPressed: () => unawaited(widget.api.refreshUpdateHistory()),
                child: const Text('刷新'),
              ),
            ],
          ),
          for (final release in snapshot.update.historyReleases) ...[
            _ReleaseCard(
              api: widget.api,
              title: '投鸽 Android ${release.versionName}',
              release: release,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _AppearanceSettingsPage extends StatelessWidget {
  const _AppearanceSettingsPage({required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Text('显示模式', style: _sectionStyle(context)),
          const SizedBox(height: 10),
          for (final preference in AppThemePreference.values) ...[
            _ThemePreferenceListTile(
              themeController: themeController,
              preference: preference,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ThemePreferenceListTile extends StatelessWidget {
  const _ThemePreferenceListTile({
    required this.themeController,
    required this.preference,
  });

  final ThemeController themeController;
  final AppThemePreference preference;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final selected = themeController.themePreference == preference;
        return _SurfaceCard(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          onTap: () =>
              unawaited(themeController.setThemePreference(preference)),
          child: Row(
            children: [
              _ThemePreferenceGlyph(
                preference: preference,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(preference.label, style: _mediumStyle(context)),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        );
      },
    );
  }
}
