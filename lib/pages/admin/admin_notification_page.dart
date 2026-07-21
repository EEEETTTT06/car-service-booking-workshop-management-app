import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> notifications = [];
  static const String adminFilterKey =
      'admin_notification_filter';

  String selectedFilter = 'Today';

  Future<void> loadSavedFilter() async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      final savedFilter =
      preferences.getString(adminFilterKey);

      if (!mounted) return;

      setState(() {
        selectedFilter =
        savedFilter == 'All'
            ? 'All'
            : 'Today';
      });
    } catch (error) {
      debugPrint(
        'Failed to load admin notification filter: $error',
      );
    }
  }

  Future<void> saveSelectedFilter(
      String value,
      ) async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      await preferences.setString(
        adminFilterKey,
        value,
      );
    } catch (error) {
      debugPrint(
        'Failed to save admin notification filter: $error',
      );
    }
  }

  @override
  void initState() {
    super.initState();

    loadSavedFilter();
    loadNotifications();
  }

  Future<void> loadNotifications() async {
    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Admin not logged in.');

      final response = await supabase
          .from('admin_notifications')
          .select()
          .eq('admin_id', user.id)
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
          .from('admin_notifications')
          .update({'is_read': true})
          .eq('notification_id', item['notification_id']);

      await loadNotifications();
    } catch (error) {
      showMessage('Failed to update notification: $error');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase
          .from('admin_notifications')
          .update({'is_read': true})
          .eq('admin_id', user.id)
          .eq('is_read', false);

      await loadNotifications();
      showMessage('All notifications marked as read.');
    } catch (error) {
      showMessage('Failed to mark all as read: $error');
    }
  }

  Future<void> deleteNotification(Map<String, dynamic> item) async {
    final deletedItem = Map<String, dynamic>.from(item);

    try {
      await supabase
          .from('admin_notifications')
          .delete()
          .eq('notification_id', item['notification_id']);

      await loadNotifications();

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          content: const Text('Notification deleted.'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.amber,
            onPressed: () async {
              await restoreDeletedNotification(deletedItem);
            },
          ),
        ),
      );
    } catch (error) {
      showMessage('Failed to delete notification: $error');
    }
  }

  Future<void> restoreDeletedNotification(
      Map<String, dynamic> deletedItem,
      ) async {
    try {
      await supabase.from('admin_notifications').insert(deletedItem);

      await loadNotifications();
      showMessage('Notification restored.');
    } catch (error) {
      showMessage('Failed to restore notification: $error');
    }
  }

  Future<bool> showDeleteConfirmation(
      Map<String, dynamic> item,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFFEAEA),
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
              ),
              SizedBox(width: 12),
              Text('Delete Notification'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete this notification?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> confirmAndDeleteNotification(
      Map<String, dynamic> item,
      ) async {
    final confirmed = await showDeleteConfirmation(item);

    if (!confirmed) return;

    await deleteNotification(item);
  }

  Future<void> clearAllNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase
          .from('admin_notifications')
          .delete()
          .eq('admin_id', user.id);

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

    return Icons.notifications;
  }

  Color getNotificationColor(String? type, String title) {
    final text = '${type ?? ''} $title'.toLowerCase();

    if (text.contains('cancel') || text.contains('reject')) return Colors.red;
    if (text.contains('confirm') || text.contains('complete')) {
      return Colors.green;
    }
    if (text.contains('vehicle') || text.contains('claim')) {
      return Colors.orange;
    }
    if (text.contains('quotation')) return Colors.purple;

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

  bool isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  List<Map<String, dynamic>> get filteredNotifications {
    if (selectedFilter == 'All') {
      return notifications;
    }

    final now = DateTime.now();

    return notifications.where((item) {
      final createdAt =
      DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();

      if (createdAt == null) return false;

      return isSameDate(createdAt, now);
    }).toList();
  }

  List<Map<String, dynamic>> getGroupedDisplayItems() {
    final List<Map<String, dynamic>> items = [];
    String? currentGroup;

    for (final notification in filteredNotifications) {
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
        final confirmed = await showDeleteConfirmation(item);

        if (!confirmed) return false;

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
            onPressed: () => confirmAndDeleteNotification(item),
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
        title: const Text('Admin Notifications'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filter Notifications',
            icon: const Icon(Icons.filter_list),
            initialValue: selectedFilter,
            onSelected: (value) async {
              setState(() {
                selectedFilter = value;
              });

              await saveSelectedFilter(value);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'Today',
                child: Row(
                  children: [
                    Icon(Icons.today, color: Color(0xFF339BFF)),
                    SizedBox(width: 10),
                    Text('Today Only'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'All',
                child: Row(
                  children: [
                    Icon(Icons.notifications, color: Color(0xFF339BFF)),
                    SizedBox(width: 10),
                    Text('All Notifications'),
                  ],
                ),
              ),
            ],
          ),
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
        child: filteredNotifications.isEmpty
            ? ListView(
          children: [
            const SizedBox(height: 220),
            Center(
              child: Text(
                selectedFilter == 'Today'
                    ? 'No notifications for today.'
                    : 'No notifications yet.',
                style: const TextStyle(
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