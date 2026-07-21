import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../../services/customer_notification_service.dart';

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
    try {
      final vehicleId = selectedVehicleData['vehicle_id'];
      final customerId = selectedVehicleData['customer_id'] ??
          selectedVehicleData['user_id'];

      String? pendingId = selectedVehicleData['pending_id']?.toString();
      String? bookingId = selectedVehicleData['booking_id']?.toString();

      if (vehicleId == null) {
        showMessage(
          'Vehicle information is missing.',
        );
        return;
      }

      if (customerId == null ||
          customerId.toString().trim().isEmpty) {
        showMessage(
          'Please link this vehicle to a customer before creating a quotation.',
        );
        return;
      }

      if (pendingId != null && pendingId.isNotEmpty) {
        final latestPendingService = await supabase
            .from('pending_services')
            .select('pending_id, quotation_id, status')
            .eq('pending_id', pendingId)
            .maybeSingle();

        if (latestPendingService == null) {
          showMessage('Pending service record was not found.');
          return;
        }

        if (latestPendingService['status'] == 'Completed') {
          showMessage(
            'Cannot create a quotation for a completed service.',
          );
          return;
        }

        if (latestPendingService['quotation_id'] != null) {
          showMessage(
            'A quotation already exists for this pending service.',
          );
          return;
        }
      } else {
        // A quotation created directly from Quotation Management
        // does not enter Pending Services until the vehicle arrives.
        pendingId = null;
        bookingId = null;
      }

      final total = calculateTotal(items);

      final quotation = await supabase.from('quotations').insert({
        'booking_id': bookingId,
        'customer_id': customerId,
        'vehicle_id': vehicleId,
        'problem_description': problem,
        'total': total,
        'status': 'Draft',
        'is_sent': false,

        // Existing Pending Service means vehicle is already at workshop.
        'is_arrived': pendingId != null && pendingId.isNotEmpty,

        'updated_at': DateTime.now().toIso8601String(),
      }).select().single();

      for (final item in items) {
        await supabase.from('quotation_items').insert({
          'quotation_id': quotation['quotation_id'],
          'item_name': item['item_name'],
          'quantity': item['quantity'],
          'price': item['price'],
        });
      }

      if (pendingId != null && pendingId.isNotEmpty) {
        await supabase.from('pending_services').update({
          'quotation_id': quotation['quotation_id'],
          'note': 'Quotation created and waiting to be sent to customer.',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('pending_id', pendingId);
      }

      await loadData();

      if (mounted) {
        setState(() {});
      }

      showMessage('Quotation saved as draft.');
    } catch (error) {
      showMessage('Failed to create quotation: $error');
    }
  }

  Future<void> updateQuotation({
    required String quotationId,
    required String problem,
    required List<Map<String, dynamic>> items,
    required String status,
    required bool isSent,
  }) async {
    try {
      final currentQuotation = await supabase
          .from('quotations')
          .select('quotation_id, status')
          .eq(
        'quotation_id',
        quotationId,
      )
          .maybeSingle();

      if (currentQuotation == null) {
        showMessage(
          'Quotation was not found.',
        );
        return;
      }

      if (currentQuotation['status'] != 'Draft') {
        showMessage(
          'Only a draft quotation can be edited.',
        );

        await loadData();
        return;
      }

      if (items.isEmpty) {
        showMessage(
          'Please add at least one quotation item.',
        );
        return;
      }

      final total = calculateTotal(items);

      final updatedQuotation = await supabase
          .from('quotations')
          .update({
        'problem_description': problem.trim(),
        'total': total,
        'status': 'Draft',
        'is_sent': false,
        'updated_at':
        DateTime.now().toIso8601String(),
      })
          .eq(
        'quotation_id',
        quotationId,
      )
          .eq(
        'status',
        'Draft',
      )
          .select('quotation_id')
          .maybeSingle();

      if (updatedQuotation == null) {
        showMessage(
          'Quotation status has changed. Please refresh the page.',
        );

        await loadData();
        return;
      }

      await supabase
          .from('quotation_items')
          .delete()
          .eq(
        'quotation_id',
        quotationId,
      );

      for (final item in items) {
        await supabase.from('quotation_items').insert({
          'quotation_id': quotationId,
          'item_name': item['item_name'],
          'quantity': item['quantity'],
          'price': item['price'],
        });
      }

      await loadData();

      showMessage(
        'Quotation updated successfully.',
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
    try {
      final quotationId =
      quotation['quotation_id']?.toString();

      final vehicleId = quotation['vehicle_id'];
      final customerId = quotation['customer_id'];
      final bookingId = quotation['booking_id'];

      if (quotationId == null ||
          quotationId.isEmpty) {
        showMessage(
          'Quotation information is missing.',
        );
        return;
      }

      if (vehicleId == null) {
        showMessage(
          'Vehicle information is missing.',
        );
        return;
      }

      if (quotation['status'] != 'Confirmed') {
        showMessage(
          'Only a confirmed quotation can be marked as arrived.',
        );
        return;
      }

      if (quotation['is_arrived'] == true) {
        showMessage(
          'This vehicle has already been marked as arrived.',
        );
        return;
      }

      final activePendingResponse = await supabase
          .from('pending_services')
          .select('''
          pending_id,
          quotation_id,
          customer_id,
          booking_id,
          status,
          note
        ''')
          .eq(
        'vehicle_id',
        vehicleId,
      )
          .neq(
        'status',
        'Completed',
      )
          .order(
        'created_at',
        ascending: false,
      )
          .limit(1);

      final activePendingRows =
      List<Map<String, dynamic>>.from(
        activePendingResponse,
      );

      final activePending = activePendingRows.isEmpty
          ? null
          : activePendingRows.first;

      if (activePending != null) {
        final linkedQuotationId =
        activePending['quotation_id']?.toString();

        if (linkedQuotationId != null &&
            linkedQuotationId.isNotEmpty &&
            linkedQuotationId != quotationId) {
          showMessage(
            'This vehicle already has another active pending service.',
          );
          return;
        }

        await supabase.from('pending_services').update({
          'quotation_id': quotationId,
          'customer_id':
          activePending['customer_id'] ??
              customerId,
          'booking_id':
          activePending['booking_id'] ??
              bookingId,
          'note':
          quotation['problem_description'] ??
              activePending['note'] ??
              'Vehicle arrived for confirmed quotation.',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq(
          'pending_id',
          activePending['pending_id'],
        );
      } else {
        await supabase.from('pending_services').insert({
          'vehicle_id': vehicleId,
          'customer_id': customerId,
          'booking_id': bookingId,
          'quotation_id': quotationId,
          'service_type':
          bookingId == null
              ? 'Walk-in'
              : 'Appointment',
          'status': 'Waiting Fix',
          'note':
          quotation['problem_description'] ??
              'Vehicle arrived for confirmed quotation.',
          'created_at':
          DateTime.now().toIso8601String(),
          'updated_at':
          DateTime.now().toIso8601String(),
        });
      }

      final updatedQuotation = await supabase
          .from('quotations')
          .update({
        'is_arrived': true,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq(
        'quotation_id',
        quotationId,
      )
          .eq(
        'status',
        'Confirmed',
      )
          .select('quotation_id')
          .maybeSingle();

      if (updatedQuotation == null) {
        showMessage(
          'Quotation status has changed. Please refresh the page.',
        );
        await loadData();
        return;
      }

      if (bookingId != null) {
        await supabase.from('bookings').update({
          'status': 'Arrived',
        }).eq(
          'booking_id',
          bookingId,
        ).neq(
          'status',
          'Completed',
        ).neq(
          'status',
          'Cancelled',
        );
      }

      if (customerId != null) {
        final vehicle = quotation['vehicles'] ?? {};
        final plate =
            vehicle['plate_number']?.toString() ??
                'your vehicle';

        const title = 'Vehicle Arrived';
        final message =
            'Your vehicle $plate has arrived at the workshop and is waiting for service.';

        await supabase.from('notifications').insert({
          'customer_id': customerId,
          'vehicle_id': vehicleId,
          'booking_id': bookingId,
          'quotation_id': quotationId,
          'title': title,
          'message': message,
          'notification_type': 'service',
          'target_page': 'my_bookings',
          'is_read': false,
        });

        await sendQuotationNotification(
          customerId: customerId.toString(),
          title: title,
          message: message,
          data: {
            'notification_type': 'service',
            'target_page': 'my_bookings',
            'vehicle_id': vehicleId,
            'booking_id': bookingId,
            'quotation_id': quotationId,
          },
        );
      }

      await loadData();

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Confirmed';
      });

      showMessage(
        'Vehicle marked as arrived and added to Pending Services.',
      );
    } catch (error) {
      showMessage(
        'Failed to mark vehicle as arrived: $error',
      );
    }
  }

  Future<void> sendQuotation(String quotationId) async {
    try {
      final quotation = await supabase
          .from('quotations')
          .select('''
          *,
          vehicles(plate_number)
        ''')
          .eq(
        'quotation_id',
        quotationId,
      )
          .maybeSingle();

      if (quotation == null) {
        showMessage('Quotation was not found.');
        return;
      }

      if (quotation['status'] != 'Draft') {
        showMessage(
          'Only a draft quotation can be sent.',
        );
        await loadData();
        return;
      }

      final customerId = quotation['customer_id'];

      if (customerId == null) {
        showMessage(
          'This quotation does not have a customer.',
        );
        return;
      }

      final updatedQuotation = await supabase
          .from('quotations')
          .update({
        'status': 'Sent',
        'is_sent': true,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq(
        'quotation_id',
        quotationId,
      )
          .eq(
        'status',
        'Draft',
      )
          .select('quotation_id')
          .maybeSingle();

      if (updatedQuotation == null) {
        showMessage(
          'This quotation has already been processed.',
        );
        await loadData();
        return;
      }

      await supabase.from('pending_services').update({
        'note':
        'Quotation sent and waiting for customer confirmation.',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq(
        'quotation_id',
        quotationId,
      );

      final plate =
          quotation['vehicles']?['plate_number'] ??
              'your vehicle';

      const title = 'Quotation Available';
      final message =
          'A new quotation is available for $plate. Please review it.';

      await supabase.from('notifications').insert({
        'customer_id': customerId,
        'vehicle_id': quotation['vehicle_id'],
        'booking_id': quotation['booking_id'],
        'quotation_id': quotationId,
        'title': title,
        'message': message,
        'notification_type': 'quotation',
        'target_page': 'customer_quotations',
        'is_read': false,
      });

      await sendQuotationNotification(
        customerId: customerId.toString(),
        title: title,
        message: message,
        data: {
          'notification_type': 'quotation',
          'target_page': 'customer_quotations',
          'vehicle_id': quotation['vehicle_id'],
          'booking_id': quotation['booking_id'],
          'quotation_id': quotationId,
        },
      );

      await loadData();

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Sent';
      });

      showMessage('Quotation sent to customer.');
    } catch (error) {
      showMessage(
        'Failed to send quotation: $error',
      );
    }
  }

  Future<void> cancelQuotation(
      String quotationId,
      ) async {
    try {
      final quotation = await supabase
          .from('quotations')
          .select('''
          *,
          vehicles(plate_number)
        ''')
          .eq(
        'quotation_id',
        quotationId,
      )
          .maybeSingle();

      if (quotation == null) {
        showMessage('Quotation was not found.');
        return;
      }

      if (quotation['status'] != 'Sent') {
        showMessage(
          'Only a sent quotation can be cancelled.',
        );
        await loadData();
        return;
      }

      final updatedQuotation = await supabase
          .from('quotations')
          .update({
        'status': 'Cancelled',
        'is_sent': false,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq(
        'quotation_id',
        quotationId,
      )
          .eq(
        'status',
        'Sent',
      )
          .select('quotation_id')
          .maybeSingle();

      if (updatedQuotation == null) {
        showMessage(
          'This quotation has already been processed.',
        );
        await loadData();
        return;
      }

      await supabase.from('pending_services').update({
        'quotation_id': null,
        'status': 'Waiting Fix',
        'note':
        'Quotation cancelled. A replacement quotation can be created.',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq(
        'quotation_id',
        quotationId,
      );

      final customerId = quotation['customer_id'];

      if (customerId != null) {
        final plate =
            quotation['vehicles']?['plate_number'] ??
                'your vehicle';

        const title = 'Quotation Cancelled';
        final message =
            'The workshop cancelled the quotation for $plate. A new quotation may be prepared.';

        await supabase.from('notifications').insert({
          'customer_id': customerId,
          'vehicle_id': quotation['vehicle_id'],
          'booking_id': quotation['booking_id'],
          'quotation_id': quotationId,
          'title': title,
          'message': message,
          'notification_type': 'quotation',
          'target_page': 'customer_quotations',
          'is_read': false,
        });

        await sendQuotationNotification(
          customerId: customerId.toString(),
          title: title,
          message: message,
          data: {
            'notification_type': 'quotation',
            'target_page': 'customer_quotations',
            'vehicle_id': quotation['vehicle_id'],
            'booking_id': quotation['booking_id'],
            'quotation_id': quotationId,
          },
        );
      }

      await loadData();

      if (!mounted) return;

      setState(() {
        selectedStatus = 'Cancelled';
      });

      showMessage('Quotation cancelled.');
    } catch (error) {
      showMessage(
        'Failed to cancel quotation: $error',
      );
    }
  }

  Future<void> deleteQuotation(
      String quotationId,
      ) async {
    try {
      final quotation = await supabase
          .from('quotations')
          .select('quotation_id, status')
          .eq(
        'quotation_id',
        quotationId,
      )
          .maybeSingle();

      if (quotation == null) {
        showMessage('Quotation was not found.');
        return;
      }

      if (quotation['status'] != 'Draft') {
        showMessage(
          'Only a draft quotation can be deleted.',
        );
        await loadData();
        return;
      }

      await supabase.from('pending_services').update({
        'quotation_id': null,
        'status': 'Waiting Fix',
        'note':
        'Quotation draft deleted. A new quotation can be created.',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq(
        'quotation_id',
        quotationId,
      );

      final deletedQuotation = await supabase
          .from('quotations')
          .delete()
          .eq(
        'quotation_id',
        quotationId,
      )
          .eq(
        'status',
        'Draft',
      )
          .select('quotation_id')
          .maybeSingle();

      if (deletedQuotation == null) {
        showMessage(
          'This quotation could not be deleted.',
        );
        await loadData();
        return;
      }

      await loadData();

      showMessage(
        'Quotation deleted successfully.',
      );
    } catch (error) {
      showMessage(
        'Failed to delete quotation: $error',
      );
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget buildStatusButton(String status) {
    final isSelected = selectedStatus == status;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => selectedStatus = status);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 46,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF339BFF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isSelected ? 0.10 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              status,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF339BFF),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
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
          height: 40,
          child: OutlinedButton.icon(
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

  Widget buildQuotationCard(Map<String, dynamic> quotation) {
    final status = quotation['status'] ?? 'Draft';
    final isArrived = quotation['is_arrived'] == true;
    final vehicle = quotation['vehicles'] ?? {};
    final customer = quotation['customers'] ?? {};
    final items = quotation['quotation_items'] as List? ?? [];
    final total =
        double.tryParse(quotation['total'].toString()) ?? calculateTotal(items);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
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
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 27,
                    backgroundColor: Color(0xFFD7E5FA),
                    child: Icon(
                      Icons.receipt_long,
                      color: Color(0xFF339BFF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Customer: ${displayCustomer(customer['name'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Items: ${items.length}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Arrival: ${isArrived ? 'Arrived' : 'Not Arrived'}',
                          style: TextStyle(
                            color: isArrived ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'RM ${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF339BFF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: getStatusBackgroundColor(status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              if (status == 'Draft') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    buildCardActionButton(
                      icon: Icons.edit,
                      label: 'Edit',
                      outlined: true,
                      onPressed: () {
                        showEditQuotationDialog(quotation);
                      },
                    ),
                    const SizedBox(width: 8),
                    buildCardActionButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      outlined: true,
                      foregroundColor: Colors.red,
                      onPressed: () {
                        showDeleteQuotationDialog(quotation['quotation_id']);
                      },
                    ),
                    const SizedBox(width: 8),
                    buildCardActionButton(
                      icon: Icons.send,
                      label: 'Send',
                      onPressed: () {
                        showSendQuotationDialog(quotation['quotation_id']);
                      },
                    ),
                  ],
                ),
              ],
              if (status == 'Sent') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    buildCardActionButton(
                      icon: Icons.cancel_outlined,
                      label: 'Cancel Quotation',
                      outlined: true,
                      foregroundColor: Colors.red,
                      onPressed: () {
                        showCancelQuotationDialog(
                          quotation['quotation_id'],
                        );
                      },
                    ),
                  ],
                ),
              ],

              if (status == 'Confirmed') ...[
                const SizedBox(height: 14),

                if (!isArrived)
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: () {
                        showMarkArrivedDialog(quotation);
                      },
                      icon: const Icon(
                        Icons.login,
                        size: 18,
                      ),
                      label: const Text(
                        'Mark Arrived',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.green.shade200,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 18,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Arrived — Added to Pending Services',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
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

  Widget buildDetailRow(String title, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void showQuotationDetailDialog(Map<String, dynamic> quotation) {
    final vehicle = quotation['vehicles'] ?? {};
    final customer = quotation['customers'] ?? {};
    final status = quotation['status'] ?? 'Draft';
    final isArrived = quotation['is_arrived'] == true;
    final items = quotation['quotation_items'] as List? ?? [];
    final total =
        double.tryParse(quotation['total'].toString()) ?? calculateTotal(items);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 35),
          title: const Text(
            'Quotation Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildDetailRow('Customer', displayCustomer(customer['name'])),
                  buildDetailRow('Phone', displayCustomer(customer['phone'])),
                  buildDetailRow(
                    'Vehicle',
                    '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
                  ),
                  buildDetailRow(
                    'Problem',
                    quotation['problem_description'] ?? 'No description',
                  ),
                  buildDetailRow('Status', status),
                  buildDetailRow(
                    'Arrival',
                    isArrived ? 'Arrived' : 'Not Arrived',
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Quotation Items',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    const Text('No items found.')
                  else
                    ...items.map((item) {
                      final qty =
                          int.tryParse(item['quantity'].toString()) ?? 1;
                      final price =
                          double.tryParse(item['price'].toString()) ?? 0;
                      final subtotal = qty * price;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item['item_name']}\nQty: $qty x RM ${price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              'RM ${subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
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
            'Confirm that vehicle $plate has physically arrived at the workshop?\n\n'
                'It will be added to Pending Services.',
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
                                      fontSize: 10,
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
        title: const Text('Quotation Management'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: () {
              AdminSidebar.show(context);
            },
            icon: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Color(0xFF339BFF)),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => loadData(),
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
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
                      style: TextStyle(color: Colors.white70, fontSize: 14),
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
                        setState(() => searchText = value);
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by plate, model, or customer',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverPersistentHeader(
              pinned: true,
              delegate: _QuotationStatusHeaderDelegate(
                child: Container(
                  color: const Color(0xFFD7E5FA),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            if (isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (displayQuotations.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No $selectedStatus quotations found.',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildQuotationCard(displayQuotations[index]);
                    },
                    childCount: displayQuotations.length,
                  ),
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
              heroTag: 'customerBackToTop',
              backgroundColor: const Color(0xFF339BFF),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up),
            ),
          if (showBackToTop) const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'createQuotation',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: showCreateQuotationDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Quotation'),
          ),
        ],
      ),
    );
  }
}

class _QuotationStatusHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _QuotationStatusHeaderDelegate({
    required this.child,
  });

  @override
  double get minExtent => 70;

  @override
  double get maxExtent => 70;

  @override
  Widget build(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
      ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _QuotationStatusHeaderDelegate oldDelegate) {
    return true;
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