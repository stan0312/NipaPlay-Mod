import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart'
    show MediaServerType, NetworkMediaServerDialog;

class RemoteMediaLibrarySettingsContent extends StatefulWidget {
  const RemoteMediaLibrarySettingsContent({super.key});

  @override
  State<RemoteMediaLibrarySettingsContent> createState() =>
      _RemoteMediaLibrarySettingsContentState();
}

class _RemoteMediaLibrarySettingsContentState
    extends State<RemoteMediaLibrarySettingsContent> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final cardColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: Text(
          '设置',
          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Consumer<EmbyProvider>(
        builder: (context, embyProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 添加媒体库
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(Icons.cloud_outlined, color: textColor),
                  title: Text(
                    '添加媒体库',
                    style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    embyProvider.isConnected
                        ? '已连接: ${embyProvider.serverUrl}'
                        : '未连接 Emby 服务器',
                    style: TextStyle(color: subtextColor, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: subtextColor),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NetworkMediaServerDialog(
                          serverType: MediaServerType.emby,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // 调试日志
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(Icons.bug_report_outline, color: textColor),
                  title: Text(
                    '调试日志',
                    style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '查看收藏查询等调试信息',
                    style: TextStyle(color: subtextColor, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right, color: subtextColor),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DebugLogPage(
                          bgColor: bgColor,
                          cardColor: cardColor,
                          textColor: textColor,
                          subtextColor: subtextColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class DebugLogPage extends StatelessWidget {
  final Color bgColor;
  final Color cardColor;
  final Color textColor;
  final Color subtextColor;

  const DebugLogPage({
    super.key,
    required this.bgColor,
    required this.cardColor,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: Text('调试日志', style: TextStyle(color: textColor, fontSize: 18)),
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: subtextColor),
            onPressed: () {
              DebugLogService().clearLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已清空')),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: DebugLogService(),
        builder: (context, _) {
          final logs = DebugLogService().logEntries.reversed.toList();
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final entry = logs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  entry.message,
                  style: TextStyle(color: textColor, fontSize: 13, height: 1.4),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
