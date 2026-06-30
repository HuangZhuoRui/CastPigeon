part of '../cast_pigeon_home.dart';

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 112),
      children: [
        _StatusCard(api: api, snapshot: snapshot),
        if (snapshot.transferStatus != null) ...[
          const SizedBox(height: 10),
          _TransferCard(status: snapshot.transferStatus!),
        ],
        if (snapshot.workMode == WorkMode.pairing ||
            snapshot.onlineDevices.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionHeader(
            title: '在线设备',
            trailing:
                snapshot.workMode == WorkMode.pairing &&
                    snapshot.onlineDevices.isEmpty
                ? '搜索中'
                : null,
          ),
          const SizedBox(height: 8),
          if (snapshot.onlineDevices.isEmpty)
            _LoadingDeviceCard()
          else
            for (final device in snapshot.onlineDevices) ...[
              _OnlineDeviceCard(api: api, snapshot: snapshot, device: device),
              const SizedBox(height: 8),
            ],
        ],
        const SizedBox(height: 10),
        _BoundDevicesCard(api: api, snapshot: snapshot),
        const SizedBox(height: 10),
        _AdvancedLabCard(api: api, snapshot: snapshot),
        if (snapshot.phase == ConnectionPhase.transferring) ...[
          const SizedBox(height: 10),
          _MessageTestCard(api: api, snapshot: snapshot),
        ],
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final active = snapshot.workMode != WorkMode.idle;
    final statusColor = switch (snapshot.phase) {
      ConnectionPhase.idle => Colors.grey,
      ConnectionPhase.transferring => const Color(0xff4caf50),
      _ => const Color(0xffffb300),
    };
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.connectionStateLabel,
                      style: _titleStyle(context),
                    ),
                    Text(snapshot.workModeLabel, style: _subtleStyle(context)),
                  ],
                ),
              ),
              Switch(
                value: active,
                onChanged: (checked) {
                  if (checked) {
                    final action = snapshot.boundDevices.isEmpty
                        ? api.startPairing()
                        : api.startWorking();
                    unawaited(action);
                  } else {
                    unawaited(api.stop());
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                selected: snapshot.role == DeviceRole.sender,
                label: const Text('发送端'),
                onSelected: snapshot.workMode == WorkMode.idle
                    ? (_) => unawaited(api.setRole(DeviceRole.sender))
                    : null,
              ),
              ChoiceChip(
                selected: snapshot.role == DeviceRole.receiver,
                label: const Text('接收端'),
                onSelected: snapshot.workMode == WorkMode.idle
                    ? (_) => unawaited(api.setRole(DeviceRole.receiver))
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnlineDeviceCard extends StatelessWidget {
  const _OnlineDeviceCard({
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
    final notificationEnabled =
        snapshot.boundDevices
            .where(
              (entry) => entry.hash.toUpperCase() == device.hash.toUpperCase(),
            )
            .map((entry) => entry.notificationSharingEnabled)
            .firstOrNull ??
        bound;
    return _SurfaceCard(
      onTap: snapshot.workMode == WorkMode.pairing
          ? () => unawaited(api.requestBinding(device))
          : null,
      child: Row(
        children: [
          Icon(_deviceIcon(device.deviceType), color: _accentColor(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.deviceName,
                  style: _titleStyle(context),
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.deviceType} / ${bound ? "已绑定" : "组内设备"} / ${device.lanReachable ? "局域网可达" : "等待验证"} / ${device.ipAddress} / 端口 ${device.filePort ?? "不可用"}',
                  style: _subtleStyle(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('通知', style: _captionStyle(context)),
                  Switch(
                    value: notificationEnabled,
                    onChanged: (checked) => unawaited(
                      api.setNotificationSharing(device.hash, checked),
                    ),
                  ),
                ],
              ),
              if (device.filePort != null && device.lanReachable)
                TextButton(
                  onPressed: () => unawaited(api.sendFile(device)),
                  child: const Text('发送文件'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoundDevicesCard extends StatelessWidget {
  const _BoundDevicesCard({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('已绑定设备', style: _titleStyle(context))),
              TextButton(
                onPressed: snapshot.workMode == WorkMode.pairing
                    ? null
                    : () => unawaited(api.startPairing()),
                child: Text(
                  snapshot.workMode == WorkMode.pairing ? '配对中' : '绑定新设备',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (snapshot.boundDevices.isEmpty)
            Text('还没有绑定设备，可以先搜索附近设备完成配对。', style: _subtleStyle(context))
          else
            for (final entry in snapshot.boundDevices)
              _BoundDeviceRow(api: api, entry: entry),
        ],
      ),
    );
  }
}

class _BoundDeviceRow extends StatelessWidget {
  const _BoundDeviceRow({required this.api, required this.entry});

  final CastPigeonApi api;
  final BoundDevice entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, style: _mediumStyle(context), maxLines: 1),
                  Text(
                    [
                      'Hash: ${entry.hash}',
                      entry.deviceType == 'Unknown' ? null : entry.deviceType,
                      entry.lastIp,
                    ].whereType<String>().join(' / '),
                    style: _subtleStyle(context),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            Text('通知', style: _captionStyle(context)),
            Switch(
              value: entry.notificationSharingEnabled,
              onChanged: (checked) =>
                  unawaited(api.setNotificationSharing(entry.hash, checked)),
            ),
            IconButton(
              tooltip: '删除绑定设备',
              onPressed: () => unawaited(api.removeBoundDevice(entry.hash)),
              icon: const Icon(Icons.delete_rounded, color: Color(0xffb3261e)),
            ),
          ],
        ),
        const Divider(height: 12),
      ],
    );
  }
}

class _AdvancedLabCard extends StatelessWidget {
  const _AdvancedLabCard({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final selectedPrivilegeMode = snapshot.privilege.mode == 'Shizuku'
        ? 'Shizuku'
        : 'Default';
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('高级实验室', style: _sectionStyle(context)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('真·后台剪贴板', style: _titleStyle(context)),
                        if (snapshot.privilege.isPrivileged) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xff4caf50),
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _privilegeStatus(snapshot.privilege),
                      style: _subtleStyle(context),
                    ),
                    Text(
                      '当前实际后端：${snapshot.privilege.activeBackend}',
                      style: _captionStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final optionWidth = constraints.maxWidth >= 420
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: optionWidth,
                    child: _PrivilegeModeOption(
                      selected: selectedPrivilegeMode == 'Default',
                      title: '默认模式',
                      subtitle: '使用系统常规权限，关闭后台提权。',
                      icon: Icons.security_rounded,
                      onTap: selectedPrivilegeMode == 'Default'
                          ? null
                          : () => unawaited(api.selectPrivilegeMode('Default')),
                    ),
                  ),
                  SizedBox(
                    width: optionWidth,
                    child: _PrivilegeModeOption(
                      selected: selectedPrivilegeMode == 'Shizuku',
                      title: 'Shizuku',
                      subtitle: '启用后台剪贴板读写与系统能力桥接。',
                      icon: Icons.bolt_rounded,
                      onTap: selectedPrivilegeMode == 'Shizuku'
                          ? null
                          : () => unawaited(api.selectPrivilegeMode('Shizuku')),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PrivilegeModeOption extends StatelessWidget {
  const _PrivilegeModeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? colors.primary : _outlineColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: _mediumStyle(context)),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: colors.primary,
                            size: 18,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle, style: _subtleStyle(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageTestCard extends StatelessWidget {
  const _MessageTestCard({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot.role == DeviceRole.sender)
            FilledButton(
              onPressed: () => unawaited(api.sendTestNotification()),
              child: const Text('发送测试通知'),
            )
          else ...[
            Text('最新收到消息：', style: _titleStyle(context)),
            const SizedBox(height: 8),
            Text(snapshot.latestReceivedMessage ?? '暂无'),
          ],
        ],
      ),
    );
  }
}
