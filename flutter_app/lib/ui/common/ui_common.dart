part of '../cast_pigeon_home.dart';

const _appLogoAsset =
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png';

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.size, this.borderRadius});

  final double size;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius ?? size * 0.22),
      child: Image.asset(
        _appLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        border: Border.all(color: _outlineColor(context)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _shadowColor(context),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.onTap,
    this.margin,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? _surfaceCardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? _outlineColor(context)),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: card,
    );
  }
}

class _LoadingDeviceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('正在发现附近设备...', style: _subtleStyle(context)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: _titleStyle(context))),
        if (trailing != null) Text(trailing!, style: _sectionStyle(context)),
      ],
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Center(child: Text(text, style: _subtleStyle(context))),
    );
  }
}

class _AppIcon extends StatefulWidget {
  const _AppIcon({
    required this.api,
    required this.packageName,
    required this.appName,
    this.useHistoryCache = false,
  });

  final CastPigeonApi? api;
  final String? packageName;
  final String appName;
  final bool useHistoryCache;

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  String? _base64Icon;
  Object? _loadKey;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(covariant _AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _currentKey;
    if (key != _loadKey) {
      _base64Icon = null;
      _loadIcon();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _base64Icon == null
        ? null
        : Image.memory(
            base64Decode(_base64Icon!),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallback(),
          );
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: image ?? _fallback(),
    );
  }

  Object get _currentKey =>
      Object.hash(widget.packageName, widget.appName, widget.useHistoryCache);

  Widget _fallback() {
    return Text(
      widget.appName.isEmpty ? '?' : widget.appName.characters.first,
      style: const TextStyle(fontWeight: FontWeight.w800),
    );
  }

  Future<void> _loadIcon() async {
    final api = widget.api;
    if (api == null) return;
    final key = _currentKey;
    _loadKey = key;
    final icon = widget.useHistoryCache
        ? await api.historyIconBase64(widget.appName)
        : await api.appIconBase64(widget.packageName ?? '');
    if (!mounted || key != _loadKey) return;
    if (icon != null && icon.isNotEmpty) {
      setState(() => _base64Icon = icon);
    }
  }
}

TextStyle _titleStyle(BuildContext context) {
  return Theme.of(
    context,
  ).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800);
}

TextStyle _mediumStyle(BuildContext context) {
  return Theme.of(
    context,
  ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700);
}

TextStyle _sectionStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium!.copyWith(
    color: _accentColor(context),
    fontWeight: FontWeight.w800,
  );
}

TextStyle _subtleStyle(BuildContext context) {
  return Theme.of(
    context,
  ).textTheme.bodySmall!.copyWith(color: _subtleColor(context));
}

TextStyle _captionStyle(BuildContext context) {
  return Theme.of(
    context,
  ).textTheme.labelSmall!.copyWith(color: _subtleColor(context));
}

Color _accentColor(BuildContext context) {
  return Theme.of(context).colorScheme.primary;
}

Color _subtleColor(BuildContext context) {
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

Color _surfaceCardColor(BuildContext context) {
  return Theme.of(context).colorScheme.surfaceContainerHigh;
}

Color _outlineColor(BuildContext context) {
  return Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7);
}

Color _shadowColor(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Colors.black.withValues(alpha: dark ? 0.32 : 0.10);
}

extension _BlankString on String {
  bool get isBlank => trim().isEmpty;
}

IconData _deviceIcon(String type) {
  return switch (type.toLowerCase()) {
    'android' => Icons.phone_android_rounded,
    'macos' => Icons.laptop_mac_rounded,
    'windows' => Icons.desktop_windows_rounded,
    _ => Icons.devices_other_rounded,
  };
}

String _progressLabel(TransferStatus status) {
  final fraction = status.progressFraction;
  if (fraction == null) return '传输中';
  return '${(math.min(1, math.max(0, fraction)) * 100).toInt()}%';
}

String _formatTimestamp(int timestamp) {
  if (timestamp <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}

String _privilegeStatus(PrivilegeState state) {
  if (state.mode == 'Shizuku') {
    return switch (state.bindStatus) {
      'Binding' => '正在连接 Shizuku...',
      'Connected' => 'Shizuku 提权已生效',
      'Failed' => 'Shizuku 授权失败',
      _ => '已选择 Shizuku 模式',
    };
  }
  return '未开启后台提权同步';
}
