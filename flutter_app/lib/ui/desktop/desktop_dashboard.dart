part of '../cast_pigeon_home.dart';

class _DesktopDashboardPage extends StatelessWidget {
  const _DesktopDashboardPage({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 24),
      children: [
        Text(
          '投鸽工作台',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (snapshot.bluetoothPermissionDenied) ...[
          const SizedBox(height: 24),
          _MacBluetoothPermissionCard(api: api),
        ],
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: _MacModeCard(
                title: '作为接收端 (Mac)',
                subtitle: '接收来自手机的推送通知和剪贴板。',
                icon: Icons.desktop_mac_rounded,
                selected: snapshot.role == DeviceRole.receiver,
                enabled: snapshot.workMode == WorkMode.idle,
                onTap: () => unawaited(api.setRole(DeviceRole.receiver)),
              ),
            ),
            const SizedBox(width: 40),
            Flexible(
              child: _MacModeCard(
                title: '作为发送端 (测试用)',
                subtitle: '向其他设备广播并发送数据。',
                icon: Icons.wifi_tethering_rounded,
                selected: snapshot.role == DeviceRole.sender,
                enabled: snapshot.workMode == WorkMode.idle,
                onTap: () => unawaited(api.setRole(DeviceRole.sender)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        _SurfaceCard(
          child: Column(
            children: [
              Text(snapshot.connectionStateLabel, style: _titleStyle(context)),
              const SizedBox(height: 8),
              Text(
                snapshot.connectionStateDescription,
                style: _subtleStyle(context),
                textAlign: TextAlign.center,
              ),
              if (snapshot.isAnimating) ...[
                const SizedBox(height: 18),
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
              ],
              const SizedBox(height: 18),
              if (snapshot.workMode == WorkMode.idle)
                FilledButton(
                  onPressed: snapshot.bluetoothPermissionDenied
                      ? () => unawaited(api.openBluetoothPrivacySettings())
                      : () => unawaited(api.startWorking()),
                  child: const SizedBox(
                    width: 180,
                    height: 40,
                    child: Center(child: Text('启动工作')),
                  ),
                )
              else
                FilledButton.tonal(
                  onPressed: () => unawaited(api.stop()),
                  child: const SizedBox(
                    width: 180,
                    height: 40,
                    child: Center(child: Text('停止并断开')),
                  ),
                ),
            ],
          ),
        ),
        if (snapshot.transferStatus != null) ...[
          const SizedBox(height: 14),
          _TransferCard(status: snapshot.transferStatus!),
        ],
        const SizedBox(height: 30),
        _MacDebugPanel(api: api, snapshot: snapshot),
      ],
    );
  }
}

class _MacBluetoothPermissionCard extends StatelessWidget {
  const _MacBluetoothPermissionCard({required this.api});

  final CastPigeonApi api;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      color: const Color(0xfffff2df),
      borderColor: const Color(0x3dd47d00),
      child: Row(
        children: [
          const Icon(
            Icons.bluetooth_disabled_rounded,
            color: Color(0xffb65f00),
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('需要蓝牙权限', style: _titleStyle(context)),
                const SizedBox(height: 4),
                Text(
                  '请在系统设置中允许投鸽使用蓝牙，然后回到应用重新启动工作。',
                  style: _subtleStyle(context),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () => unawaited(api.openBluetoothPrivacySettings()),
            child: const Text('打开蓝牙权限设置'),
          ),
        ],
      ),
    );
  }
}

class _MacModeCard extends StatelessWidget {
  const _MacModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _SurfaceCard(
      color: selected ? colors.primary : null,
      borderColor: selected ? colors.primary : null,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 200,
        height: 160,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: selected ? colors.onPrimary : colors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: _titleStyle(
                context,
              ).copyWith(color: selected ? colors.onPrimary : null),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: _subtleStyle(context).copyWith(
                color: selected
                    ? colors.onPrimary.withValues(alpha: 0.74)
                    : null,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacDebugPanel extends StatelessWidget {
  const _MacDebugPanel({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final logText = snapshot.debugLogs.isEmpty
        ? '暂无日志'
        : snapshot.debugLogs.join('\n');
    final colors = Theme.of(context).colorScheme;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('BLE 实时诊断日志：', style: _titleStyle(context)),
              Text('可选中复制', style: _captionStyle(context)),
              TextButton(
                onPressed: () =>
                    unawaited(api.insertDebugLog('这是一条手动插入的测试日志！')),
                child: const Text('插入测试日志'),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: logText));
                },
                child: const Text('复制全部'),
              ),
              TextButton(
                onPressed: () => unawaited(api.clearDebugLogs()),
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 170,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _outlineColor(context)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                logText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: snapshot.debugLogs.isEmpty
                      ? colors.onSurfaceVariant
                      : colors.onSurface,
                  fontFamily: 'Menlo',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
