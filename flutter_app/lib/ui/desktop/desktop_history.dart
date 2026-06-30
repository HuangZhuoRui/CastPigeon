part of '../cast_pigeon_home.dart';

class _MacHistoryPage extends StatefulWidget {
  const _MacHistoryPage({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  State<_MacHistoryPage> createState() => _MacHistoryPageState();
}

class _MacHistoryPageState extends State<_MacHistoryPage> {
  String _selectedDeviceHash = 'All';
  bool _messages = true;

  @override
  Widget build(BuildContext context) {
    final messages = _filteredMessages;
    final clipboardItems = widget.snapshot.clipboardItems;
    final contentKey =
        '${_messages ? 'messages' : 'clipboard'}:${_selectedDeviceHash.toUpperCase()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '历史记录',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.notifications_rounded),
                    label: Text('消息'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.content_paste_rounded),
                    label: Text('粘贴板'),
                  ),
                ],
                selected: {_messages},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _messages = selection.first),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '刷新',
                onPressed: () => unawaited(widget.api.refresh()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _messages
                ? Padding(
                    key: const ValueKey('mac-device-filter'),
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 18),
                    child: _MacDeviceFilterBar(
                      devices: _deviceFilters,
                      selectedHash: _effectiveSelectedDeviceHash,
                      onSelected: (hash) =>
                          setState(() => _selectedDeviceHash = hash),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('mac-device-filter-off')),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0.018, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(contentKey),
              child: _messages
                  ? _MacHistoryList(
                      emptyText: '暂无消息记录',
                      children: [
                        for (final message in messages)
                          _HistoryMessageCard(
                            api: widget.api,
                            message: message,
                          ),
                      ],
                    )
                  : _MacHistoryList(
                      emptyText: '暂无粘贴板记录',
                      children: [
                        for (final item in clipboardItems)
                          _ClipboardCard(api: widget.api, item: item),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  List<HistoryMessage> get _filteredMessages {
    final selected = _effectiveSelectedDeviceHash;
    if (selected == 'All') {
      return widget.snapshot.historyMessages;
    }
    return widget.snapshot.historyMessages
        .where(
          (message) =>
              message.deviceHash.toUpperCase() == selected.toUpperCase(),
        )
        .toList();
  }

  List<_MacDeviceFilter> get _deviceFilters {
    final filters = <_MacDeviceFilter>[
      const _MacDeviceFilter(hash: 'All', name: '全部设备', deviceType: 'All'),
    ];
    final seen = <String>{'ALL'};
    for (final device in widget.snapshot.boundDevices) {
      final hash = device.hash.toUpperCase();
      if (hash.isEmpty || !seen.add(hash)) {
        continue;
      }
      filters.add(
        _MacDeviceFilter(
          hash: device.hash,
          name: device.name,
          deviceType: device.deviceType,
        ),
      );
    }
    for (final message in widget.snapshot.historyMessages) {
      final hash = message.deviceHash.toUpperCase();
      if (hash.isEmpty || !seen.add(hash)) {
        continue;
      }
      filters.add(
        _MacDeviceFilter(
          hash: message.deviceHash,
          name: message.deviceHash,
          deviceType: 'Unknown',
        ),
      );
    }
    return filters;
  }

  String get _effectiveSelectedDeviceHash {
    if (_selectedDeviceHash == 'All') {
      return 'All';
    }
    final stillExists = _deviceFilters.any(
      (filter) =>
          filter.hash.toUpperCase() == _selectedDeviceHash.toUpperCase(),
    );
    return stillExists ? _selectedDeviceHash : 'All';
  }
}

class _MacHistoryList extends StatelessWidget {
  const _MacHistoryList({required this.emptyText, required this.children});

  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return _EmptyText(emptyText);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
      children: children,
    );
  }
}

class _MacDeviceFilter {
  const _MacDeviceFilter({
    required this.hash,
    required this.name,
    required this.deviceType,
  });

  final String hash;
  final String name;
  final String deviceType;
}

class _MacDeviceFilterBar extends StatelessWidget {
  const _MacDeviceFilterBar({
    required this.devices,
    required this.selectedHash,
    required this.onSelected,
  });

  final List<_MacDeviceFilter> devices;
  final String selectedHash;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final device in devices) ...[
            _MacDeviceFilterChip(
              device: device,
              selected: device.hash.toUpperCase() == selectedHash.toUpperCase(),
              onTap: () => onSelected(device.hash),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _MacDeviceFilterChip extends StatelessWidget {
  const _MacDeviceFilterChip({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final _MacDeviceFilter device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colors.primary : _outlineColor(context),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                device.hash == 'All'
                    ? Icons.all_inclusive_rounded
                    : _deviceIcon(device.deviceType),
                size: 17,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mediumStyle(context).copyWith(
                    color: selected ? colors.onPrimary : colors.onSurface,
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
