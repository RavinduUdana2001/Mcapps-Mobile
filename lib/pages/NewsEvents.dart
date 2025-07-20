import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mcapps/pages/NewsDetailPage.dart';

class NewsEventsPage extends StatefulWidget {
  const NewsEventsPage({super.key});

  @override
  State<NewsEventsPage> createState() => _NewsEventsPageState();
}

class _NewsEventsPageState extends State<NewsEventsPage> {
  List<dynamic> _items = [];
  bool _isGrid = false;
  bool _isLoading = true;
  Timer? _refreshTimer;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchNewsEvents();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchNewsEvents();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchNewsEvents() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://test.mchostlk.com/api_get_posts.php?ts=${DateTime.now().millisecondsSinceEpoch}',
        ),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          if (mounted) {
            setState(() {
              _items = decoded;
              _isLoading = false;
            });

            // ✅ Scroll to top to show newest item
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        } else {
          throw Exception('Unexpected response format');
        }
      } else {
        throw Exception('Failed to load');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      debugPrint("Error: $e");
    }
  }

  void _openDetailsPage(dynamic item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NewsDetailPage(item: item)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "News & Events",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isGrid ? Icons.view_list : Icons.grid_view,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _isGrid = !_isGrid;
              });
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Colors.white,
        backgroundColor: Colors.black54,
        onRefresh: _fetchNewsEvents,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _items.isEmpty
            ? const Center(
                child: Text(
                  "No news/events found",
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _isGrid ? _buildGridView() : _buildListView(),
              ),
      ),
    );
  }

  Widget _buildListView() {
    return ListView.separated(
      controller: _scrollController,
      itemCount: _items.length,
      physics: const BouncingScrollPhysics(),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _buildCard(_items[index], false),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      controller: _scrollController,
      itemCount: _items.length,
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.65,
      ),
      itemBuilder: (context, index) => _buildCard(_items[index], true),
    );
  }

  Widget _buildCard(dynamic item, bool isGridMode) {
    final String imageUrl = item['image_url']?.toString() ?? '';
    final String title = item['title']?.toString() ?? 'Untitled';
    final String description = item['description']?.toString() ?? '';
    final String createdAt = item['created_at']?.toString() ?? '';

    return GestureDetector(
      onTap: () => _openDetailsPage(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(height: 140, color: Colors.black12),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.broken_image,
                        color: Colors.white70,
                        size: 40,
                      ),
                    )
                  : Container(
                      height: 140,
                      width: double.infinity,
                      color: Colors.black26,
                      child: const Icon(
                        Icons.image_not_supported,
                        color: Colors.white54,
                        size: 40,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isGridMode) ...[
                    const SizedBox(height: 6),
                    Text(
                      description.length > 100
                          ? '${description.substring(0, 100)}...'
                          : description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          createdAt,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white70,
                        size: 14,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
