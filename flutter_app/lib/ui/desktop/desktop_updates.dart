part of '../cast_pigeon_home.dart';

class _MacUpdatesPage extends StatelessWidget {
  const _MacUpdatesPage({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '自动更新',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => unawaited(api.checkUpdate()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('检查更新'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前版本 ${snapshot.update.currentVersion}',
                style: _titleStyle(context),
              ),
              const SizedBox(height: 8),
              if (snapshot.update.latestRelease == null)
                Text(
                  snapshot.update.message.isBlank
                      ? '当前没有可用更新。'
                      : snapshot.update.message,
                  style: _subtleStyle(context),
                )
              else
                _ReleaseCard(
                  api: api,
                  title: '发现新版本 ${snapshot.update.latestRelease!.versionName}',
                  release: snapshot.update.latestRelease!,
                  downloadLabel: '下载 macOS 安装包',
                  redownloadLabel: '重新下载 macOS 安装包',
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Text('历史更新', style: _titleStyle(context))),
            TextButton(
              onPressed: () => unawaited(api.refreshUpdateHistory()),
              child: const Text('刷新'),
            ),
          ],
        ),
        for (final release in snapshot.update.historyReleases) ...[
          _ReleaseCard(
            api: api,
            title: '投鸽 macOS ${release.versionName}',
            release: release,
            downloadLabel: '下载 macOS 安装包',
            redownloadLabel: '重新下载 macOS 安装包',
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
