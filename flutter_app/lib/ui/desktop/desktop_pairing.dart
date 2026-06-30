part of '../cast_pigeon_home.dart';

class _MacPairingSheetOverlay extends StatefulWidget {
  const _MacPairingSheetOverlay({
    required this.api,
    required this.snapshot,
    required this.onClose,
  });

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;
  final VoidCallback onClose;

  @override
  State<_MacPairingSheetOverlay> createState() =>
      _MacPairingSheetOverlayState();
}

class _MacPairingSheetOverlayState extends State<_MacPairingSheetOverlay> {
  String _pin = '';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints.tightFor(width: 400, height: 350),
            child: _SurfaceCard(
              color: colors.surface,
              child: _content(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final pinDisplay = widget.snapshot.pinDisplay;
    final pinInputDevice = widget.snapshot.pinInputDevice;
    if (pinDisplay != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('配对请求', style: _titleStyle(context)),
          const SizedBox(height: 14),
          Text('${pinDisplay.requestingDevice.deviceName} 请求绑定。'),
          const SizedBox(height: 10),
          const Text('请在对方设备上输入以下配对码：'),
          const SizedBox(height: 16),
          SelectableText(
            pinDisplay.pin,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: _accentColor(context),
              fontWeight: FontWeight.w800,
              fontFamily: 'Menlo',
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: widget.onClose, child: const Text('取消')),
        ],
      );
    }

    if (pinInputDevice != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('输入配对码', style: _titleStyle(context)),
          const SizedBox(height: 14),
          Text('请输入 ${pinInputDevice.deviceName} 上显示的 4 位配对码：'),
          const SizedBox(height: 16),
          SizedBox(
            width: 150,
            child: TextField(
              autofocus: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFamily: 'Menlo',
              ),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '配对码',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _pin = value.trim()),
              onSubmitted: (_) => _verifyPin(pinInputDevice),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: widget.onClose,
                child: const Text('取消'),
              ),
              const SizedBox(width: 20),
              FilledButton(
                onPressed: _pin.length == 4
                    ? () => _verifyPin(pinInputDevice)
                    : null,
                child: const Text('验证'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        Text(
          widget.snapshot.role == DeviceRole.receiver
              ? '寻找附近的发送端...'
              : '正在广播，请在手机端点击绑定',
          style: _titleStyle(context),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        Expanded(
          child: widget.snapshot.role == DeviceRole.receiver
              ? _receiverPairingList(context)
              : const Center(
                  child: SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(strokeWidth: 2.8),
                  ),
                ),
        ),
        OutlinedButton(onPressed: widget.onClose, child: const Text('取消并关闭')),
      ],
    );
  }

  Widget _receiverPairingList(BuildContext context) {
    if (widget.snapshot.onlineDevices.isEmpty) {
      return const Center(
        child: SizedBox.square(
          dimension: 32,
          child: CircularProgressIndicator(strokeWidth: 2.8),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: widget.snapshot.onlineDevices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final device = widget.snapshot.onlineDevices[index];
        return _SurfaceCard(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(
                _deviceIcon(device.deviceType),
                color: _accentColor(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.deviceName, style: _mediumStyle(context)),
                    Text(
                      'Hash: ${device.hash} | Role: ${device.role}',
                      style: _captionStyle(context),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => unawaited(widget.api.requestBinding(device)),
                child: const Text('绑定此设备'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _verifyPin(CastDevice device) {
    if (_pin.length == 4) {
      unawaited(widget.api.verifyBinding(device, _pin));
    }
  }
}
