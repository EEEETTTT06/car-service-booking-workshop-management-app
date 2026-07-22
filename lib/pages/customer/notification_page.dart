import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import 'my_vehicles_page.dart';
import 'book_service_page.dart';
import 'customer_quotations_page.dart';
import 'service_records_page.dart';
import '../common/app_result_message.dart';

class CustomerNotificationPage extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  const CustomerNotificationPage({
    super.key,
    this.onNavigate,
  });

  @override
  State<CustomerNotificationPage> createState() =>
      _CustomerNotificationPageState();
}

class _CustomerNotificationPageState
    extends State<CustomerNotificationPage> {
  bool isLoading = false;

  Map<String, dynamic>? currentCustomer;
  List<Map<String, dynamic>> notifications = [];

  @override
  void initState() {
    super.initState();
    loadNotifications();
  }

  Future<void> loadNotifications() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await fetchNotifications();
    } catch (error) {
      showMessage('Failed to load notifications: $error');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchCurrentCustomer() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User not logged in.');
    }

    final response = await supabase
        .from('customers')
        .select()
        .eq('auth_user_id', user.id)
        .maybeSingle();

    if (response == null) {
      throw Exception('Customer profile not found.');
    }

    currentCustomer = Map<String, dynamic>.from(response);
  }

  Future<void> fetchNotifications() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('notifications')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .order('created_at', ascending: false);

    notifications = List<Map<String, dynamic>>.from(response);
  }

  int get unreadCount {
    return notifications.where((n) => n['is_read'] == false).length;
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await supabase.from('notifications').update({
        'is_read': true,
      }).eq('notification_id', notificationId);

      await fetchNotifications();
      if (mounted) setState(() {});
    } catch (error) {
      showMessage('Failed to mark notification as read: $error');
    }
  }

  Future<void> markAllAsRead() async {
    if (currentCustomer == null) return;

    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('customer_id', currentCustomer!['customer_id'])
          .eq('is_read', false);

      await fetchNotifications();
      if (mounted) setState(() {});

      showMessage('All notifications marked as read.');
    } catch (error) {
      showMessage('Failed to mark all as read: $error');
    }
  }

  String formatDate(String? dateText) {
    if (dateText == null || dateText.isEmpty) return '';

    final date = DateTime.parse(dateText).toLocal();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} mins ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  IconData getNotificationIcon(String title) {
    final text = title.toLowerCase();

    if (text.contains('booking')) return Icons.calendar_month;
    if (text.contains('quotation')) return Icons.receipt_long;
    if (text.contains('claim')) return Icons.verified;
    if (text.contains('status')) return Icons.car_repair;
    if (text.contains('completed')) return Icons.check_circle;
    return Icons.notifications;
  }

  Color getNotificationColor(String title) {
    final text = title.toLowerCase();

    if (text.contains('booking')) return Colors.blue;
    if (text.contains('quotation')) return Colors.orange;
    if (text.contains('claim')) return Colors.green;
    if (text.contains('status')) return Colors.purple;
    if (text.contains('completed')) return Colors.green;
    return const Color(0xFF339BFF);
  }

  int? getTargetPageIndex(Map<String, dynamic> notification) {
    final targetPage =
        notification['target_page']?.toString().trim().toLowerCase() ?? '';

    switch (targetPage) {
      case 'my_vehicles':
      case 'vehicles':
      case 'vehicle_claim':
        return 1;
      case 'my_bookings':
      case 'book_service':
      case 'booking':
        return 2;
      case 'customer_quotations':
      case 'quotations':
      case 'quotation':
        return 3;
      case 'service_records':
      case 'records':
      case 'service_record':
        return 4;
    }

    final notificationType =
        notification['notification_type']?.toString().toLowerCase() ?? '';
    final title = notification['title']?.toString().toLowerCase() ?? '';

    if (notificationType.contains('claim') || title.contains('claim')) {
      return 1;
    }

    if (notificationType.contains('quotation') ||
        title.contains('quotation')) {
      return 3;
    }

    if (title.contains('service record') || title.contains('record available')) {
      return 4;
    }

    if (notificationType.contains('booking') ||
        notificationType.contains('service') ||
        title.contains('booking') ||
        title.contains('arrived') ||
        title.contains('status') ||
        title.contains('completed')) {
      return 2;
    }

    return null;
  }

  Widget? buildTargetPage(int pageIndex) {
    switch (pageIndex) {
      case 1:
        return const MyVehiclesPage();
      case 2:
        return const BookServicePage();
      case 3:
        return const CustomerQuotationPage();
      case 4:
        return const ServiceRecordsPage();
      default:
        return null;
    }
  }

  Future<void> handleNotificationTap(
      Map<String, dynamic> notification,
      ) async {
    final notificationId =
        notification['notification_id']?.toString().trim() ?? '';

    if (notification['is_read'] != true && notificationId.isNotEmpty) {
      await markAsRead(notificationId);
    }

    if (!mounted) return;

    final targetIndex = getTargetPageIndex(notification);

    if (targetIndex == null) {
      showMessage('This notification does not have a linked page.');
      return;
    }

    if (widget.onNavigate != null) {
      widget.onNavigate!(targetIndex);
      Navigator.pop(context);
      return;
    }

    final targetPage = buildTargetPage(targetIndex);

    if (targetPage == null) {
      showMessage('Unable to open the linked page.');
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => targetPage,
      ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
    );
  }

  Widget buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFD7E5FA),
            child: Icon(
              Icons.notifications,
              color: Color(0xFF339BFF),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unread Notifications',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '$unreadCount',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0)
            TextButton(
              onPressed: markAllAsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: Color(0xFF339BFF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildNotificationCard(Map<String, dynamic> notification) {
    final title = notification['title']?.toString() ?? 'Notification';
    final message = notification['message']?.toString() ?? '';
    final isRead = notification['is_read'] == true;

    final icon = getNotificationIcon(title);
    final color = getNotificationColor(title);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRead ? Colors.transparent : const Color(0xFF339BFF),
          width: 1,
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
        contentPadding: const EdgeInsets.all(14),
        onTap: () async {
          await handleNotificationTap(notification);
        },
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                ),
              ),
            ),
            if (!isRead)
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFF339BFF),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ),
        trailing: Text(
          formatDate(notification['created_at']),
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: loadNotifications,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              decoration: const BoxDecoration(
                color: Color(0xFF339BFF),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(26),
                  bottomRight: Radius.circular(26),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notification Center',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Stay updated with your booking and vehicle status',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  buildSummaryCard(),
                ],
              ),
            ),
            Expanded(
              child: notifications.isEmpty
                  ? ListView(
                children: const [
                  SizedBox(height: 180),
                  Center(
                    child: Text(
                      'No notifications found.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  return buildNotificationCard(
                    notifications[index],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}