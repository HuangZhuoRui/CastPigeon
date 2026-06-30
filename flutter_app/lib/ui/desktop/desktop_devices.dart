part of '../cast_pigeon_home.dart';

class _MacDevicesPage extends StatelessWidget {
  const _MacDevicesPage({
    required this.api,
    required this.snapshot,
    required this.onStartPairing,
  });

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;
  final VoidCallback onStartPairing;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '设备管理',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: onStartPairing,
              icon: const Icon(Icons.add_rounded),
              label: const Text('配对新设备'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已授权绑定的设备', style: _sectionStyle(context)),
              const SizedBox(height: 12),
              if (snapshot.boundDevices.isEmpty)
                Text('当前未绑定任何设备，请先配对。', style: _subtleStyle(context))
              else
                for (final entry in snapshot.boundDevices)
                  _MacBoundDeviceRow(
                    api: api,
                    entry: entry,
                    snapshot: snapshot,
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (snapshot.transferStatus != null) ...[
          _TransferCard(status: snapshot.transferStatus!),
          const SizedBox(height: 14),
        ],
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('局域网在线设备', style: _sectionStyle(context)),
              const SizedBox(height: 12),
              if (snapshot.onlineDevices.isEmpty)
                Text('暂无局域网设备。启动工作或配对模式后会自动发现。', style: _subtleStyle(context))
              else
                for (final device in snapshot.onlineDevices)
                  _MacOnlineDeviceRow(
                    api: api,
                    snapshot: snapshot,
                    device: device,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacBoundDeviceRow extends StatelessWidget {
  const _MacBoundDeviceRow({
    required this.api,
    required this.entry,
    required this.snapshot,
  });

  final CastPigeonApi api;
  final BoundDevice entry;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final online = snapshot.connectedDeviceHashes
        .map((hash) => hash.toUpperCase())
        .contains(entry.hash.toUpperCase());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(_deviceIcon(entry.deviceType), color: _accentColor(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(entry.name, style: _mediumStyle(context)),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: online ? const Color(0xff4caf50) : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(online ? '在线' : '离线', style: _captionStyle(context)),
                  ],
                ),
                Text('Hash: ${entry.hash}', style: _subtleStyle(context)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_showRenameBoundDeviceDialog(context)),
            child: const Text('重命名'),
          ),
          Text('通知', style: _captionStyle(context)),
          Switch(
            value: entry.notificationSharingEnabled,
            onChanged: (checked) =>
                unawaited(api.setNotificationSharing(entry.hash, checked)),
          ),
          IconButton(
            tooltip: '解绑',
            onPressed: () => unawaited(api.removeBoundDevice(entry.hash)),
            icon: const Icon(Icons.link_off_rounded, color: Color(0xffb3261e)),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameBoundDeviceDialog(BuildContext context) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名设备'),
          content: SizedBox(
            width: 260,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '设备名称',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      await api.renameBoundDevice(entry.hash, trimmed);
    }
  }
}

class _MacOnlineDeviceRow extends StatelessWidget {
  const _MacOnlineDeviceRow({
    required this.api,
    required this.snapshot,
    required this.device,
  });

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;
  final CastDevice device;

  @override
  Widget build(BuildContext context) {
    final bound = snapshot.boundDevices.any(
      (entry) => entry.hash.toUpperCase() == device.hash.toUpperCase(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(_deviceIcon(device.deviceType), color: _accentColor(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.deviceName, style: _mediumStyle(context)),
                Text(
                  '${device.deviceType} / ${device.ipAddress} / 文件端口 ${device.filePort ?? "不可用"}',
                  style: _subtleStyle(context),
                ),
              ],
            ),
          ),
          if (snapshot.workMode == WorkMode.pairing && !bound)
            TextButton(
              onPressed: () => unawaited(api.requestBinding(device)),
              child: const Text('绑定'),
            ),
          TextButton.icon(
            onPressed: device.filePort == null || device.ipAddress.isEmpty
                ? null
                : () => unawaited(api.sendFile(device)),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('发送文件'),
          ),
        ],
      ),
    );
  }
}
