part of '../cast_pigeon_home.dart';

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.api,
    required this.title,
    required this.release,
    this.downloadLabel = '下载 APK',
    this.redownloadLabel = '重新下载 APK',
  });

  final CastPigeonApi api;
  final String title;
  final ReleaseInfo release;
  final String downloadLabel;
  final String redownloadLabel;

  @override
  Widget build(BuildContext context) {
    final download = release.download;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _mediumStyle(context).copyWith(color: _accentColor(context)),
          ),
          const SizedBox(height: 6),
          Text(release.assetName, style: _subtleStyle(context)),
          const SizedBox(height: 8),
          _ReleaseMarkdownBody(body: release.body),
          if (download != null &&
              (download.progress >= 0 && download.progress < 100 ||
                  download.isVerifying)) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: download.progress < 0
                  ? null
                  : download.progress.clamp(0, 100) / 100,
            ),
            const SizedBox(height: 4),
            Text(
              download.isVerifying
                  ? '正在校验安装包...'
                  : '${download.progress.clamp(0, 100)}%',
              style: _subtleStyle(context),
            ),
          ],
          if (download?.message != null) ...[
            const SizedBox(height: 8),
            Text(
              download!.message!,
              style: _subtleStyle(context).copyWith(
                color: download.isVerified
                    ? _accentColor(context)
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed:
                    download != null &&
                        (download.progress >= 0 && download.progress < 100 ||
                            download.isVerifying)
                    ? null
                    : () => unawaited(api.downloadRelease(release.tagName)),
                child: Text(
                  download?.progress == 100 ? redownloadLabel : downloadLabel,
                ),
              ),
              if (download?.isVerified == true)
                OutlinedButton(
                  onPressed: () =>
                      unawaited(api.installRelease(release.tagName)),
                  child: const Text('安装'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReleaseMarkdownBody extends StatelessWidget {
  const _ReleaseMarkdownBody({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseText = theme.textTheme.bodyMedium!.copyWith(
      color: colors.onSurface,
      height: 1.42,
    );
    final headingText = theme.textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w800,
      color: colors.onSurface,
    );
    return MarkdownBody(
      data: body.isBlank ? '暂无更新日志' : body,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: baseText,
        pPadding: const EdgeInsets.only(bottom: 4),
        h1: headingText,
        h1Padding: const EdgeInsets.only(top: 6, bottom: 4),
        h2: headingText,
        h2Padding: const EdgeInsets.only(top: 6, bottom: 4),
        h3: headingText,
        h3Padding: const EdgeInsets.only(top: 6, bottom: 4),
        strong: baseText.copyWith(fontWeight: FontWeight.w800),
        em: baseText.copyWith(fontStyle: FontStyle.italic),
        listBullet: baseText,
        listIndent: 22,
        blockSpacing: 6,
        code: theme.textTheme.bodySmall!.copyWith(
          fontFamily: 'Menlo',
          color: colors.onSurface,
          backgroundColor: colors.surface.withValues(alpha: 0.72),
        ),
        codeblockPadding: const EdgeInsets.all(10),
        codeblockDecoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _outlineColor(context)),
        ),
        blockquote: baseText.copyWith(color: colors.onSurfaceVariant),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        blockquoteDecoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: colors.primary, width: 3)),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: _outlineColor(context))),
        ),
      ),
    );
  }
}
