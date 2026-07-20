import 'package:flutter/material.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import 'admin_quotations_page.dart';

class PendingServicePage extends StatefulWidget {
  const PendingServicePage({super.key});

  @override
  State<PendingServicePage> createState() => _PendingServicePageState();
}

class _PendingServicePageState extends State<PendingServicePage> {
  String searchText = '';
  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  List<Map<String, dynamic>> pendingServices = [];

  final List<String> statusList = [
    'Waiting Fix',
    'In Progress',
    'Completed',
  ];

  @override
  void initState() {
    super.initState();

    fetchPendingServices();

    scrollController.addListener(() {
      if (scrollController.offset > 350 && !showBackToTop) {
        setState(() => showBackToTop = true);
      } else if (scrollController.offset <= 350 && showBackToTop) {
        setState(() => showBackToTop = false);
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

  Future<void> openCreateQuotation(
      Map<String, dynamic> service,
      ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminQuotationsPage(
          initialPendingService: service,
        ),
      ),
    );

    if (!mounted) return;

    await fetchPendingServices();
  }

  Future<void> fetchPendingServices() async {
    setState(() => isLoading = true);

    try {
      final response = await supabase.from('pending_services').select('''
  *,
  vehicles(plate_number, car_model),
  customers(name, phone, email, fcm_token),
  quotations(
    quotation_id,
    status,
    problem_description,
    total,
    quotation_items(
      item_id,
      item_name,
      quantity,
      price
    )
  )
''').order('created_at', ascending: false);

      pendingServices = List<Map<String, dynamic>>.from(response);
    } catch (error) {
      showMessage('Failed to load pending services: $error');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  List<Map<String, dynamic>> get filteredCars {
    return pendingServices.where((service) {
      final vehicle = service['vehicles'] ?? {};
      final plate = (vehicle['plate_number'] ?? '').toString().toLowerCase();
      final model = (vehicle['car_model'] ?? '').toString().toLowerCase();
      final customer =
      (service['customers']?['name'] ?? '').toString().toLowerCase();
      final search = searchText.toLowerCase();

      return plate.contains(search) ||
          model.contains(search) ||
          customer.contains(search);
    }).toList();
  }

  int getCompletedCount() {
    return pendingServices.where((service) {
      return service['status'] == 'Completed';
    }).length;
  }

  int getInProgressCount() {
    return pendingServices.where((service) {
      final status = service['status'];

      return status == 'Waiting Fix' ||
          status == 'In Progress';
    }).length;
  }

  Color getStatusColor(String status) {
    if (status == 'Completed') return Colors.green;
    if (status == 'In Progress') return Colors.blue;
    if (status == 'Waiting Fix') return Colors.orange;
    return Colors.grey;
  }

  Color getStatusBackgroundColor(String status) {
    if (status == 'Completed') return Colors.green.shade50;
    if (status == 'In Progress') return Colors.blue.shade50;
    if (status == 'Waiting Fix') return Colors.orange.shade50;
    return Colors.grey.shade100;
  }

  String getNotificationMessage(String status, String plate) {
    if (status == 'Waiting Fix') {
      return 'Your vehicle $plate is waiting for inspection and repair.';
    }

    if (status == 'In Progress') {
      return 'Your vehicle $plate is currently being serviced.';
    }

    if (status == 'Completed') {
      return 'Your vehicle $plate service has been completed.';
    }

    return 'Your vehicle $plate service status has been updated.';
  }

  Future<void> sendFcmPushNotification({
    required String customerId,
    required String title,
    required String message,
  }) async {
    try {
      final customer = await supabase
          .from('customers')
          .select('fcm_token')
          .eq('customer_id', customerId)
          .maybeSingle();

      final token = customer?['fcm_token']?.toString();

      if (token == null || token.isEmpty) {
        debugPrint('No FCM token found for customer $customerId');
        return;
      }

      final response = await supabase.functions.invoke(
        'send-fcm',
        body: {
          'token': token,
          'title': title,
          'body': message,
        },
      );

      debugPrint('FCM response: ${response.data}');
    } catch (error) {
      debugPrint('Failed to send FCM notification: $error');
    }
  }
  Future<bool> serviceRecordAlreadyExists(String quotationId) async {
    final response = await supabase
        .from('service_records')
        .select('record_id')
        .eq('quotation_id', quotationId)
        .maybeSingle();

    return response != null;
  }
  double calculateItemsTotal(List items) {
    double total = 0;

    for (final item in items) {
      final quantity = int.tryParse(item['quantity'].toString()) ?? 1;
      final price = double.tryParse(item['price'].toString()) ?? 0;

      total += quantity * price;
    }

    return total;
  }
  Future<bool> createAutomaticServiceRecord(
      Map<String, dynamic> service,
      ) async {
    final quotationId = service['quotation_id']?.toString();

    // No quotation means this may be a walk-in service.
    // Keep it for manual service-record creation.
    if (quotationId == null || quotationId.isEmpty) {
      return false;
    }

    final quotation = service['quotations'];

    if (quotation == null) {
      throw Exception('Linked quotation was not found.');
    }

    if (quotation['status'] != 'Confirmed') {
      throw Exception(
        'The quotation must be confirmed before completing the service.',
      );
    }

    final exists = await serviceRecordAlreadyExists(quotationId);

    if (exists) {
      throw Exception(
        'A service record already exists for this quotation.',
      );
    }

    final quotationItems =
        quotation['quotation_items'] as List? ?? [];

    if (quotationItems.isEmpty) {
      throw Exception(
        'The confirmed quotation does not contain any items.',
      );
    }

    final total = calculateItemsTotal(quotationItems);

    final record = await supabase.from('service_records').insert({
      'vehicle_id': service['vehicle_id'],
      'customer_id': service['customer_id'],
      'quotation_id': quotationId,
      'booking_id': service['booking_id'],
      'problem_description':
      quotation['problem_description'] ?? service['note'],
      'service_action':
      'Service completed according to the confirmed quotation.',
      'total_price': total,
      'status': 'Completed',
    }).select().single();

    for (final item in quotationItems) {
      await supabase.from('service_record_items').insert({
        'record_id': record['record_id'],
        'item_name': item['item_name'],
        'quantity':
        int.tryParse(item['quantity'].toString()) ?? 1,
        'price':
        double.tryParse(item['price'].toString()) ?? 0,
      });
    }

    return true;
  }
  Future<void> updatePendingStatus(
      Map<String, dynamic> service,
      String newStatus,
      ) async {
    try {
      final vehicle = service['vehicles'] ?? {};
      final plate = vehicle['plate_number'] ?? 'your vehicle';
      final customerId = service['customer_id'];

      final title = newStatus == 'Completed'
          ? 'Vehicle Service Completed'
          : 'Vehicle Status Updated';

      final message = getNotificationMessage(newStatus, plate);

      bool automaticRecordCreated = false;

      if (newStatus == 'Completed') {
        automaticRecordCreated =
        await createAutomaticServiceRecord(service);
      }

      if (service['booking_id'] != null &&
          newStatus == 'Completed') {
        await supabase.from('bookings').update({
          'status': 'Completed',
        }).eq(
          'booking_id',
          service['booking_id'],
        );
      }

      if (automaticRecordCreated) {
        await supabase
            .from('pending_services')
            .delete()
            .eq(
          'pending_id',
          service['pending_id'],
        );
      } else {
        await supabase.from('pending_services').update({
          'status': newStatus,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq(
          'pending_id',
          service['pending_id'],
        );
      }

      if (customerId != null) {
        await supabase.from('notifications').insert({
          'customer_id': customerId,
          'vehicle_id': service['vehicle_id'],
          'booking_id': service['booking_id'],
          'quotation_id': service['quotation_id'],
          'pending_id':
          automaticRecordCreated ? null : service['pending_id'],
          'title': automaticRecordCreated
              ? 'Service Record Available'
              : title,
          'message': automaticRecordCreated
              ? 'The service for vehicle $plate has been completed. Your service record is now available.'
              : message,
          'is_read': false,
        });

        await sendFcmPushNotification(
          customerId: customerId,
          title: automaticRecordCreated
              ? 'Service Record Available'
              : title,
          message: automaticRecordCreated
              ? 'The service for vehicle $plate has been completed. Your service record is now available.'
              : message,
        );
      }

      await fetchPendingServices();

      if (automaticRecordCreated) {
        showMessage(
          'Service completed and service record created automatically.',
        );
      } else if (newStatus == 'Completed') {
        showMessage(
          'Walk-in service completed. Create the service record manually from Service Records.',
        );
      } else {
        showMessage('Service status updated to $newStatus.');
      }
    } catch (error) {
      showMessage('Failed to update status: $error');
    }
  }

  Future<void> deletePendingService(String pendingId) async {
    try {
      await supabase
          .from('pending_services')
          .delete()
          .eq('pending_id', pendingId);

      await fetchPendingServices();

      showMessage('Pending service deleted successfully.');
    } catch (error) {
      showMessage('Failed to delete pending service: $error');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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

  Widget buildPendingDetailRow(
      String title,
      String value,
      ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Not Provided' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showPendingServiceDetailDialog(
      Map<String, dynamic> service,
      ) {
    final vehicle = service['vehicles'] ?? {};
    final customer = service['customers'] ?? {};
    final quotation = service['quotations'];

    final items =
        quotation?['quotation_items'] as List? ?? [];

    final total = quotation == null
        ? 0.0
        : double.tryParse(
      quotation['total']?.toString() ?? '',
    ) ??
        calculateItemsTotal(items);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 30,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Pending Service Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildPendingDetailRow(
                    'Plate Number',
                    vehicle['plate_number']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Car Model',
                    vehicle['car_model']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Customer',
                    customer['name']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Phone',
                    customer['phone']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Service Type',
                    service['service_type']?.toString() ??
                        'Walk-in',
                  ),
                  buildPendingDetailRow(
                    'Service Status',
                    service['status']?.toString() ??
                        'Waiting Fix',
                  ),
                  buildPendingDetailRow(
                    'Problem',
                    quotation?['problem_description']
                        ?.toString() ??
                        service['note']?.toString() ??
                        'No description',
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Quotation Information',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (quotation == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'No quotation is linked to this service.',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else ...[
                    buildPendingDetailRow(
                      'Quotation Status',
                      quotation['status']?.toString() ?? '',
                    ),
                    buildPendingDetailRow(
                      'Quotation Total',
                      'RM ${total.toStringAsFixed(2)}',
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Quotation Items',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (items.isEmpty)
                      const Text('No quotation items found.')
                    else
                      ...items.map((item) {
                        final quantity = int.tryParse(
                          item['quantity'].toString(),
                        ) ??
                            1;

                        final price = double.tryParse(
                          item['price'].toString(),
                        ) ??
                            0;

                        final subtotal = quantity * price;

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
                                  '${item['item_name'] ?? 'Item'}\n'
                                      'Qty: $quantity × RM ${price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                'RM ${subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFF339BFF),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
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

  Widget buildPendingServiceCard(Map<String, dynamic> service) {
    final vehicle = service['vehicles'] ?? {};
    final customer = service['customers'] ?? {};
    final quotation = service['quotations'];

    final status = service['status'] ?? 'Waiting Fix';

    final plate = vehicle['plate_number'] ?? '';
    final model = vehicle['car_model'] ?? '';
    final customerName = customer['name'] ?? 'Not Provided';
    final type = service['service_type'] ?? 'Walk-in';

    final quotationId = service['quotation_id'];
    final hasQuotation = quotationId != null;
    final isCompleted = status == 'Completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          showPendingServiceDetailDialog(service);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Color(0xFFD7E5FA),
                    child: Icon(
                      Icons.car_repair,
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
                          '$plate - $model',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Customer: $customerName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Type: $type',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasQuotation
                              ? 'Quotation: ${quotation?['status'] ?? 'Linked'}'
                              : 'Quotation: Not Created',
                          style: TextStyle(
                            color: hasQuotation
                                ? Colors.purple
                                : Colors.orange,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      showDeletePendingServiceDialog(
                        service['pending_id'],
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                value: status,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Service Status',
                  floatingLabelBehavior:
                  FloatingLabelBehavior.always,
                  prefixIcon: const Icon(Icons.update),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: statusList.map((itemStatus) {
                  return DropdownMenuItem(
                    value: itemStatus,
                    child: Text(itemStatus),
                  );
                }).toList(),
                onChanged: (value) async {
                  if (value == null || value == status) return;

                  await updatePendingStatus(service, value);
                },
              ),

              const SizedBox(height: 12),

              Row(
                children: [
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
                  const Spacer(),
                  if (!hasQuotation && !isCompleted)
                    ElevatedButton.icon(
                      onPressed: () {
                        openCreateQuotation(service);
                      },
                      icon: const Icon(
                        Icons.receipt_long,
                        size: 17,
                      ),
                      label: const Text('Create Quotation'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(0xFF339BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  else if (hasQuotation)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            color: Colors.purple,
                            size: 17,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Quotation Linked',
                            style: TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
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
    );
  }

  void showDeletePendingServiceDialog(String pendingId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Pending Service'),
          content: const Text(
            'Are you sure you want to delete this pending service record?',
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
                await deletePendingService(pendingId);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayCars = filteredCars;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Pending Services'),
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: fetchPendingServices,
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
                      'Pending Service Queue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Track vehicle service progress and notify customers',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.car_repair,
                          title: 'In Progress',
                          value: '${getInProgressCount()}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.check_circle,
                          title: 'Completed',
                          value: '${getCompletedCount()}',
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
                        hintText: 'Search by plate, model or customer',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
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
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (displayCars.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No pending service found.',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildPendingServiceCard(displayCars[index]);
                    },
                    childCount: displayCars.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        onPressed: scrollToTop,
        child: const Icon(Icons.keyboard_arrow_up),
      )
          : null,
    );
  }
}