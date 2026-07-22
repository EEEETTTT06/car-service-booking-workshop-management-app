import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';

class CustomerQuotationPage extends StatefulWidget {
  const CustomerQuotationPage({super.key});

  @override
  State<CustomerQuotationPage> createState() => _CustomerQuotationPageState();
}

class _CustomerQuotationPageState extends State<CustomerQuotationPage> {
  String selectedStatus = 'Sent';
  String searchText = '';
  bool isLoading = false;
  bool isUpdatingQuotation = false;

  final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  bool showBackToTop = false;
  Map<String, dynamic>? currentCustomer;
  List<Map<String, dynamic>> quotations = [];
  RealtimeChannel? quotationRealtimeChannel;
  bool isRealtimeRefreshing = false;
  @override
  void initState() {
    super.initState();

    loadQuotations();

    scrollController.addListener(() {
      if (!mounted) return;

      final shouldShow =
          scrollController.hasClients &&
              scrollController.offset > 180;

      if (shouldShow != showBackToTop) {
        setState(() {
          showBackToTop = shouldShow;
        });
      }
    });
  }

  @override
  void dispose() {
    final channel = quotationRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    scrollController.dispose();
    searchController.dispose();
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

  Future<void> loadQuotations() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await fetchQuotations();
      setupRealtimeSubscription();
    } catch (error) {
      showMessage('Failed to load quotations: $error');
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

  Future<void> fetchQuotations() async {
    if (currentCustomer == null) return;

    final response = await supabase.from('quotations').select('''
      *,
      vehicles(plate_number, car_model),
      quotation_items(item_id, item_name, quantity, price)
    ''')
        .eq('customer_id', currentCustomer!['customer_id'])
        .inFilter('status', ['Sent', 'Confirmed', 'Cancelled'])
        .order('created_at', ascending: false);

    quotations = List<Map<String, dynamic>>.from(response);
  }

  void setupRealtimeSubscription() {
    if (currentCustomer == null) return;

    // Avoid creating duplicate Realtime listeners.
    if (quotationRealtimeChannel != null) {
      return;
    }

    final customerId =
    currentCustomer!['customer_id'].toString();

    quotationRealtimeChannel = supabase
        .channel(
      'customer-quotations-$customerId',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        debugPrint(
          'Customer quotation changed: '
              '${payload.eventType}',
        );

        refreshQuotationsFromRealtime();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotation_items',
      callback: (payload) {
        debugPrint(
          'Quotation item changed: '
              '${payload.eventType}',
        );

        refreshQuotationsFromRealtime();
      },
    )
        .subscribe();
  }

  Future<void> refreshQuotationsFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await fetchQuotations();

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      debugPrint(
        'Realtime quotation refresh failed: $error',
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  List<Map<String, dynamic>> get filteredQuotations {
    return quotations.where((quotation) {
      final status = quotation['status'] ?? 'Sent';
      final vehicle = quotation['vehicles'] ?? {};

      final plate = (vehicle['plate_number'] ?? '').toString().toLowerCase();
      final model = (vehicle['car_model'] ?? '').toString().toLowerCase();
      final search = searchText.toLowerCase();

      return status == selectedStatus &&
          (plate.contains(search) || model.contains(search));
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
    if (status == 'Confirmed') return Colors.green;
    if (status == 'Cancelled') return Colors.red;
    return Colors.orange;
  }

  Color getStatusBackgroundColor(String status) {
    if (status == 'Confirmed') return Colors.green.shade50;
    if (status == 'Cancelled') return Colors.red.shade50;
    return Colors.orange.shade50;
  }

  Future<void> notifyAdminsQuotationDecision({
    required Map<String, dynamic> quotation,
    required String status,
  }) async {
    try {
      final vehicle = quotation['vehicles'] ?? {};
      final customerName = currentCustomer?['name'] ?? 'A customer';
      final plate = vehicle['plate_number'] ?? 'Unknown Vehicle';

      final title =
      status == 'Confirmed' ? 'Quotation Confirmed' : 'Quotation Rejected';

      final body = status == 'Confirmed'
          ? '$customerName confirmed the quotation for $plate.'
          : '$customerName rejected the quotation for $plate.';

      final admins = await supabase
          .from('admins')
          .select('admin_id, notification_enabled');

      for (final admin in admins) {
        await supabase.from('admin_notifications').insert({
          'admin_id': admin['admin_id'],
          'title': title,
          'message': body,
          'notification_type': 'quotation',
          'is_read': false,
        });
      }

      final enabledAdminIds = admins
          .where((admin) => admin['notification_enabled'] != false)
          .map((admin) => admin['admin_id'])
          .toList();

      if (enabledAdminIds.isEmpty) return;

      final tokens = await supabase
          .from('admin_fcm_tokens')
          .select('fcm_token, admin_id')
          .inFilter('admin_id', enabledAdminIds);

      for (final row in tokens) {
        final token = row['fcm_token'];
        if (token == null || token.toString().isEmpty) continue;

        await supabase.functions.invoke(
          'send-fcm',
          body: {'token': token, 'title': title, 'body': body},
        );
      }
    } catch (error) {
      debugPrint('Quotation notify admin error: $error');
    }
  }

  Future<void> updateQuotationStatus({
    required Map<String, dynamic> quotation,
    required String status,
  }) async {
    if (isUpdatingQuotation) return;

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

    if (status != 'Confirmed' &&
        status != 'Cancelled') {
      showMessage(
        'The quotation decision is invalid.',
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      isUpdatingQuotation = true;
    });

    try {
      /*
     * The RPC validates the logged-in customer,
     * quotation ownership and quotation status.
     *
     * Quotation and Pending Service changes are
     * completed in one database transaction.
     */
      final rpcResult = await supabase.rpc(
        'customer_decide_quotation',
        params: {
          'p_quotation_id': quotationId,
          'p_decision': status,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid quotation decision information was returned.',
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

      final returnedStatus =
      result['status']
          ?.toString();

      final plateValue =
      result['plate_number']
          ?.toString()
          .trim();

      final plate =
      plateValue == null ||
          plateValue.isEmpty
          ? 'your vehicle'
          : plateValue;

      if (returnedQuotationId == null ||
          returnedQuotationId.isEmpty) {
        throw Exception(
          'Quotation ID was not returned.',
        );
      }

      if (returnedStatus != status) {
        throw Exception(
          'The quotation decision was not completed correctly.',
        );
      }

      /*
     * Notifications run after the transaction.
     * Notification failure will not undo the
     * customer's quotation decision.
     */
      try {
        if (status == 'Cancelled' &&
            customerId != null &&
            customerId.isNotEmpty) {
          await supabase
              .from('notifications')
              .insert({
            'customer_id': customerId,
            'vehicle_id': vehicleId,
            'booking_id': bookingId,
            'quotation_id':
            returnedQuotationId,
            'title':
            'Quotation Rejected',
            'message':
            'You rejected the quotation for $plate. The workshop will not proceed with this quotation.',
            'notification_type':
            'quotation',
            'target_page':
            'customer_quotations',
            'is_read': false,
          });
        }

        /*
       * Existing method creates Admin notification
       * history and sends FCM to all Admin devices.
       */
        await notifyAdminsQuotationDecision(
          quotation: quotation,
          status: status,
        );
      } catch (
      notificationError,
      stackTrace
      ) {
        debugPrint(
          'Quotation decision notification failed: '
              '$notificationError',
        );

        debugPrint(
          stackTrace.toString(),
        );
      }

      await loadQuotations();

      if (!mounted) return;

      setState(() {
        selectedStatus = status;
      });

      showMessage(
        status == 'Confirmed'
            ? 'Quotation confirmed. Please bring your vehicle to the workshop when ready.'
            : 'Quotation rejected. The workshop may prepare a new quotation if necessary.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await loadQuotations();
    } catch (error, stackTrace) {
      debugPrint(
        'Update quotation error: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to update quotation: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isUpdatingQuotation = false;
        });
      }
    }
  }

  void showDecisionConfirmDialog({
    required Map<String, dynamic> quotation,
    required String status,
  }) {
    final vehicle = quotation['vehicles'] ?? {};
    final plate = vehicle['plate_number'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            status == 'Confirmed' ? 'Confirm Quotation' : 'Reject Quotation',
          ),
          content: Text(
            status == 'Confirmed'
                ? 'Are you sure you want to confirm this quotation for $plate?\n\n'
                'Confirming the quotation does not mean the vehicle has arrived. '
                'The workshop will mark it as arrived when you bring the vehicle in.'
                : 'Are you sure you want to reject this quotation for $plate? '
                'The workshop will stop this quotation process.',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                status == 'Confirmed' ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await updateQuotationStatus(
                  quotation: quotation,
                  status: status,
                );
              },
              child: Text(
                status == 'Confirmed' ? 'Yes, Confirm' : 'Yes, Reject',
              ),
            ),
          ],
        );
      },
    );
  }

