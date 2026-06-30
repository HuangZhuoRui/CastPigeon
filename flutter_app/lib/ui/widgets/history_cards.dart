part of '../cast_pigeon_home.dart';

class _HistoryMessageCard extends StatelessWidget {
  const _HistoryMessageCard({required this.api, required this.message});

  final CastPigeonApi api;
  final HistoryMessage message;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppIcon(
            api: api,
            packageName: null,
            appName: message.appName,
            useHistoryCache: true,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        message.appName,
                        style: _mediumStyle(context),
                      ),
                    ),
                    Text(
                      _formatTimestamp(message.timestamp),
                      style: _captionStyle(context),
                    ),
                  ],
                ),
                if (message.title.isNotEmpty)
                  Text(
                    message.title,
                    style: _mediumStyle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (message.content.isNotEmpty)
                  Text(
                    message.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipboardCard extends StatelessWidget {
  const _ClipboardCard({required this.api, required this.item});

  final CastPigeonApi api;
  final ClipboardHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final direction = switch (item.direction) {
      'sent_to_mac' => '发送到 Mac',
      'received_from_mac' => '来自 Mac',
      'sent_to_android' => '发送到手机',
      'received_from_android' => '来自手机',
      _ => '粘贴板',
    };
    return _SurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        direction,
                        style: _mediumStyle(
                          context,
                        ).copyWith(color: _accentColor(context)),
                      ),
                    ),
                    Text(
                      _formatTimestamp(item.timestamp),
                      style: _captionStyle(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.content,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '复制粘贴板内容',
            onPressed: () => unawaited(api.copyClipboardHistory(item.content)),
            icon: const Icon(Icons.content_copy_rounded),
          ),
        ],
      ),
    );
  }
}
