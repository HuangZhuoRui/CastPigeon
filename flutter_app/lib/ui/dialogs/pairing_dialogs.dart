part of '../cast_pigeon_home.dart';

class _SnapshotDialogs extends StatelessWidget {
  const _SnapshotDialogs({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (snapshot.phase == ConnectionPhase.pairingRequest &&
            snapshot.pairingDeviceName != null)
          _DeferredDialog(
            key: ValueKey('ble-pairing-${snapshot.pairingDeviceName}'),
            child: _BlePairingRequestDialog(
              api: api,
              pairingDeviceName: snapshot.pairingDeviceName!,
            ),
          ),
        if (snapshot.pinDisplay != null)
          _DeferredDialog(
            key: ValueKey(
              'pin-display-${snapshot.pinDisplay!.requestingDevice.hash}-${snapshot.pinDisplay!.pin}',
            ),
            child: _PinDisplayDialog(
              api: api,
              pinDisplay: snapshot.pinDisplay!,
            ),
          ),
        if (snapshot.pinInputDevice != null)
          _DeferredDialog(
            key: ValueKey('pin-input-${snapshot.pinInputDevice!.hash}'),
            child: _PinInputDialog(api: api, device: snapshot.pinInputDevice!),
          ),
      ],
    );
  }
}

class _BlePairingRequestDialog extends StatelessWidget {
  const _BlePairingRequestDialog({
    required this.api,
    required this.pairingDeviceName,
  });

  final CastPigeonApi api;
  final String pairingDeviceName;

  @override
  Widget build(BuildContext context) {
    final deviceName = pairingDeviceName.split('|').first;
    return AlertDialog(
      title: const Text('配对请求'),
      content: Text('收到来自 [$deviceName] 的请求，是否允许并绑定该设备？'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(api.rejectPairingRequest());
          },
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(api.approvePairingRequest());
          },
          child: const Text('允许并绑定'),
        ),
      ],
    );
  }
}

class _PinDisplayDialog extends StatelessWidget {
  const _PinDisplayDialog({required this.api, required this.pinDisplay});

  final CastPigeonApi api;
  final PinDisplay pinDisplay;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配对请求'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${pinDisplay.requestingDevice.deviceName} 请求绑定。'),
          const SizedBox(height: 8),
          const Text('请在对方设备上输入以下配对码：'),
          const SizedBox(height: 16),
          Text(
            pinDisplay.pin,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: _accentColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(api.cancelPairingPrompt());
          },
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _PinInputDialog extends StatefulWidget {
  const _PinInputDialog({required this.api, required this.device});

  final CastPigeonApi api;
  final CastDevice device;

  @override
  State<_PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends State<_PinInputDialog> {
  String _pin = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入配对码'),
      content: TextField(
        maxLength: 4,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '请输入 ${widget.device.deviceName} 上显示的 4 位配对码',
        ),
        onChanged: (value) => setState(() => _pin = value),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(widget.api.cancelPairingPrompt());
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _pin.length == 4
              ? () {
                  Navigator.of(context).pop();
                  unawaited(widget.api.verifyBinding(widget.device, _pin));
                }
              : null,
          child: const Text('验证'),
        ),
      ],
    );
  }
}

class _DeferredDialog extends StatefulWidget {
  const _DeferredDialog({super.key, required this.child});

  final Widget child;

  @override
  State<_DeferredDialog> createState() => _DeferredDialogState();
}

class _DeferredDialogState extends State<_DeferredDialog> {
  bool _shown = false;
  NavigatorState? _navigator;
  DialogRoute<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator ??= Navigator.of(context, rootNavigator: true);
    if (_shown) return;
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _route != null) return;
      final navigator = _navigator;
      if (navigator == null) return;
      final route = DialogRoute<void>(
        context: context,
        builder: (_) => widget.child,
      );
      _route = route;
      unawaited(
        navigator.push<void>(route).whenComplete(() {
          _route = null;
        }),
      );
    });
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null && route.isActive) {
      _navigator?.removeRoute(route);
    }
    _route = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
