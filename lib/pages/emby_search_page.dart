// [QBSenHook] v7.5: 顶部统一控件组的"搜索"入口。
// 全屏 Emby 搜索页：输入关键词调用 EmbyService.searchMediaItems，
// 结果以 3 列海报网格展示，点击进入 Emby 详情页。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';

class EmbySearchPage extends StatefulWidget {
  const EmbySearchPage({super.key});

  @override
  State<EmbySearchPage> createState() => _EmbySearchPageState();
}

class _EmbySearchPageState extends State<EmbySearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<EmbyMediaItem> _results = [];
  bool _isSearching = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final keyword = query.trim();
    if (keyword.isEmpty) {
      setState(() {
        _results.clear();
        _isSearching = false;
        _isLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isLoading = true);
      List<EmbyMediaItem> found = [];
      try {
        found = await EmbyService.instance.searchMediaItems(
          keyword,
          limit: 60,
        );
      } catch (e) {
        debugPrint('Emby 搜索失败: $e');
      }
      if (!mounted) return;
      setState(() {
        _results = found;
        _isSearching = true;
        _isLoading = false;
      });
    });
  }

  void _openDetail(EmbyMediaItem item) {
    MediaServerDetailPage.show(context, item.id, MediaServerType.emby);
  }

  String _posterUrl(EmbyMediaItem item) {
    if (item.imagePrimaryTag == null) return '';
    return EmbyService.instance.getImageUrl(
      item.id,
      tag: item.imagePrimaryTag,
      width: 400,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black45;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('搜索', style: TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                onChanged: _onQueryChanged,
                onSubmitted: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: '搜索电影、剧集、视频…',
                  hintStyle: TextStyle(color: secondaryTextColor),
                  prefixIcon: Icon(Icons.search, color: secondaryTextColor),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.clear, color: secondaryTextColor),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFFE5E5EA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                ),
              ),
            ),
            Expanded(child: _buildBody(textColor, secondaryTextColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Color textColor, Color secondaryTextColor) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_isSearching && _results.isEmpty && !_isLoading) {
      return Center(
        child: Text(
          '输入关键词搜索 Emby 媒体库',
          style: TextStyle(color: secondaryTextColor, fontSize: 15),
        ),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '未找到相关内容',
          style: TextStyle(color: secondaryTextColor, fontSize: 15),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 0.56, // 海报 2:3 加底部文字
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: double.infinity,
                    child: _posterUrl(item).isEmpty
                        ? Container(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFE5E5EA),
                            child: Icon(
                              Icons.play_circle_outline,
                              color: secondaryTextColor,
                              size: 28,
                            ),
                          )
                        : Image.network(
                            _posterUrl(item),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFE5E5EA),
                              child: Icon(
                                Icons.photo_outlined,
                                color: secondaryTextColor,
                                size: 28,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (item.productionYear != null)
                Text(
                  '${item.productionYear}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondaryTextColor, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }
}
