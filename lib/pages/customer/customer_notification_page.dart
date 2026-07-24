import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../common/app_result_message.dart';
import '../common/notification_navigation_service.dart';

class CustomerNotificationPage extends StatefulWidget {
  const CustomerNotificationPage({super.key});

  @override
  State<CustomerNotificationPage> createState() =>
      _CustomerNotificationPageState();
}

class _CustomerNotificationPageState extends State<CustomerNotificationPage> {
  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  static const String customerFilterKey =
      'customer_notification_filter';

  String selectedFilter = 'Today';

  List<Map<String, dynamic>> notifications = [];
  Map<String, dynamic>? currentCustomer;

  Future<void> loadSavedFilter() async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      final savedFilter =
      preferences.getString(customerFilterKey);

      if (!mounted) return;

      setState(() {
        selectedFilter =
        savedFilter == 'All'
            ? 'All'
            : 'Today';
      });
    } catch (error) {
      debugPrint(
        'Failed to load customer notification filter: $error',
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
        customerFilterKey,
        value,
      );
    } catch (error) {
      debugPrint(
        'Failed to save customer notification filter: $error',
      );
    }
  }

  @override
  void initState() {
    super.initState();

    loadSavedFilter();
    loadNotifications();

    scrollController.addListener(() {
      if (!mounted) return;

      if (scrollController.offset > 180 && !showBackToTop) {
        setState(() {
          showBackToTop = true;
        });
      } else if (scrollController.offset <= 180 && showBackToTop) {
        setState(() {
          showBackToTop = false;
        });
      }
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
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
    if (item['is_read'] == true) return;

    final notificationId =
    item['notification_id']?.toString().trim();

    if (notificationId == null || notificationId.isEmpty) {
      showMessage('Notification information is missing.');
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'customer_notification_action',
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
        'customer_notification_action',
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
        'customer_notification_action',
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
        'customer_restore_notification',
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
              Expanded(
                child: Text('Delete Notification'),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete this notification?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
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
    final confirmed =
    await showDeleteConfirmation(item);

    if (!confirmed) return;

    await deleteNotification(item);
  }

  Future<void> clearAllNotifications() async {
    try {
      final rpcResult = await supabase.rpc(
        'customer_notification_action',
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
      DateTime.tryParse(
        item['created_at']?.toString() ?? '',
      )?.toLocal();

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

  Widget buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFD7E5FA),
              child: Icon(
                icon,
                color: const Color(0xFF339BFF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
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

    final type =
    item['notification_type']?.toString();

    final color =
    getNotificationColor(type, title);

    final canOpenRelatedPage =
    NotificationNavigationService.canOpen(
      notification: item,
      isAdmin: false,
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
                    offset: const Offset(0, 12),
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
                                  isAdmin: false,
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

  Widget buildNotificationCard(
      Map<String, dynamic> item,
      ) {
    final title =
        item['title']?.toString().trim() ??
            'Notification';

    final type =
    item['notification_type']?.toString();

    final isRead =
        item['is_read'] == true;

    final color =
    getNotificationColor(type, title);

    return Dismissible(
      key: ValueKey(
        item['notification_id'].toString(),
      ),
      direction:
      DismissDirection.endToStart,
      background: Container(
        margin:
        const EdgeInsets.only(bottom: 14),
        padding:
        const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius:
          BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (_) async {
        final confirmed =
        await showDeleteConfirmation(
          item,
        );

        if (!confirmed) return false;

        await deleteNotification(item);
        return false;
      },
      child: Container(
        margin:
        const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.white
              : const Color(0xFFEAF4FF),
          borderRadius:
          BorderRadius.circular(20),
          border: Border.all(
            color: isRead
                ? Colors.transparent
                : const Color(0xFF339BFF),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color:
              Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius:
          BorderRadius.circular(20),
          onTap: () {
            openNotificationDetails(item);
          },
          child: Padding(
            padding:
            const EdgeInsets.fromLTRB(
              15,
              14,
              10,
              14,
            ),
            child: Row(
              crossAxisAlignment:
              CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color:
                    color.withOpacity(0.12),
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
                      Text(
                        title.isEmpty
                            ? 'Notification'
                            : title,
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.3,
                          fontWeight: isRead
                              ? FontWeight.w600
                              : FontWeight.bold,
                          color: const Color(
                            0xFF1F2937,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: Colors.black38,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              formatDate(
                                item['created_at'],
                              ),
                              maxLines: 1,
                              overflow:
                              TextOverflow
                                  .ellipsis,
                              style:
                              const TextStyle(
                                color:
                                Colors.black45,
                                fontSize: 10.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding:
                            const EdgeInsets
                                .symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration:
                            BoxDecoration(
                              color: isRead
                                  ? Colors
                                  .grey.shade100
                                  : const Color(
                                0xFF339BFF,
                              ).withOpacity(
                                0.12,
                              ),
                              borderRadius:
                              BorderRadius
                                  .circular(
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
                                    : const Color(
                                  0xFF339BFF,
                                ),
                                fontSize: 9.5,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip:
                  'Delete Notification',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 21,
                  ),
                  onPressed: () {
                    confirmAndDeleteNotification(
                      item,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
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
    final groupedItems = getGroupedDisplayItems();
    final displayNotifications =
        filteredNotifications;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Notifications'),
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

              if (scrollController.hasClients) {
                scrollController.animateTo(
                  0,
                  duration: const Duration(
                    milliseconds: 350,
                  ),
                  curve: Curves.easeOut,
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'Today',
                child: Row(
                  children: [
                    Icon(
                      Icons.today,
                      color: Color(0xFF339BFF),
                    ),
                    SizedBox(width: 10),
                    Text('Today Only'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'All',
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications,
                      color: Color(0xFF339BFF),
                    ),
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
                style: TextStyle(
                  color: Colors.white,
                ),
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
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: loadNotifications,
        child: CustomScrollView(
          controller: scrollController,
          physics:
          const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
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
                    bottomLeft:
                    Radius.circular(26),
                    bottomRight:
                    Radius.circular(26),
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
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
                    Text(
                      selectedFilter == 'Today'
                          ? 'Showing today’s notifications'
                          : 'Showing all notifications',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.notifications,
                          title: 'Total',
                          value:
                          '${notifications.length}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon:
                          Icons.mark_email_unread,
                          title: 'Unread',
                          value: '$unreadCount',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 14),
            ),

            if (displayNotifications.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
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
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  100,
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
      floatingActionButton: showBackToTop
          ? FloatingActionButton.small(
        heroTag:
        'customerNotificationBackToTop',
        backgroundColor:
        const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: scrollToTop,
        child: const Icon(
          Icons.keyboard_arrow_up,
        ),
      )
          : null,
    );
  }
}