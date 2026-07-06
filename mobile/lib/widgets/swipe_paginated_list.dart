import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class SwipePaginatedList<T> extends StatefulWidget {
  final Future<List<T>> Function(int offset) fetchPage;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final int maxVisible;
  final double itemHeight;
  final Widget? emptyWidget;
  final void Function(List<T> firstPage)? onFirstLoad;

  const SwipePaginatedList({
    super.key,
    required this.fetchPage,
    required this.itemBuilder,
    this.separatorBuilder,
    this.maxVisible = 5,
    required this.itemHeight,
    this.emptyWidget,
    this.onFirstLoad,
  });

  @override
  State<SwipePaginatedList<T>> createState() => _SwipePaginatedListState<T>();
}

class _SwipePaginatedListState<T> extends State<SwipePaginatedList<T>> {
  final List<T> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchNextPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 50) {
      _fetchNextPage();
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      final newItems = await widget.fetchPage(_offset);
      if (mounted) {
        if (_offset == 0 && newItems.isNotEmpty) {
          widget.onFirstLoad?.call(newItems);
        }
        setState(() {
          _offset += newItems.length;
          _items.addAll(newItems);
          if (newItems.isEmpty || newItems.length < 5) {
            _hasMore = false;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _isLoading) {
      return Container(
        height: widget.itemHeight * widget.maxVisible,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_items.isEmpty && !_isLoading) {
      return widget.emptyWidget ?? Container(
        height: widget.itemHeight,
        alignment: Alignment.center,
        child: Text("Veri bulunamadı.", style: TextStyle(color: AppColors.textSecondary(context))),
      );
    }

    final visibleCount = _items.length.clamp(1, widget.maxVisible);

    return Container(
      height: visibleCount * widget.itemHeight,
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.separated(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _items.length + (_hasMore ? 1 : 0),
          separatorBuilder: (ctx, i) => widget.separatorBuilder?.call(ctx, i) ?? Divider(height: 1, thickness: 1, color: AppColors.border(ctx)),
          itemBuilder: (ctx, i) {
            if (i == _items.length) {
              return SizedBox(
                height: widget.itemHeight,
                child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            return SizedBox(
              height: widget.itemHeight,
              child: widget.itemBuilder(ctx, _items[i]),
            );
          },
        ),
      ),
    );
  }
}
