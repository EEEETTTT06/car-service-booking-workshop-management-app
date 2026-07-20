import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class CustomerNotificationPage extends StatefulWidget {
  const CustomerNotificationPage({super.key});

  @override
  State<CustomerNotificationPage> createState() =>
      _CustomerNotificationPageState();
}

class _CustomerNotificationPageState extends State<CustomerNotificationPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> notifications = [];
  Map<String, dynamic>? currentCustomer;

  @override
  void initState() {
    super.initState();
    loadNotifications();
  }

  Future<void> fetchCurrentCustomer() async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in.');

    final response = await supabase
        .from('customers')
        .select('customer_id')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    if (response == null) {
      throw Exception('Customer profile not found.');
    }

    currentCustomer = Map<String, dynamic>.from(response);
  }

  Future<void> loadNotifications() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();

      final response = await supabase
          .from('notifications')
          .select()
          .eq('customer_id', currentCustomer!['customer_id'])
          .order('created_at', ascending: false);

      notifications = List<Map<String, dynamic>>.from(response);
    } catch (error) {
      showMessage('Failed to load notifications: $error');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> markAsRead(Map<String, dynamic> item) async {
    try {
      if (item['is_read'] == true) return;

      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('notification_id', item['notification_id']);

      await loadNotifications();
    } catch (error) {
      showMessage('Failed to update notification: $error');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      if (currentCustomer == null) {
        await fetchCurrentCustomer();
      }

      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('customer_id', currentCustomer!['customer_id'])
          .eq('is_read', false);

      await loadNotifications();
      showMessage('All notifications marked as read.');
    } catch (error) {
      showMessage('Failed to mark all as read: $error');
    }
  }

  Future<void> deleteNotification(Map<String, dynamic> item) async {
    try {
      await supabase
          .from('notifications')
          .delete()
          .eq('notification_id', item['notification_id']);

      await loadNotifications();
      showMessage('Notification deleted.');
    } catch (error) {
      showMessage('Failed to delete notification: $error');
    }
  }

  Future<void> clearAllNotifications() async {
    try {
      if (currentCustomer == null) {
        await fetchCurrentCustomer();
      }

      await supabase
          .from('notifications')
          .delete()
          .eq('customer_id', currentCustomer!['customer_id']);

      await loadNotifications();
      showMessage('All notifications cleared.');
    } catch (error) {
      showMessage('Failed to clear notifications: $error');
    }
  }

  void showClearAllDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear All Notifications'),
          content: const Text(
            'Are you sure you want to delete all notifications?',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await clearAllNotifications();
              },
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
  }

  IconData getNotificationIcon(String? type, String title) {
    final text = '${type ?? ''} $title'.toLowerCase();

    if (text.contains('booking') || text.contains('appointment')) {
      return Icons.calendar_month;
    }
    if (text.contains('quotation')) return Icons.receipt_long;
    if (text.contains('vehicle') || text.contains('claim')) {
      return Icons.directions_car;
    }
    if (text.contains('cancel')) return Icons.cancel;
    if (text.contains('complete')) return Icons.check_circle;
    if (text.contains('ready')) return Icons.car_repair;

    return Icons.notifications;
  }

  Color getNotificationColor(String? type, String title) {
    final text = '${type ?? ''} $title'.toLowerCase();

    if (text.contains('cancel') || text.contains('reject')) return Colors.red;
    if (text.contains('confirm') ||
        text.contains('complete') ||
        text.contains('approved')) {
      return Colors.green;
    }
    if (text.contains('vehicle') || text.contains('claim')) {
      return Colors.orange;
    }
    if (text.contains('quotation')) return Colors.purple;
    if (text.contains('ready')) return Colors.teal;

    return const Color(0xFF339BFF);
  }

  String formatDate(dynamic value) {
    if (value == null) return '';

    final date = DateTime.tryParse(value.toString());
    if (date == null) return '';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}  '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String getDateGroup(dynamic value) {
    if (value == null) return 'Earlier';

    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return 'Earlier';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);
    final difference = today.difference(itemDate).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference <= 7) return 'This Week';

    return 'Earlier';
  }

  List<Map<String, dynamic>> getGroupedDisplayItems() {
    final List<Map<String, dynamic>> items = [];
    String? currentGroup;

    for (final notification in notifications) {
      final group = getDateGroup(notification['created_at']);

      if (group != currentGroup) {
        currentGroup = group;
        items.add({
          'type': 'header',
          'title': group,
        });
      }

      items.add({
        'type': 'notification',
        'data': notification,
      });
    }

    return items;
  }

  Widget buildGroupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.black12,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildNotificationCard(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? 'Notification';
    final message = item['message']?.toString() ?? '';
    final type = item['notification_type']?.toString();
    final isRead = item['is_read'] == true;
    final color = getNotificationColor(type, title);

    return Dismissible(
      key: ValueKey(item['notification_id'].toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (_) async {
        await deleteNotification(item);
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isRead ? Colors.transparent : const Color(0xFF339BFF),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListTile(
          onTap: () => markAsRead(item),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            child: Icon(
              getNotificationIcon(type, title),
              color: color,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ),
              if (!isRead)
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: isRead ? Colors.black54 : Colors.black87,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatDate(item['created_at']),
                  style: const TextStyle(
                    color: Colors.black45,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          trailing: IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.red,
              size: 22,
            ),
            onPressed: () => deleteNotification(item),
          ),
        ),
      ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int get unreadCount {
    return notifications.where((item) => item['is_read'] != true).length;
  }

  @override
  Widget build(BuildContext context) {
    final groupedItems = getGroupedDisplayItems();

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: markAllAsRead,
              child: const Text(
                'Read All',
                style: TextStyle(color: Colors.white),
              ),
            ),
          if (notifications.isNotEmpty)
            IconButton(
              onPressed: showClearAllDialog,
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: loadNotifications,
        child: notifications.isEmpty
            ? ListView(
          children: const [
            SizedBox(height: 220),
            Center(
              child: Text(
                'No notifications yet.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        )
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupedItems.length,
          itemBuilder: (context, index) {
            final item = groupedItems[index];

            if (item['type'] == 'header') {
              return buildGroupHeader(item['title']);
            }

            return buildNotificationCard(item['data']);
          },
        ),
      ),
    );
  }
}