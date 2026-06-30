part of '../cast_pigeon_home.dart';

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.api, required this.snapshot});

  final CastPigeonApi api;
  final CastPigeonSnapshot snapshot;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final apps = widget.snapshot.installedApps.where((app) {
      if (query.isEmpty) return true;
      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();
    return Column(
      children: [
        _PageTitle(title: '控制台'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('应用同步设置', style: _sectionStyle(context)),
          ),
        ),
        SwitchListTile(
          title: const Text('显示系统应用'),
          subtitle: const Text('默认隐藏系统应用，打开后显示完整应用列表'),
          value: widget.snapshot.showSystemApps,
          onChanged: (show) => unawaited(widget.api.setShowSystemApps(show)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.close_rounded),
                    ),
              hintText: '搜索应用名称或包名',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        Expanded(
          child: apps.isEmpty
              ? const _EmptyText('没有找到匹配的应用')
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 112),
                  itemCount: apps.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 24, endIndent: 24),
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 6,
                      ),
                      leading: _AppIcon(
                        api: widget.api,
                        packageName: app.packageName,
                        appName: app.appName,
                      ),
                      title: Text(
                        app.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Switch(
                        value: app.isSelected,
                        onChanged: (checked) => unawaited(
                          widget.api.setAppSyncEnabled(
                            app.packageName,
                            checked,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