  void showQuotationDetailDialog(Map<String, dynamic> quotation) {
    final vehicle = quotation['vehicles'] ?? {};
    final items = quotation['quotation_items'] as List? ?? [];
    final status = quotation['status'] ?? 'Sent';
    final isArrived = quotation['is_arrived'] == true;

    final total =
        double.tryParse(quotation['total'].toString()) ?? calculateTotal(items);

    final isSent = status == 'Sent';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Quotation Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildDetailBox('Plate Number', vehicle['plate_number'] ?? ''),
                  buildDetailBox('Car Model', vehicle['car_model'] ?? ''),
                  buildDetailBox(
                    'Problem',
                    quotation['problem_description'] ?? 'No description',
                  ),
                  buildDetailBox('Status', status),

                  if (status == 'Confirmed')
                    buildDetailBox(
                      'Vehicle Arrival',
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
                              style:
                              const TextStyle(fontWeight: FontWeight.bold),
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isSent) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Please review the quotation carefully before making your decision.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (isSent)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  showDecisionConfirmDialog(
                    quotation: quotation,
                    status: 'Cancelled',
                  );
                },
                child: const Text(
                  'Reject',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            if (isSent)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  showDecisionConfirmDialog(
                    quotation: quotation,
                    status: 'Confirmed',
                  );
                },
                child: const Text('Confirm'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget buildDetailBox(String title, String value) {
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
              value.isEmpty ? 'Not Provided' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStatusButton(String status) {
    final isSelected = selectedStatus == status;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (selectedStatus == status) return;

          setState(() {
            selectedStatus = status;
          });

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 45,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF339BFF)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              status,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : const Color(0xFF339BFF),
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
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildQuotationCard(Map<String, dynamic> quotation) {
    final vehicle = quotation['vehicles'] ?? {};
    final items = quotation['quotation_items'] as List? ?? [];
    final status = quotation['status'] ?? 'Sent';
    final isArrived = quotation['is_arrived'] == true;
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
        onTap: () => showQuotationDetailDialog(quotation),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
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
                    const SizedBox(height: 6),
                    Text(
                      'Problem: ${quotation['problem_description'] ?? 'No description'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                      const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF339BFF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                    if (status == 'Confirmed') ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isArrived
                                ? Icons.check_circle
                                : Icons.schedule,
                            color: isArrived
                                ? Colors.green
                                : Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isArrived
                                ? 'Vehicle Arrived'
                                : 'Vehicle Not Arrived',
                            style: TextStyle(
                              color: isArrived
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 15,
                color: Colors.black38,
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    final displayQuotations = filteredQuotations;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('My Quotations'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: const [
          NotificationBell(
            isAdmin: false,
          ),
        ],
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: loadQuotations,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
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
                    bottomLeft: Radius.circular(26),
                    bottomRight: Radius.circular(26),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quotation List',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Review workshop quotations and make your decision',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.pending_actions,
                          title: 'Waiting',
                          value: '${getStatusCount('Sent')}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.check_circle,
                          title: 'Confirmed',
                          value: '${getStatusCount('Confirmed')}',
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: searchController,
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText:
                        'Search by plate number or car model',
                        prefixIcon: const Icon(Icons.search),

                        suffixIcon: searchText.isNotEmpty
                            ? IconButton(
                          onPressed: () {
                            searchController.clear();

                            setState(() {
                              searchText = '';
                            });
                          },
                          icon: const Icon(
                            Icons.clear,
                          ),
                        )
                            : null,

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
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  8,
                ),
                child: Row(
                  children: [
                    buildStatusButton('Sent'),
                    const SizedBox(width: 8),
                    buildStatusButton('Confirmed'),
                    const SizedBox(width: 8),
                    buildStatusButton('Cancelled'),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 8),
            ),

            if (displayQuotations.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No $selectedStatus quotations found.',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
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
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildQuotationCard(
                        displayQuotations[index],
                      );
                    },
                    childCount: displayQuotations.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton.small(
        heroTag: 'customerQuotationBackToTop',
        backgroundColor: const Color(0xFF339BFF),
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