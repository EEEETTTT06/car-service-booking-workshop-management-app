import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../common/app_result_message.dart';
import '../common/notification_navigation_service.dart';

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
    if (item['is_read'] == true) return;

    final notificationId =
    item['notification_id']?.toString().trim();

    if (notificationId == null || notificationId.isEmpty) {
      showMessage('Notification information is missing.');
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_notification_action',
        params: {
          'p_action': 'mark_read',
          'p_notification_id': notificationId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid notification update result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(rpcResult);

      if (result['completed'] != true) {
        throw Exception('The notification was not updated.');
      }

      await loadNotifications();
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadNotifications();
    } catch (error) {
      showMessage('Failed to update notification: $error');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final rpcResult = await supabase.rpc(
        'admin_notification_action',
        params: {
          'p_action': 'mark_all_read',
          'p_notification_id': null,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid notification update result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(rpcResult);

      if (result['completed'] != true) {
        throw Exception('Notifications were not updated.');
      }

      await loadNotifications();
      showMessage('All notifications marked as read.');
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadNotifications();
    } catch (error) {
      showMessage('Failed to mark all as read: $error');
    }
  }

  Future<void> deleteNotification(
      Map<String, dynamic> item,
      ) async {
    final notificationId =
    item['notification_id']?.toString().trim();

    if (notificationId == null || notificationId.isEmpty) {
      showMessage('Notification information is missing.');
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_notification_action',
        params: {
          'p_action': 'delete',
          'p_notification_id': notificationId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid notification deletion result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(rpcResult);

      if (result['completed'] != true ||
          result['deleted_item'] is! Map) {
        throw Exception('The notification was not deleted.');
      }

      final deletedItem = Map<String, dynamic>.from(
        result['deleted_item'] as Map,
      );

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
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadNotifications();
    } catch (error) {
      showMessage('Failed to delete notification: $error');
    }
  }

  Future<void> restoreDeletedNotification(
      Map<String, dynamic> deletedItem,
      ) async {
    try {
      final rpcResult = await supabase.rpc(
        'admin_restore_notification',
        params: {
          'p_notification': deletedItem,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid notification restore result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(rpcResult);

      if (result['restored'] != true) {
        throw Exception('The notification was not restored.');
      }

      await loadNotifications();
      showMessage('Notification restored.');
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadNotifications();
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
      final rpcResult = await supabase.rpc(
        'admin_notification_action',
        params: {
          'p_action': 'clear_all',
          'p_notification_id': null,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid notification deletion result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(rpcResult);

      if (result['completed'] != true) {
        throw Exception('Notifications were not cleared.');
      }

      await loadNotifications();
      showMessage('All notifications cleared.');
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadNotifications();
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

    final date = DateTime.tryParse(value.toString())?.toLocal();
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

  Widget buildNotificationCard(
      Map<String, dynamic> item,
      ) {
    final title =
        item['title']?.toString().trim() ??
            'Notification';

    final type =
    item['notification_type']
        ?.toString();

    final isRead =
        item['is_read'] == true;

    final color =
    getNotificationColor(
      type,
      title,
    );

    return Dismissible(
      key: ValueKey(
        item['notification_id'].toString(),
      ),
      direction:
      DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(
          bottom: 14,
        ),
        padding: const EdgeInsets.only(
          right: 22,
        ),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius:
          BorderRadius.circular(20),
        ),
        child: const Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline,
              color: Colors.white,
            ),
            SizedBox(height: 3),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final confirmed =
        await showDeleteConfirmation(
          item,
        );

        if (!confirmed) {
          return false;
        }

        await deleteNotification(item);
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(
          bottom: 14,
        ),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.white
              : const Color(0xFFEAF4FF),
          borderRadius:
          BorderRadius.circular(20),
          border: Border.all(
            color: isRead
                ? Colors.transparent
                : const Color(0xFF339BFF)
                .withOpacity(0.48),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(
                isRead ? 0.045 : 0.075,
              ),
              blurRadius: 11,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius:
          BorderRadius.circular(20),
          onTap: () {
            openNotificationDetails(
              item,
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              15,
              14,
              10,
              14,
            ),
            child: Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius:
                    BorderRadius.circular(15),
                  ),
                  child: Icon(
                    getNotificationIcon(
                      type,
                      title,
                    ),
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow:
                              TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(
                                  0xFF1F2937,
                                ),
                                fontSize: 15,
                                fontWeight: isRead
                                    ? FontWeight.w600
                                    : FontWeight.bold,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding:
                            const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration:
                            BoxDecoration(
                              color: isRead
                                  ? Colors.grey.shade100
                                  : color.withOpacity(
                                0.11,
                              ),
                              borderRadius:
                              BorderRadius.circular(
                                20,
                              ),
                            ),
                            child: Text(
                              isRead
                                  ? 'READ'
                                  : 'NEW',
                              style: TextStyle(
                                color: isRead
                                    ? Colors.black45
                                    : color,
                                fontSize: 9.5,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 14,
                            color:
                            Colors.black38,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              formatDate(
                                item['created_at'],
                              ),
                              style:
                              const TextStyle(
                                color:
                                Colors.black45,
                                fontSize: 10.8,
                                fontWeight:
                                FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons
                                .chevron_right,
                            size: 18,
                            color:
                            Colors.black38,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete Notification',
                  style: IconButton.styleFrom(
                    foregroundColor:
                    Colors.red,
                  ),
                  onPressed: () {
                    confirmAndDeleteNotification(
                      item,
                    );
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String getNotificationTypeLabel(
      Map<String, dynamic> item,
      ) {
    final type = item['notification_type']
        ?.toString()
        .trim();

    if (type == null || type.isEmpty) {
      return 'General Notification';
    }

    return type
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
      '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
    )
        .join(' ');
  }

  Future<void> openNotificationDetails(
      Map<String, dynamic> item,
      ) async {
    await markAsRead(item);

    if (!mounted) return;

    final title =
        item['title']?.toString().trim() ??
            'Notification';

    final message =
        item['message']?.toString().trim() ??
            '';

    final type = item['notification_type']
        ?.toString()
        .trim();

    final color =
    getNotificationColor(type, title);

    final canOpenRelatedPage =
    NotificationNavigationService.canOpen(
      notification: item,
      isAdmin: true,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 470,
              maxHeight:
              MediaQuery.of(dialogContext)
                  .size
                  .height *
                  0.86,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color:
                    Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset:
                    const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding:
                    const EdgeInsets.fromLTRB(
                      18,
                      16,
                      10,
                      16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color,
                          color.withOpacity(0.72),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color:
                            Colors.white.withOpacity(
                              0.18,
                            ),
                            borderRadius:
                            BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: Icon(
                            getNotificationIcon(
                              type,
                              title,
                            ),
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Text(
                                title.isEmpty
                                    ? 'Notification'
                                    : title,
                                maxLines: 2,
                                overflow:
                                TextOverflow.ellipsis,
                                style:
                                const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight:
                                  FontWeight.bold,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                getNotificationTypeLabel(
                                  item,
                                ),
                                maxLines: 1,
                                overflow:
                                TextOverflow.ellipsis,
                                style:
                                const TextStyle(
                                  color:
                                  Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight:
                                  FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                            );
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding:
                      const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding:
                            const EdgeInsets.all(
                              15,
                            ),
                            decoration: BoxDecoration(
                              color:
                              const Color(0xFFF7F9FC),
                              borderRadius:
                              BorderRadius.circular(
                                18,
                              ),
                              border: Border.all(
                                color:
                                Colors.grey.shade200,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons
                                          .subject_rounded,
                                      color:
                                      Color(0xFF339BFF),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Notification Details',
                                      style: TextStyle(
                                        color:
                                        Color(0xFF1F2937),
                                        fontSize: 15,
                                        fontWeight:
                                        FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 13),
                                Text(
                                  message.isEmpty
                                      ? 'No additional information was provided.'
                                      : message,
                                  style: const TextStyle(
                                    color:
                                    Color(0xFF374151),
                                    fontSize: 13.5,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding:
                            const EdgeInsets.all(
                              14,
                            ),
                            decoration: BoxDecoration(
                              color:
                              const Color(0xFFEAF4FF),
                              borderRadius:
                              BorderRadius.circular(
                                16,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons
                                      .schedule_rounded,
                                  color:
                                  Color(0xFF339BFF),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    formatDate(
                                      item[
                                      'created_at'],
                                    ),
                                    style:
                                    const TextStyle(
                                      color:
                                      Color(0xFF1F2937),
                                      fontSize: 12.5,
                                      fontWeight:
                                      FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding:
                                  const EdgeInsets
                                      .symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration:
                                  BoxDecoration(
                                    color:
                                    Colors.green.shade50,
                                    borderRadius:
                                    BorderRadius.circular(
                                      20,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize:
                                    MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons
                                            .check_circle_outline,
                                        color:
                                        Colors.green,
                                        size: 14,
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'READ',
                                        style:
                                        TextStyle(
                                          color:
                                          Colors.green,
                                          fontSize: 10,
                                          fontWeight:
                                          FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(
                          color:
                          Colors.grey.shade200,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style:
                            OutlinedButton.styleFrom(
                              foregroundColor:
                              const Color(
                                0xFF1F2937,
                              ),
                              side: BorderSide(
                                color:
                                Colors.grey.shade300,
                              ),
                              padding:
                              const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                  14,
                                ),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(
                                dialogContext,
                              );
                            },
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (canOpenRelatedPage) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child:
                            ElevatedButton.icon(
                              style: ElevatedButton
                                  .styleFrom(
                                backgroundColor:
                                const Color(
                                  0xFF339BFF,
                                ),
                                foregroundColor:
                                Colors.white,
                                padding:
                                const EdgeInsets
                                    .symmetric(
                                  vertical: 13,
                                ),
                                shape:
                                RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius
                                      .circular(
                                    14,
                                  ),
                                ),
                              ),
                              onPressed: () async {
                                Navigator.pop(
                                  dialogContext,
                                );

                                await NotificationNavigationService
                                    .openRelatedPage(
                                  context,
                                  notification: item,
                                  isAdmin: true,
                                );

                                if (mounted) {
                                  await loadNotifications();
                                }
                              },
                              icon: const Icon(
                                Icons
                                    .open_in_new_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Open Related Page',
                                style: TextStyle(
                                  fontWeight:
                                  FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (mounted) {
      await loadNotifications();
    }
  }

  Widget buildNotificationSummaryCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withOpacity(0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.11),
                borderRadius:
                BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black38,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildNotificationOverview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF339BFF),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Notification Centre',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Review workshop activity and important updates.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              buildNotificationSummaryCard(
                icon: Icons.notifications_none,
                title: 'Total',
                value: '${notifications.length}',
                subtitle: 'All notifications',
                color: const Color(0xFF339BFF),
              ),
              const SizedBox(width: 11),
              buildNotificationSummaryCard(
                icon: Icons.mark_email_unread_outlined,
                title: 'Unread',
                value: '$unreadCount',
                subtitle: 'Need attention',
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style:
                  OutlinedButton.styleFrom(
                    foregroundColor:
                    Colors.white,
                    side: BorderSide(
                      color: Colors.white
                          .withOpacity(0.78),
                    ),
                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                  onPressed: unreadCount > 0
                      ? markAllAsRead
                      : null,
                  icon: const Icon(
                    Icons.done_all,
                    size: 18,
                  ),
                  label: const Text(
                    'Mark All Read',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style:
                  ElevatedButton.styleFrom(
                    backgroundColor:
                    Colors.white,
                    foregroundColor:
                    Colors.red,
                    elevation: 0,
                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                  onPressed:
                  notifications.isNotEmpty
                      ? showClearAllDialog
                      : null,
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'Clear All',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildNotificationFilterButton(
      String filter,
      IconData icon,
      ) {
    final isSelected =
        selectedFilter == filter;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () async {
          if (selectedFilter == filter) {
            return;
          }

          setState(() {
            selectedFilter = filter;
          });

          await saveSelectedFilter(
            filter,
          );
        },
        child: AnimatedContainer(
          duration:
          const Duration(milliseconds: 200),
          height: 46,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF339BFF)
                : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF339BFF)
                  : const Color(0xFF339BFF)
                  .withOpacity(0.14),
            ),
          ),
          child: Row(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? Colors.white
                    : const Color(
                  0xFF339BFF,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                filter == 'Today'
                    ? 'Today'
                    : 'All',
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : const Color(
                    0xFF339BFF,
                  ),
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildNotificationFilterPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        12,
      ),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.62),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          buildNotificationFilterButton(
            'Today',
            Icons.today,
          ),
          const SizedBox(width: 8),
          buildNotificationFilterButton(
            'All',
            Icons.notifications_outlined,
          ),
        ],
      ),
    );
  }

  Widget buildNotificationEmptyState() {
    final isToday =
        selectedFilter == 'Today';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        10,
        16,
        30,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 38,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF339BFF)
              .withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius:
              BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF339BFF),
              size: 37,
            ),
          ),
          const SizedBox(height: 17),
          Text(
            isToday
                ? 'No Notifications Today'
                : 'No Notifications Yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            isToday
                ? 'There are no new admin notifications for today.'
                : 'Workshop updates and activity notifications will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: loadNotifications,
            icon: const Icon(
              Icons.refresh,
            ),
            label: const Text(
              'Refresh',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
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

  int get unreadCount {
    return notifications.where((item) => item['is_read'] != true).length;
  }

  @override
  Widget build(BuildContext context) {
    final groupedItems =
    getGroupedDisplayItems();

    return Scaffold(
      backgroundColor:
      const Color(0xFFD7E5FA),
      appBar: AppBar(
        title:
        const Text('Admin Notifications'),
        centerTitle: true,
        backgroundColor:
        const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: loadNotifications,
        child: CustomScrollView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child:
              buildNotificationOverview(),
            ),
            SliverToBoxAdapter(
              child:
              buildNotificationFilterPanel(),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedFilter ==
                            'Today'
                            ? 'Today Notifications'
                            : 'All Notifications',
                        style:
                        const TextStyle(
                          color: Color(
                            0xFF1F2937,
                          ),
                          fontSize: 18,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration:
                      BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                        BorderRadius.circular(
                          20,
                        ),
                      ),
                      child: Text(
                        '${filteredNotifications.length} item(s)',
                        style:
                        const TextStyle(
                          color: Color(
                            0xFF339BFF,
                          ),
                          fontSize: 11,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (filteredNotifications
                .isEmpty)
              SliverToBoxAdapter(
                child:
                buildNotificationEmptyState(),
              )
            else
              SliverPadding(
                padding:
                const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  28,
                ),
                sliver: SliverList(
                  delegate:
                  SliverChildBuilderDelegate(
                        (context, index) {
                      final item =
                      groupedItems[index];

                      if (item['type'] ==
                          'header') {
                        return buildGroupHeader(
                          item['title'],
                        );
                      }

                      return buildNotificationCard(
                        item['data'],
                      );
                    },
                    childCount:
                    groupedItems.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
