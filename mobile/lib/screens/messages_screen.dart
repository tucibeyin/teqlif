import 'package:flutter/material.dart';
import '../config/theme.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mesajlar'),
          bottom: const TabBar(
            labelColor: kPrimary,
            unselectedLabelColor: Color(0xFF9CA3AF),
            indicatorColor: kPrimary,
            tabs: [
              Tab(text: 'Mesajlar'),
              Tab(text: 'Bildirimler'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MessagesTab(),
            _NotificationsTab(),
          ],
        ),
      ),
    );
  }
}

class _MessagesTab extends StatelessWidget {
  const _MessagesTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Color(0xFFD1D5DB)),
          SizedBox(height: 16),
          Text(
            'Henüz mesajın yok',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Bir ilanla ilgilendiğinde\nburada görüntülenecek',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }
}

class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_outlined, size: 64, color: Color(0xFFD1D5DB)),
          SizedBox(height: 16),
          Text(
            'Bildirim yok',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Yeni bildirimler burada görünecek',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }
}
