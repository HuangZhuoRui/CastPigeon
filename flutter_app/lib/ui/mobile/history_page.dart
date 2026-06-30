part of '../cast_pigeon_home.dart';

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  bool _messages = true;

  @override
  Widget build(BuildContext context) {
    final messages = widget.snapshot.historyMessages;
    final clipboardItems = widget.snapshot.clipboardItems;
    return Column(
      children: [
        _PageTitle(title: '发送历史记录'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('消息')),
            ButtonSegment(value: false, label: Text('粘贴板')),
          ],
          selected: {_messages},
          onSelectionChanged: (selection) =>
              setState(() => _messages = selection.first),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
            children: [
              if (_messages && messages.isEmpty) const _EmptyText('暂无发送记录'),
              if (!_messages && clipboardItems.isEmpty)
                const _EmptyText('暂无粘贴板记录'),
              if (_messages)
                for (final message in messages)
                  _HistoryMessageCard(api: widget.api, message: message)
              else
                for (final item in clipboardItems)
                  _ClipboardCard(api: widget.api, item: item),
            ],
          ),
        ),
      ],
    );
  }
}
