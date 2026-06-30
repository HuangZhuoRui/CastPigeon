part of '../cast_pigeon_home.dart';

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    final sending = status.direction == 'Sending';
    final title = switch (status.phase) {
      'InProgress' => sending ? '正在发送文件' : '正在接收文件',
      'Success' => sending ? '发送成功' : '接收成功',
      'Failed' => sending ? '发送失败' : '接收失败',
      _ => '文件传输',
    };
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _titleStyle(context)),
          const SizedBox(height: 4),
          Text(status.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(status.peerLabel, style: _subtleStyle(context)),
          if (status.phase == 'InProgress') ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: status.progressFraction),
            const SizedBox(height: 4),
            Text(_progressLabel(status), style: _subtleStyle(context)),
          ] else if ((status.detail ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(status.detail!, style: _subtleStyle(context)),
          ],
        ],
      ),
    );
  }
}
