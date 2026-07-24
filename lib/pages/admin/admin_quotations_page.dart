import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../../services/customer_notification_service.dart';
import '../common/app_result_message.dart';

class AdminQuotationsPage extends StatefulWidget {
  final Map<String, dynamic>? initialPendingService;

  const AdminQuotationsPage({
    super.key,
    this.initialPendingService,
  });

  @override
  State<AdminQuotationsPage> createState() => _AdminQuotationsPageState();
}

class _AdminQuotationsPageState extends State<AdminQuotationsPage> {
  String selectedStatus = 'Draft';
  String searchText = '';
  bool isLoading = false;
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  List<Map<String, dynamic>> quotations = [];
  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> pendingServices = [];
  RealtimeChannel? quotationsRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    loadData().then((_) {
      if (!mounted) return;

      if (widget.initialPendingService != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          showCreateQuotationDialog(
            initialPendingService: widget.initialPendingService,
          );
        });
      }
    });

    setupRealtimeSubscription();

    scrollController.addListener(() {
      if (!mounted) return;

      final shouldShow =
          scrollController.hasClients &&
              scrollController.offset > 350;

      if (shouldShow != showBackToTop) {
        setState(() {
          showBackToTop = shouldShow;
        });
      }
    });
  }

  @override
  void dispose() {
    realtimeRefreshTimer?.cancel();

    final channel =
        quotationsRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (!scrollController.hasClients) return;

    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  Future<void> loadData({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      await fetchVehicles();
      await fetchPendingServices();
      await fetchQuotations();

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load quotations: $error',
        );
      } else {
        debugPrint(
          'Realtime quotation refresh failed: $error',
        );
      }
    } finally {
      if (showLoading && mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> fetchVehicles() async {
    final response = await supabase.from('vehicles').select('''
    *,
    customers(name, phone, email)
  ''').order('plate_number', ascending: true);

    vehicles = List<Map<String, dynamic>>.from(response);
  }

  Future<void> fetchPendingServices() async {
    final response = await supabase.from('pending_services').select('''
    *,
    customers(name, phone, email),
    vehicles(plate_number, car_model)
  ''')
        .neq('status', 'Completed')
        .isFilter('quotation_id', null)
        .order('created_at', ascending: false);

    pendingServices = List<Map<String, dynamic>>.from(response);
  }

  Future<void> fetchQuotations() async {
    final response = await supabase.from('quotations').select('''
      *,
      customers(name, phone, email),
      vehicles(plate_number, car_model),
      quotation_items(item_id, item_name, quantity, price)
    ''').order('created_at', ascending: false);

    quotations = List<Map<String, dynamic>>.from(response);
  }
  void setupRealtimeSubscription() {
    if (quotationsRealtimeChannel != null) {
      return;
    }

    quotationsRealtimeChannel = supabase
        .channel(
      'admin-quotations-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotations',
      callback: (payload) {
        debugPrint(
          'Quotation changed: ${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotation_items',
      callback: (payload) {
        debugPrint(
          'Quotation item changed: ${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'pending_services',
      callback: (payload) {
        debugPrint(
          'Quotation pending service changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vehicles',
      callback: (payload) {
        debugPrint(
          'Quotation vehicle changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .subscribe();
  }

  void scheduleRealtimeRefresh() {
    realtimeRefreshTimer?.cancel();

    realtimeRefreshTimer = Timer(
      const Duration(milliseconds: 350),
      refreshQuotationsFromRealtime,
    );
  }

  Future<void> refreshQuotationsFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await loadData(
        showLoading: false,
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }
  String displayCustomer(dynamic customer) {
    final name = customer?.toString().trim() ?? '';
    return name.isEmpty ? 'Not Provided' : name;
  }

  List<Map<String, dynamic>> get filteredQuotations {
    return quotations.where((quotation) {
      final status = quotation['status'] ?? 'Draft';

      final plate =
      (quotation['vehicles']?['plate_number'] ?? '').toString().toLowerCase();

      final model =
      (quotation['vehicles']?['car_model'] ?? '').toString().toLowerCase();

      final customer =
      (quotation['customers']?['name'] ?? '').toString().toLowerCase();

      final search = searchText.toLowerCase();

      return status == selectedStatus &&
          (plate.contains(search) ||
              model.contains(search) ||
              customer.contains(search));
    }).toList();
  }

  double calculateTotal(List items) {
    double total = 0;

    for (final item in items) {
      final qty = int.tryParse(item['quantity'].toString()) ?? 1;
      final price = double.tryParse(item['price'].toString()) ?? 0;
      total += qty * price;
    }

    return total;
  }

  int getStatusCount(String status) {
    return quotations.where((q) => q['status'] == status).length;
  }

  Color getStatusColor(String status) {
    if (status == 'Draft') return Colors.grey;
    if (status == 'Sent') return Colors.orange;
    if (status == 'Confirmed') return Colors.green;
    if (status == 'Cancelled') return Colors.red;
    return Colors.grey;
  }

  Color getStatusBackgroundColor(String status) {
    if (status == 'Draft') return Colors.grey.shade100;
    if (status == 'Sent') return Colors.orange.shade50;
    if (status == 'Confirmed') return Colors.green.shade50;
    if (status == 'Cancelled') return Colors.red.shade50;
    return Colors.grey.shade100;
  }

  Future<void> createQuotation({
    required Map<String, dynamic> selectedVehicleData,
    required String problem,
    required List<Map<String, dynamic>> items,
  }) async {
    final vehicleId =
    selectedVehicleData['vehicle_id']
        ?.toString()
        .trim();

    if (vehicleId == null ||
        vehicleId.isEmpty) {
      showMessage(
        'Vehicle information is missing.',
      );
      return;
    }

    if (items.isEmpty) {
      showMessage(
        'Please add at least one quotation item.',
      );
      return;
    }

    final pendingIdValue =
    selectedVehicleData['pending_id'];

    final String? pendingId =
    pendingIdValue == null ||
        pendingIdValue
            .toString()
            .trim()
            .isEmpty
        ? null
        : pendingIdValue
        .toString()
        .trim();

    final normalizedItems =
    <Map<String, dynamic>>[];

    for (final item in items) {
      final itemName =
          item['item_name']
              ?.toString()
              .trim() ??
              '';

      final quantity =
          int.tryParse(
            item['quantity'].toString(),
          ) ??
              0;

      final price =
      double.tryParse(
        item['price'].toString(),
      );

      if (itemName.isEmpty) {
        showMessage(
          'Every quotation item must have a name.',
        );
        return;
      }

      if (quantity <= 0) {
        showMessage(
          'Every quotation item must have a quantity greater than 0.',
        );
        return;
      }

      if (price == null || price < 0) {
        showMessage(
          'Every quotation item must have a valid price.',
        );
        return;
      }

      normalizedItems.add({
        'item_name': itemName,
        'quantity': quantity,
        'price': price,
      });
    }

    try {
      final rpcResult = await supabase.rpc(
        'create_quotation_draft',
        params: {
          'p_vehicle_id': vehicleId,
          'p_pending_id': pendingId,
          'p_problem_description':
          problem.trim(),
          'p_items': normalizedItems,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid quotation information was returned.',
        );
      }

      final quotation =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final quotationId =
      quotation['quotation_id']
          ?.toString();

      if (quotationId == null ||
          quotationId.isEmpty) {
        throw Exception(
          'Quotation ID was not returned.',
        );
      }

      await loadData(
        showLoading: false,
      );

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Draft';
      });

      showMessage(
        'Quotation saved as draft.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
    } catch (error) {
      showMessage(
        'Failed to create quotation: $error',
      );
    }
  }

  Future<void> updateQuotation({
    required String quotationId,
    required String problem,
    required List<Map<String, dynamic>> items,
    required String status,
    required bool isSent,
  }) async {
    if (quotationId.trim().isEmpty) {
      showMessage(
        'Quotation information is missing.',
      );
      return;
    }

    if (status != 'Draft' || isSent) {
      showMessage(
        'Only a draft quotation can be edited.',
      );

      await loadData(
        showLoading: false,
      );
      return;
    }

    if (items.isEmpty) {
      showMessage(
        'Please add at least one quotation item.',
      );
      return;
    }

    final normalizedItems =
    <Map<String, dynamic>>[];

    for (final item in items) {
      final itemName =
          item['item_name']
              ?.toString()
              .trim() ??
              '';

      final quantity =
          int.tryParse(
            item['quantity'].toString(),
          ) ??
              0;

      final price =
      double.tryParse(
        item['price'].toString(),
      );

      if (itemName.isEmpty) {
        showMessage(
          'Every quotation item must have a name.',
        );
        return;
      }

      if (quantity <= 0) {
        showMessage(
          'Every quotation item must have a quantity greater than 0.',
        );
        return;
      }

      if (price == null || price < 0) {
        showMessage(
          'Every quotation item must have a valid price.',
        );
        return;
      }

      normalizedItems.add({
        'item_name': itemName,
        'quantity': quantity,
        'price': price,
      });
    }

    try {
      final rpcResult = await supabase.rpc(
        'update_quotation_draft',
        params: {
          'p_quotation_id':
          quotationId.trim(),
          'p_problem_description':
          problem.trim(),
          'p_items': normalizedItems,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid quotation information was returned.',
        );
      }

      final quotation =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedQuotationId =
      quotation['quotation_id']
          ?.toString();

      if (returnedQuotationId == null ||
          returnedQuotationId.isEmpty) {
        throw Exception(
          'Quotation ID was not returned.',
        );
      }

      await loadData(
        showLoading: false,
      );

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Draft';
      });

      showMessage(
        'Quotation updated successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);

      await loadData(
        showLoading: false,
      );
    } catch (error) {
      showMessage(
        'Failed to update quotation: $error',
      );
    }
  }

  Future<void> sendQuotationNotification({
    required String customerId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) {
    return CustomerNotificationService.sendToAllDevices(
      customerId: customerId,
      title: title,
      message: message,
      data: data,
    );
  }

  Future<void> markQuotationArrived(
      Map<String, dynamic> quotation,
      ) async {
    final quotationId =
    quotation['quotation_id']
        ?.toString()
        .trim();

    if (quotationId == null ||
        quotationId.isEmpty) {
      showMessage(
        'Quotation information is missing.',
      );
      return;
    }

    try {
      /*
     * The RPC updates the quotation,
     * pending service and booking in one
     * database transaction.
     */
      final rpcResult = await supabase.rpc(
        'mark_confirmed_quotation_arrived',
        params: {
          'p_quotation_id': quotationId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle arrival information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedQuotationId =
      result['quotation_id']
          ?.toString();

      final pendingId =
      result['pending_id']
          ?.toString();

      final customerId =
      result['customer_id']
          ?.toString();

      final vehicleId =
      result['vehicle_id']
          ?.toString();

      final bookingId =
      result['booking_id']
          ?.toString();

      final plate =
      result['plate_number']
          ?.toString()
          .trim();

      if (returnedQuotationId == null ||
          returnedQuotationId.isEmpty) {
        throw Exception(
          'Quotation ID was not returned.',
        );
      }

      if (pendingId == null ||
          pendingId.isEmpty) {
        throw Exception(
          'Pending Service ID was not returned.',
        );
      }

      /*
     * Notification is handled only after
     * the database transaction succeeds.
     */
      if (customerId != null &&
          customerId.isNotEmpty) {
        try {
          const title =
              'Vehicle Arrived';

          final displayPlate =
          plate == null || plate.isEmpty
              ? 'your vehicle'
              : plate;

          final message =
              'Your vehicle $displayPlate has arrived at the workshop and is waiting for service.';

          await supabase
              .from('notifications')
              .insert({
            'customer_id': customerId,
            'vehicle_id': vehicleId,
            'booking_id': bookingId,
            'quotation_id':
            returnedQuotationId,
            'title': title,
            'message': message,
            'notification_type':
            'service',
            'target_page':
            'my_bookings',
            'is_read': false,
          });

          await sendQuotationNotification(
            customerId: customerId,
            title: title,
            message: message,
            data: {
              'notification_type':
              'service',
              'target_page':
              'my_bookings',
              'quotation_id':
              returnedQuotationId,
              'pending_id':
              pendingId,
              if (vehicleId != null)
                'vehicle_id': vehicleId,
              if (bookingId != null)
                'booking_id': bookingId,
            },
          );
        } catch (
        notificationError,
        stackTrace
        ) {
          debugPrint(
            'Vehicle arrival notification failed: '
                '$notificationError',
          );

          debugPrint(
            stackTrace.toString(),
          );
        }
      }

      await loadData(
        showLoading: false,
      );

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Confirmed';
      });

      showMessage(
        'Vehicle marked as arrived and added to Pending Services.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await loadData(
        showLoading: false,
      );
    } catch (error) {
      showMessage(
        'Failed to mark vehicle as arrived: $error',
      );
    }
  }

  Future<void> sendQuotation(
      String quotationId,
      ) async {
    final normalizedQuotationId =
    quotationId.trim();

    if (normalizedQuotationId.isEmpty) {
      showMessage(
        'Quotation information is missing.',
      );
      return;
    }

    try {
      /*
     * The RPC validates the administrator,
     * quotation status, customer, vehicle,
     * quotation items and linked pending service.
     *
     * Quotation and Pending Service are updated
     * in one database transaction.
     */
      final rpcResult = await supabase.rpc(
        'send_quotation_to_customer',
        params: {
          'p_quotation_id':
          normalizedQuotationId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid quotation information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedQuotationId =
      result['quotation_id']
          ?.toString();

      final customerId =
      result['customer_id']
          ?.toString();

      final vehicleId =
      result['vehicle_id']
          ?.toString();

      final bookingId =
      result['booking_id']
          ?.toString();

      final plate =
      result['plate_number']
          ?.toString()
          .trim();

      if (returnedQuotationId == null ||
          returnedQuotationId.isEmpty) {
        throw Exception(
          'Quotation ID was not returned.',
        );
      }

      if (customerId == null ||
          customerId.isEmpty) {
        throw Exception(
          'Customer information was not returned.',
        );
      }

      /*
     * Notification is created only after the
     * quotation transaction succeeds.
     *
     * Notification or FCM failure will not undo
     * the successfully sent quotation.
     */
      try {
        const title =
            'Quotation Available';

        final displayPlate =
        plate == null || plate.isEmpty
            ? 'your vehicle'
            : plate;

        final message =
            'A new quotation is available for $displayPlate. Please review it.';

        await supabase
            .from('notifications')
            .insert({
          'customer_id': customerId,
          'vehicle_id': vehicleId,
          'booking_id': bookingId,
          'quotation_id':
          returnedQuotationId,
          'title': title,
          'message': message,
          'notification_type':
          'quotation',
          'target_page':
          'customer_quotations',
          'is_read': false,
        });

        await sendQuotationNotification(
          customerId: customerId,
          title: title,
          message: message,
          data: {
            'notification_type':
            'quotation',
            'target_page':
            'customer_quotations',
            'quotation_id':
            returnedQuotationId,
            if (vehicleId != null)
              'vehicle_id': vehicleId,
            if (bookingId != null)
              'booking_id': bookingId,
          },
        );
      } catch (
      notificationError,
      stackTrace
      ) {
        debugPrint(
          'Quotation notification failed: '
              '$notificationError',
        );

        debugPrint(
          stackTrace.toString(),
        );
      }

      await loadData(
        showLoading: false,
      );

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Sent';
      });

      showMessage(
        'Quotation sent to customer.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await loadData(
        showLoading: false,
      );
    } catch (error) {
      showMessage(
        'Failed to send quotation: $error',
      );
    }
  }

  Future<void> cancelQuotation(
      String quotationId,
      ) async {
    final normalizedQuotationId =
    quotationId.trim();

    if (normalizedQuotationId.isEmpty) {
      showMessage(
        'Quotation information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'cancel_sent_quotation',
        params: {
          'p_quotation_id':
          normalizedQuotationId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid quotation information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedQuotationId =
      result['quotation_id']
          ?.toString();

      final customerId =
      result['customer_id']
          ?.toString();

      final vehicleId =
      result['vehicle_id']
          ?.toString();

      final bookingId =
      result['booking_id']
          ?.toString();

      final plate =
      result['plate_number']
          ?.toString()
          .trim();

      if (returnedQuotationId == null ||
          returnedQuotationId.isEmpty) {
        throw Exception(
          'Quotation ID was not returned.',
        );
      }

      /*
     * Notification is sent after the database
     * transaction succeeds. A notification error
     * will not undo the cancelled quotation.
     */
      if (customerId != null &&
          customerId.isNotEmpty) {
        try {
          const title =
              'Quotation Cancelled';

          final displayPlate =
          plate == null || plate.isEmpty
              ? 'your vehicle'
              : plate;

          final message =
              'The workshop cancelled the quotation for $displayPlate. A new quotation may be prepared.';

          await supabase
              .from('notifications')
              .insert({
            'customer_id': customerId,
            'vehicle_id': vehicleId,
            'booking_id': bookingId,
            'quotation_id':
            returnedQuotationId,
            'title': title,
            'message': message,
            'notification_type':
            'quotation',
            'target_page':
            'customer_quotations',
            'is_read': false,
          });

          await sendQuotationNotification(
            customerId: customerId,
            title: title,
            message: message,
            data: {
              'notification_type':
              'quotation',
              'target_page':
              'customer_quotations',
              'quotation_id':
              returnedQuotationId,
              if (vehicleId != null)
                'vehicle_id': vehicleId,
              if (bookingId != null)
                'booking_id': bookingId,
            },
          );
        } catch (
        notificationError,
        stackTrace
        ) {
          debugPrint(
            'Quotation cancellation notification failed: '
                '$notificationError',
          );

          debugPrint(
            stackTrace.toString(),
          );
        }
      }

      await loadData(
        showLoading: false,
      );

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Cancelled';
      });

      showMessage(
        'Quotation cancelled.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await loadData(
        showLoading: false,
      );
    } catch (error) {
      showMessage(
        'Failed to cancel quotation: $error',
      );
    }
  }

  Future<void> deleteQuotation(
      String quotationId,
      ) async {
    final normalizedQuotationId =
    quotationId.trim();

    if (normalizedQuotationId.isEmpty) {
      showMessage(
        'Quotation information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'delete_draft_quotation',
        params: {
          'p_quotation_id':
          normalizedQuotationId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid deletion result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedQuotationId =
      result['quotation_id']
          ?.toString();

      final wasDeleted =
          result['deleted'] == true;

      if (returnedQuotationId == null ||
          returnedQuotationId.isEmpty) {
        throw Exception(
          'Quotation ID was not returned.',
        );
      }

      if (!wasDeleted) {
        throw Exception(
          'The quotation was not deleted.',
        );
      }

      await loadData(
        showLoading: false,
      );

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Draft';
      });

      showMessage(
        'Quotation deleted successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await loadData(
        showLoading: false,
      );
    } catch (error) {
      showMessage(
        'Failed to delete quotation: $error',
      );
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
    );
  }

  IconData getQuotationStatusIcon(String status) {
    if (status == 'Draft') {
      return Icons.edit_document;
    }

    if (status == 'Sent') {
      return Icons.send_outlined;
    }

    if (status == 'Confirmed') {
      return Icons.verified_outlined;
    }

    if (status == 'Cancelled') {
      return Icons.cancel_outlined;
    }

    return Icons.receipt_long_outlined;
  }

  Widget buildStatusButton(String status) {
    final isSelected = selectedStatus == status;
    final statusColor = getStatusColor(status);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (selectedStatus == status) {
            return;
          }

          setState(() {
            selectedStatus = status;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 68,
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? statusColor
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? statusColor
                  : statusColor.withOpacity(0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(
                  isSelected ? 0.18 : 0.06,
                ),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  Icon(
                    getQuotationStatusIcon(status),
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : statusColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${getStatusCount(status)}',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : statusColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF1F2937),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              child: Icon(icon, color: const Color(0xFF339BFF)),
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

  Widget buildCardActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
    bool outlined = false,
  }) {
    if (outlined) {
      return Expanded(
        child: SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 17),
            label: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: foregroundColor ?? const Color(0xFF339BFF),
              side: BorderSide(
                color: foregroundColor ?? const Color(0xFF339BFF),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: SizedBox(
        height: 40,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor ?? const Color(0xFF339BFF),
            foregroundColor: foregroundColor ?? Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildQuotationInformationLine({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final displayValue =
    value.trim().isEmpty ? 'Not Provided' : value.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF339BFF),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Text(
            displayValue,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildViewQuotationButton(
      Map<String, dynamic> quotation,
      ) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF339BFF),
          side: const BorderSide(
            color: Color(0xFF339BFF),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: () {
          showQuotationDetailDialog(quotation);
        },
        icon: const Icon(
          Icons.visibility_outlined,
          size: 18,
        ),
        label: const Text(
          'View Quotation Details',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget buildQuotationCard(
      Map<String, dynamic> quotation,
      ) {
    final status =
        quotation['status']?.toString() ??
            'Draft';

    final isArrived =
        quotation['is_arrived'] == true;

    final vehicle =
        quotation['vehicles'] ??
            <String, dynamic>{};

    final customer =
        quotation['customers'] ??
            <String, dynamic>{};

    final items =
        quotation['quotation_items'] as List? ??
            [];

    final total =
        double.tryParse(
          quotation['total'].toString(),
        ) ??
            calculateTotal(items);

    final plate =
        vehicle['plate_number']
            ?.toString()
            .trim() ??
            '';

    final model =
        vehicle['car_model']
            ?.toString()
            .trim() ??
            '';

    final customerName =
    displayCustomer(customer['name']);

    final statusColor =
    getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: statusColor.withOpacity(0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.07),
            blurRadius: 13,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          showQuotationDetailDialog(quotation);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7E5FA),
                      borderRadius:
                      BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.receipt_long,
                      color: Color(0xFF339BFF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          plate.isEmpty
                              ? 'NO PLATE NUMBER'
                              : plate,
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF1F2937),
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          model.isEmpty
                              ? 'Car model not provided'
                              : model,
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color:
                      getStatusBackgroundColor(
                        status,
                      ),
                      borderRadius:
                      BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        Icon(
                          getQuotationStatusIcon(status),
                          color: statusColor,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius:
                  BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    buildQuotationInformationLine(
                      icon: Icons.person_outline,
                      title: 'Customer',
                      value: customerName,
                    ),
                    const SizedBox(height: 11),
                    const Divider(height: 1),
                    const SizedBox(height: 11),
                    buildQuotationInformationLine(
                      icon: Icons.inventory_2_outlined,
                      title: 'Quotation Items',
                      value: '${items.length} item(s)',
                    ),
                    const SizedBox(height: 11),
                    const Divider(height: 1),
                    const SizedBox(height: 11),
                    buildQuotationInformationLine(
                      icon: isArrived
                          ? Icons.check_circle_outline
                          : Icons.schedule,
                      title: 'Vehicle Arrival',
                      value: isArrived
                          ? 'Arrived'
                          : 'Not Arrived',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 13),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius:
                  BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      color: Color(0xFF339BFF),
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'Quotation Total',
                        style: TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      'RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF339BFF),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              buildViewQuotationButton(
                quotation,
              ),

              if (status == 'Draft') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    buildCardActionButton(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      outlined: true,
                      onPressed: () {
                        showEditQuotationDialog(
                          quotation,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    buildCardActionButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      outlined: true,
                      foregroundColor: Colors.red,
                      onPressed: () {
                        showDeleteQuotationDialog(
                          quotation['quotation_id'],
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    buildCardActionButton(
                      icon: Icons.send_outlined,
                      label: 'Send',
                      onPressed: () {
                        showSendQuotationDialog(
                          quotation['quotation_id'],
                        );
                      },
                    ),
                  ],
                ),
              ],

              if (status == 'Sent') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style:
                    OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(
                        color: Colors.red,
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      showCancelQuotationDialog(
                        quotation['quotation_id'],
                      );
                    },
                    icon: const Icon(
                      Icons.cancel_outlined,
                      size: 18,
                    ),
                    label: const Text(
                      'Cancel Quotation',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],

              if (status == 'Confirmed') ...[
                const SizedBox(height: 10),
                if (!isArrived)
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      style:
                      ElevatedButton.styleFrom(
                        backgroundColor:
                        Colors.green,
                        foregroundColor:
                        Colors.white,
                        elevation: 0,
                        shape:
                        RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        showMarkArrivedDialog(
                          quotation,
                        );
                      },
                      icon: const Icon(
                        Icons.login,
                        size: 18,
                      ),
                      label: const Text(
                        'Mark Vehicle Arrived',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius:
                      BorderRadius.circular(14),
                      border: Border.all(
                        color:
                        Colors.green.shade200,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 18,
                        ),
                        SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            'Arrived — Added to Pending Services',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight:
                              FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF339BFF)),
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget buildQuotationDialogSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius:
                  BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: const Color(0xFF339BFF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget buildQuotationDialogInformationRow({
    required IconData icon,
    required String title,
    required String value,
    bool showDivider = true,
  }) {
    final displayValue =
    value.trim().isEmpty ? 'Not Provided' : value.trim();

    return Column(
      children: [
        Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: Colors.black45,
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 6,
              child: Text(
                displayValue,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: 11),
          Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 11),
        ],
      ],
    );
  }

  Widget buildQuotationDialogItem(
      Map<dynamic, dynamic> item,
      ) {
    final quantity =
        int.tryParse(
          item['quantity']?.toString() ?? '',
        ) ??
            1;

    final price =
        double.tryParse(
          item['price']?.toString() ?? '',
        ) ??
            0;

    final subtotal = quantity * price;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.build_outlined,
              color: Color(0xFF339BFF),
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  item['item_name']?.toString() ??
                      'Quotation Item',
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Qty $quantity  ×  RM ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'RM ${subtotal.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Color(0xFF339BFF),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void showQuotationDetailDialog(
      Map<String, dynamic> quotation,
      ) {
    final vehicle =
        quotation['vehicles'] ??
            <String, dynamic>{};

    final customer =
        quotation['customers'] ??
            <String, dynamic>{};

    final status =
        quotation['status']?.toString() ??
            'Draft';

    final isArrived =
        quotation['is_arrived'] == true;

    final items =
        quotation['quotation_items'] as List? ??
            [];

    final total =
        double.tryParse(
          quotation['total'].toString(),
        ) ??
            calculateTotal(items);

    final plate =
        vehicle['plate_number']
            ?.toString()
            .trim() ??
            '';

    final model =
        vehicle['car_model']
            ?.toString()
            .trim() ??
            '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(26),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 470,
              maxHeight:
              MediaQuery.of(dialogContext)
                  .size
                  .height *
                  0.88,
            ),
            child: Column(
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
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF248CF2),
                        Color(0xFF63B3FF),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(0.18),
                          borderRadius:
                          BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.receipt_long,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              plate.isEmpty
                                  ? 'Quotation Details'
                                  : plate,
                              maxLines: 1,
                              overflow:
                              TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              model.isEmpty
                                  ? 'Quotation Details'
                                  : model,
                              maxLines: 1,
                              overflow:
                              TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontWeight:
                                FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(0.18),
                          borderRadius:
                          BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight:
                            FontWeight.bold,
                          ),
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
                          Icons.close,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                    const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        buildQuotationDialogSection(
                          icon: Icons.person_outline,
                          title:
                          'Customer & Vehicle',
                          children: [
                            buildQuotationDialogInformationRow(
                              icon: Icons.person,
                              title: 'Customer',
                              value: displayCustomer(
                                customer['name'],
                              ),
                            ),
                            buildQuotationDialogInformationRow(
                              icon:
                              Icons.phone_outlined,
                              title: 'Phone',
                              value: displayCustomer(
                                customer['phone'],
                              ),
                            ),
                            buildQuotationDialogInformationRow(
                              icon:
                              Icons.directions_car,
                              title: 'Vehicle',
                              value:
                              '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
                              showDivider: false,
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        buildQuotationDialogSection(
                          icon:
                          Icons.description_outlined,
                          title:
                          'Quotation Information',
                          children: [
                            buildQuotationDialogInformationRow(
                              icon:
                              Icons.report_problem_outlined,
                              title: 'Problem',
                              value: quotation[
                              'problem_description']
                                  ?.toString() ??
                                  'No description',
                            ),
                            buildQuotationDialogInformationRow(
                              icon:
                              getQuotationStatusIcon(
                                status,
                              ),
                              title: 'Status',
                              value: status,
                            ),
                            buildQuotationDialogInformationRow(
                              icon: isArrived
                                  ? Icons
                                  .check_circle_outline
                                  : Icons.schedule,
                              title: 'Arrival',
                              value: isArrived
                                  ? 'Arrived'
                                  : 'Not Arrived',
                              showDivider: false,
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        buildQuotationDialogSection(
                          icon:
                          Icons.inventory_2_outlined,
                          title: 'Quotation Items',
                          children: [
                            if (items.isEmpty)
                              Container(
                                width:
                                double.infinity,
                                padding:
                                const EdgeInsets.all(
                                  13,
                                ),
                                decoration:
                                BoxDecoration(
                                  color:
                                  Colors.grey.shade100,
                                  borderRadius:
                                  BorderRadius.circular(
                                    14,
                                  ),
                                ),
                                child: const Text(
                                  'No quotation items found.',
                                  textAlign:
                                  TextAlign.center,
                                  style: TextStyle(
                                    color:
                                    Colors.black54,
                                    fontSize: 12.5,
                                  ),
                                ),
                              )
                            else
                              ...items.map(
                                    (item) =>
                                    buildQuotationDialogItem(
                                      item as Map<
                                          dynamic,
                                          dynamic>,
                                    ),
                              ),
                            const SizedBox(height: 4),
                            Container(
                              width: double.infinity,
                              padding:
                              const EdgeInsets
                                  .symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFEAF4FF,
                                ),
                                borderRadius:
                                BorderRadius.circular(
                                  14,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Quotation Total',
                                      style: TextStyle(
                                        color: Color(
                                          0xFF1F2937,
                                        ),
                                        fontSize: 13,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'RM ${total.toStringAsFixed(2)}',
                                    style:
                                    const TextStyle(
                                      color: Color(
                                        0xFF339BFF,
                                      ),
                                      fontSize: 17,
                                      fontWeight:
                                      FontWeight
                                          .bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style:
                      ElevatedButton.styleFrom(
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
                      icon:
                      const Icon(Icons.check),
                      label: const Text(
                        'Done',
                        style: TextStyle(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showSendQuotationDialog(String quotationId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send Quotation'),
          content: const Text('Send this quotation to the customer?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF339BFF),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await sendQuotation(quotationId);
              },
              child: const Text('Yes, Send'),
            ),
          ],
        );
      },
    );
  }

  void showDeleteQuotationDialog(String quotationId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Quotation'),
          content: const Text(
            'Are you sure you want to delete this draft quotation?',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await deleteQuotation(quotationId);
              },
              child: const Text('Yes, Delete'),
            ),
          ],
        );
      },
    );
  }

  void showCancelQuotationDialog(String quotationId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel Quotation'),
          content: const Text('Are you sure you want to cancel this quotation?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await cancelQuotation(quotationId);
              },
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );
  }

  void showMarkArrivedDialog(
      Map<String, dynamic> quotation,
      ) {
    final vehicle = quotation['vehicles'] ?? {};
    final plate =
        vehicle['plate_number']?.toString() ?? 'this vehicle';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(
                  Icons.directions_car,
                  color: Colors.green,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Mark Vehicle Arrived'),
              ),
            ],
          ),
          content: Text(
            'Please physically check the plate number before continuing.\n\n'
                'Plate Number: $plate\n\n'
                'Mark this vehicle as Arrived and add it to Pending Services?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await markQuotationArrived(quotation);
              },
              icon: const Icon(Icons.check),
              label: const Text('Mark Arrived'),
            ),
          ],
        );
      },
    );
  }

  void showCreateQuotationDialog({
    Map<String, dynamic>? initialPendingService,
  }) {
    Map<String, dynamic>? selectedVehicleData =
        initialPendingService;

    final vehicleSearchController = TextEditingController();
    final problemController = TextEditingController();

    final itemNameController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController();

    final List<Map<String, dynamic>> tempItems = [];

    Widget sectionTitle(String title, IconData icon) {
      return Row(
        children: [
          Icon(icon, color: const Color(0xFF339BFF), size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final search =
            vehicleSearchController.text.trim().toUpperCase();

            final searchedVehicles = vehicles.where((vehicle) {
              final plate =
              (vehicle['plate_number'] ?? '').toString().toUpperCase();

              final model =
              (vehicle['car_model'] ?? '').toString().toUpperCase();

              final customerName =
              (vehicle['customers']?['name'] ?? '')
                  .toString()
                  .toUpperCase();

              return plate.contains(search) ||
                  model.contains(search) ||
                  customerName.contains(search);
            }).toList();

            final total = calculateTotal(tempItems);

            final selectedVehicle =
                selectedVehicleData?['vehicles'] ?? selectedVehicleData ?? {};

            final selectedCustomer =
                selectedVehicleData?['customers'] ??
                    selectedVehicleData?['vehicles']?['customers'] ??
                    {};

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF339BFF), Color(0xFF63B3FF)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.receipt_long, color: Colors.white, size: 42),
                            SizedBox(height: 10),
                            Text(
                              'Create New Quotation',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Select a vehicle and prepare a quotation.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      sectionTitle('Choose Vehicle', Icons.directions_car),
                      const SizedBox(height: 12),

                      TextField(
                        controller: vehicleSearchController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          UpperCaseTextFormatter(),
                        ],
                        onChanged: (_) {
                          setDialogState(() {});
                        },
                        decoration: InputDecoration(
                          hintText: 'SEARCH PLATE, MODEL OR CUSTOMER',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFF339BFF),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (selectedVehicleData != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF4FF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF339BFF).withOpacity(0.18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Selected Vehicle',
                                style: TextStyle(
                                  color: Color(0xFF339BFF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${selectedVehicle['plate_number'] ?? ''} • ${selectedVehicle['car_model'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Customer: ${displayCustomer(selectedCustomer['name'])}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              Text(
                                'Phone: ${displayCustomer(selectedCustomer['phone'])}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              Text(
                                'Status: ${selectedVehicleData!['status'] ?? 'Vehicle Record'}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedVehicleData = null;
                                      vehicleSearchController.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.change_circle_outlined),
                                  label: const Text('Change Vehicle'),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        SizedBox(
                          height: 220,
                          child: searchedVehicles.isEmpty
                              ? const Center(
                            child: Text(
                              'No vehicle found.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                              : ListView.builder(
                            itemCount: searchedVehicles.length,
                            itemBuilder: (context, index) {
                              final vehicle = searchedVehicles[index];
                              final customer = vehicle['customers'] ?? {};

                              return Card(
                                elevation: 0,
                                color: const Color(0xFFF5F7FA),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFFD7E5FA),
                                    child: Icon(
                                      Icons.directions_car,
                                      color: Color(0xFF339BFF),
                                    ),
                                  ),
                                  title: Text(
                                    '${vehicle['plate_number'] ?? ''} - '
                                        '${vehicle['car_model'] ?? ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Customer: '
                                        '${displayCustomer(customer['name'])}',
                                  ),
                                  trailing: const Text(
                                    'SELECT',
                                    style: TextStyle(
                                      color: Color(0xFF339BFF),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  onTap: () {
                                    setDialogState(() {
                                      selectedVehicleData = vehicle;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 22),

                      sectionTitle('Problem Description', Icons.report_problem_outlined),
                      const SizedBox(height: 12),

                      buildInputBox(
                        controller: problemController,
                        label: 'Describe customer complaint or vehicle problem',
                        icon: Icons.description_outlined,
                        maxLines: 3,
                      ),

                      const SizedBox(height: 22),

                      sectionTitle('Quotation Items', Icons.handyman),
                      const SizedBox(height: 12),

                      buildInputBox(
                        controller: itemNameController,
                        label: 'Service / Spare Part Name',
                        icon: Icons.build,
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: buildInputBox(
                              controller: qtyController,
                              label: 'Qty',
                              icon: Icons.numbers,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildInputBox(
                              controller: priceController,
                              label: 'Unit Price',
                              icon: Icons.payments_outlined,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (itemNameController.text.trim().isEmpty ||
                                qtyController.text.trim().isEmpty ||
                                priceController.text.trim().isEmpty) {
                              showMessage('Please complete item information.');
                              return;
                            }

                            setDialogState(() {
                              tempItems.add({
                                'item_name': itemNameController.text.trim(),
                                'quantity':
                                int.tryParse(qtyController.text.trim()) ?? 1,
                                'price':
                                double.tryParse(priceController.text.trim()) ?? 0,
                              });

                              itemNameController.clear();
                              qtyController.text = '1';
                              priceController.clear();
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Quotation Item'),
                        ),
                      ),

                      const SizedBox(height: 14),

                      if (tempItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'No items added yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        ...tempItems.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final qty = int.tryParse(item['quantity'].toString()) ?? 1;
                          final price =
                              double.tryParse(item['price'].toString()) ?? 0;
                          final subtotal = qty * price;

                          return Card(
                            elevation: 0,
                            color: const Color(0xFFF5F7FA),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              title: Text(
                                item['item_name'],
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Qty $qty × RM ${price.toStringAsFixed(2)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'RM ${subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF339BFF),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        tempItems.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Quotation Total',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              'RM ${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF339BFF),
                                fontWeight: FontWeight.bold,
                                fontSize: 19,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF339BFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                if (selectedVehicleData == null ||
                                    tempItems.isEmpty) {
                                  showMessage(
                                    'Please select a vehicle and add at least one item.',
                                  );
                                  return;
                                }

                                Navigator.pop(context);

                                await createQuotation(
                                  selectedVehicleData: selectedVehicleData!,
                                  problem: problemController.text.trim(),
                                  items: tempItems,
                                );
                              },
                              icon: const Icon(Icons.save),
                              label: const Text('Save Draft'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void showEditQuotationDialog(Map<String, dynamic> quotation) {
    final problemController = TextEditingController(
      text: quotation['problem_description'] ?? '',
    );

    final itemNameController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController();

    final List<Map<String, dynamic>> tempItems =
    List<Map<String, dynamic>>.from(quotation['quotation_items'] ?? []);

    final currentStatus = quotation['status'] ?? 'Draft';
    final vehicle = quotation['vehicles'] ?? {};
    final customer = quotation['customers'] ?? {};

    Widget sectionTitle(String title, IconData icon) {
      return Row(
        children: [
          Icon(icon, color: const Color(0xFF339BFF), size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final total = calculateTotal(tempItems);

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF339BFF), Color(0xFF63B3FF)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.edit_document, color: Colors.white, size: 42),
                            SizedBox(height: 10),
                            Text(
                              'Edit Quotation',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Update quotation details before sending to customer.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      sectionTitle('Quotation Vehicle', Icons.directions_car),
                      const SizedBox(height: 12),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF339BFF).withOpacity(0.18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Customer: ${displayCustomer(customer['name'])}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            Text(
                              'Phone: ${displayCustomer(customer['phone'])}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Status: $currentStatus',
                              style: TextStyle(
                                color: getStatusColor(currentStatus),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      sectionTitle('Problem Description', Icons.report_problem_outlined),
                      const SizedBox(height: 12),

                      buildInputBox(
                        controller: problemController,
                        label: 'Describe customer complaint or vehicle problem',
                        icon: Icons.description_outlined,
                        maxLines: 3,
                      ),

                      const SizedBox(height: 22),

                      sectionTitle('Quotation Items', Icons.handyman),
                      const SizedBox(height: 12),

                      buildInputBox(
                        controller: itemNameController,
                        label: 'Service / Spare Part Name',
                        icon: Icons.build,
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: buildInputBox(
                              controller: qtyController,
                              label: 'Qty',
                              icon: Icons.numbers,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildInputBox(
                              controller: priceController,
                              label: 'Unit Price',
                              icon: Icons.payments_outlined,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (itemNameController.text.trim().isEmpty ||
                                qtyController.text.trim().isEmpty ||
                                priceController.text.trim().isEmpty) {
                              showMessage('Please complete item information.');
                              return;
                            }

                            setDialogState(() {
                              tempItems.add({
                                'item_name': itemNameController.text.trim(),
                                'quantity':
                                int.tryParse(qtyController.text.trim()) ?? 1,
                                'price':
                                double.tryParse(priceController.text.trim()) ?? 0,
                              });

                              itemNameController.clear();
                              qtyController.text = '1';
                              priceController.clear();
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Item'),
                        ),
                      ),

                      const SizedBox(height: 14),

                      if (tempItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'No items added yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        ...tempItems.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final qty = int.tryParse(item['quantity'].toString()) ?? 1;
                          final price =
                              double.tryParse(item['price'].toString()) ?? 0;
                          final subtotal = qty * price;

                          return Card(
                            elevation: 0,
                            color: const Color(0xFFF5F7FA),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              title: Text(
                                item['item_name'],
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Qty $qty × RM ${price.toStringAsFixed(2)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'RM ${subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF339BFF),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        tempItems.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Quotation Total',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              'RM ${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF339BFF),
                                fontWeight: FontWeight.bold,
                                fontSize: 19,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF339BFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                if (tempItems.isEmpty) {
                                  showMessage('Please add at least one item.');
                                  return;
                                }

                                Navigator.pop(context);

                                await updateQuotation(
                                  quotationId: quotation['quotation_id'],
                                  problem: problemController.text.trim(),
                                  items: tempItems,
                                  status: currentStatus,
                                  isSent: currentStatus == 'Sent',
                                );
                              },
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayQuotations = filteredQuotations;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Quotations'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const NotificationBell(
            isAdmin: true,
          ),
          IconButton(
            onPressed: () {
              AdminSidebar.show(context);
            },
            icon: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person,
                color: Color(0xFF339BFF),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => loadData(),
        child: ListView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            Container(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quotation Records',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Create, edit, send and manage customer quotations',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      buildSummaryCard(
                        icon: Icons.edit_document,
                        title: 'Draft',
                        value: '${getStatusCount('Draft')}',
                      ),
                      const SizedBox(width: 12),
                      buildSummaryCard(
                        icon: Icons.send,
                        title: 'Sent',
                        value: '${getStatusCount('Sent')}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        searchText = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText:
                      'Search by plate, model, or customer',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                      const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              child: Row(
                children: [
                  buildStatusButton('Draft'),
                  const SizedBox(width: 8),
                  buildStatusButton('Sent'),
                  const SizedBox(width: 8),
                  buildStatusButton('Confirmed'),
                  const SizedBox(width: 8),
                  buildStatusButton('Cancelled'),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$selectedStatus Quotations',
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${displayQuotations.length} record(s)',
                      style: const TextStyle(
                        color: Color(0xFF339BFF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 90,
                ),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (displayQuotations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 70,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                        BorderRadius.circular(24),
                      ),
                      child: Icon(
                        getQuotationStatusIcon(
                          selectedStatus,
                        ),
                        color: getStatusColor(
                          selectedStatus,
                        ),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No $selectedStatus quotations found.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Create a quotation or select another status.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  110,
                ),
                child: Column(
                  children: displayQuotations
                      .map(buildQuotationCard)
                      .toList(),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showBackToTop)
            FloatingActionButton.small(
              heroTag: 'quotationBackToTop',
              backgroundColor:
              const Color(0xFF339BFF),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: scrollToTop,
              child: const Icon(
                Icons.keyboard_arrow_up,
              ),
            ),
          if (showBackToTop)
            const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'createQuotation',
            backgroundColor:
            const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: showCreateQuotationDialog,
            icon: const Icon(Icons.add),
            label: const Text(
              'Create Quotation',
            ),
          ),
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}