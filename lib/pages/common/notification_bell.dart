import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../admin/admin_notification_page.dart';
import '../customer/customer_notification_page.dart';

class NotificationBell extends StatefulWidget {
  final bool isAdmin;

  const NotificationBell({
    super.key,
    required this.isAdmin,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int unreadCount = 0;
  String? customerId;
  RealtimeChannel? notificationChannel;

  @override
  void initState() {
    super.initState();
    setupNotificationBell();
  }

  Future<void> setupNotificationBell() async {
    await loadUnreadCount();
    subscribeToRealtimeNotifications();
  }

  Future<void> loadUnreadCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      int count = 0;

      if (widget.isAdmin) {
        final response = await supabase
            .from('admin_notifications')
            .select('notification_id')
            .eq('admin_id', user.id)
            .eq('is_read', false);

        count = response.length;
      } else {
        final customer = await supabase
            .from('customers')
            .select('customer_id')
            .eq('auth_user_id', user.id)
            .maybeSingle();

        if (customer == null) return;

        customerId = customer['customer_id'].toString();

        final response = await supabase
            .from('notifications')
            .select('notification_id')
            .eq('customer_id', customerId!)
            .eq('is_read', false);

        count = response.length;
      }

      if (!mounted) return;

      setState(() {
        unreadCount = count;
      });
    } catch (error) {
      debugPrint('Load unread notification count error: $error');
    }
  }

  void subscribeToRealtimeNotifications() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final tableName =
    widget.isAdmin ? 'admin_notifications' : 'notifications';

    final filterColumn =
    widget.isAdmin ? 'admin_id' : 'customer_id';

    final filterValue =
    widget.isAdmin ? user.id : customerId;

    if (filterValue == null || filterValue.toString().isEmpty) {
      debugPrint('Realtime notification filter value is missing.');
      return;
    }

    if (notificationChannel != null) {
      supabase.removeChannel(notificationChannel!);
      notificationChannel = null;
    }

    final uniqueChannelName =
        '${tableName}_${filterValue}_${DateTime.now().millisecondsSinceEpoch}';

    notificationChannel = supabase.channel(uniqueChannelName);

    notificationChannel!
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: tableName,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: filterColumn,
        value: filterValue,
      ),
      callback: (payload) async {
        debugPrint('New notification received: ${payload.newRecord}');

        await loadUnreadCount();

        if (!mounted) return;

        showInAppNotification(payload.newRecord);
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: tableName,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: filterColumn,
        value: filterValue,
      ),
      callback: (payload) async {
        debugPrint('Notification updated: ${payload.newRecord}');

        await loadUnreadCount();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: tableName,
      callback: (payload) async {
        debugPrint('Notification deleted.');

        await loadUnreadCount();
      },
    )
        .subscribe((status, error) {
      debugPrint('Notification Realtime status: $status');

      if (error != null) {
        debugPrint('Notification Realtime error: $error');
      }
    });
  }

  bool isNotificationForCurrentUser(Map<String, dynamic> record, String userId) {
    if (widget.isAdmin) {
      return record['admin_id']?.toString() == userId;
    }

    return record['customer_id']?.toString() == customerId;
  }

  void showInAppNotification(Map<String, dynamic> record) {
    if (!mounted) return;

    final title = record['title']?.toString() ?? 'New Notification';
    final message = record['message']?.toString() ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        content: InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            openNotificationPage();
          },
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFD7E5FA),
                child: Icon(
                  Icons.notifications,
                  color: Color(0xFF339BFF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openNotificationPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.isAdmin
            ? const AdminNotificationPage()
            : const CustomerNotificationPage(),
      ),
    );

    await loadUnreadCount();
  }

  @override
  void dispose() {
    if (notificationChannel != null) {
      supabase.removeChannel(notificationChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: openNotificationPage,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.notifications,
                size: 28,
                color: Colors.white,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 2,
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}