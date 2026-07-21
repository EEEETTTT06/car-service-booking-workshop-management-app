import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../../services/pdf_service.dart';
import '../../services/customer_notification_service.dart';

class AdminRecordsPage extends StatefulWidget {
  const AdminRecordsPage({super.key});

  @override
  State<AdminRecordsPage> createState() => _AdminRecordsPageState();
}

class _AdminRecordsPageState extends State<AdminRecordsPage> {
  bool isLoading = false;
  bool isSavingRecord = false;
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  final TextEditingController searchController = TextEditingController();

  String selectedModel = 'All Car Model';

  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> completedPendingServices = [];
  RealtimeChannel? serviceRecordsRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    loadData();
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
        serviceRecordsRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    searchController.dispose();
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
      await fetchCompletedPendingServices();
      await fetchRecords();

      // Prevent DropdownButton error when a car model
      // is no longer available after Realtime refresh.
      if (!carModels.contains(selectedModel)) {
        selectedModel = 'All Car Model';
      }

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load records: $error',
        );
      } else {
        debugPrint(
          'Realtime service record refresh failed: $error',
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

  Future<void> fetchCompletedPendingServices() async {
    final response = await supabase.from('pending_services').select('''
      *,
      customers(name, phone, email),
      vehicles(plate_number, car_model),
      quotations(
        quotation_id,
        problem_description,
        total,
        quotation_items(item_id, item_name, quantity, price)
      )
    ''')
        .eq('status', 'Completed')
        .order('updated_at', ascending: false);

    completedPendingServices = List<Map<String, dynamic>>.from(response);
  }

  Future<void> fetchRecords() async {
    final response = await supabase.from('service_records').select('''
      *,
      customers(name, phone, email),
      vehicles(plate_number, car_model),
      service_record_items(item_id, item_name, quantity, price)
    ''').order('created_at', ascending: false);

    records = List<Map<String, dynamic>>.from(response);
  }

  void setupRealtimeSubscription() {
    if (serviceRecordsRealtimeChannel != null) {
      return;
    }

    serviceRecordsRealtimeChannel = supabase
        .channel(
      'admin-service-records-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'service_records',
      callback: (payload) {
        scheduleRealtimeRefresh(
          'Service record',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'service_record_items',
      callback: (payload) {
        scheduleRealtimeRefresh(
          'Service record item',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'pending_services',
      callback: (payload) {
        scheduleRealtimeRefresh(
          'Completed pending service',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotations',
      callback: (payload) {
        scheduleRealtimeRefresh(
          'Service record quotation',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotation_items',
      callback: (payload) {
        scheduleRealtimeRefresh(
          'Service record quotation item',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vehicles',
      callback: (payload) {
        scheduleRealtimeRefresh(
          'Service record vehicle',
          payload.eventType,
        );
      },
    )
        .subscribe();
  }

  void scheduleRealtimeRefresh(
      String source,
      dynamic eventType,
      ) {
    debugPrint(
      '$source changed: $eventType',
    );

    realtimeRefreshTimer?.cancel();

    realtimeRefreshTimer = Timer(
      const Duration(milliseconds: 350),
      refreshServiceRecordsFromRealtime,
    );
  }

  Future<void> refreshServiceRecordsFromRealtime() async {
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

  String displayCustomer(dynamic name) {
    final value = name?.toString().trim() ?? '';
    return value.isEmpty ? 'Not Provided' : value;
  }

  String formatDate(String? dateText) {
    if (dateText == null || dateText.isEmpty) return 'Not Provided';

    final date = DateTime.parse(dateText).toLocal();

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
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

  List<String> get carModels {
    final models = records.map((record) {
      return record['vehicles']?['car_model']?.toString() ?? '';
    }).toSet().toList();

    models.removeWhere((model) => model.isEmpty);

    return ['All Car Model', ...models];
  }

  List<Map<String, dynamic>> get filteredRecords {
    final searchText = searchController.text.toLowerCase();

    return records.where((record) {
      final vehicle = record['vehicles'] ?? {};
      final plate = (vehicle['plate_number'] ?? '').toString().toLowerCase();
      final model = (vehicle['car_model'] ?? '').toString();

      final matchesPlate = plate.contains(searchText);
      final matchesModel =
          selectedModel == 'All Car Model' || model == selectedModel;

      return matchesPlate && matchesModel;
    }).toList();
  }

  int getCompletedCount() {
    return records.where((record) => record['status'] == 'Completed').length;
  }

  Color getStatusColor(String status) {
    return status == 'Completed' ? Colors.green : Colors.orange;
  }

  Color getStatusBackgroundColor(String status) {
    return status == 'Completed'
        ? Colors.green.shade50
        : Colors.orange.shade50;
  }

  Future<bool> quotationRecordExists(String quotationId) async {
    final response = await supabase
        .from('service_records')
        .select('record_id')
        .eq('quotation_id', quotationId)
        .maybeSingle();

    return response != null;
  }

  Future<void> sendRecordNotification({
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

  Future<void> createRecord({
    required Map<String, dynamic> vehicle,
    required String problem,
    required String action,
    required List<Map<String, dynamic>> items,
    String? quotationId,
    String? bookingId,
    String? pendingId,
  }) async {
    if (isSavingRecord) return;

    final vehicleId = vehicle['vehicle_id'];
    final customerId = vehicle['customer_id'];

    if (vehicleId == null) {
      showMessage(
        'Vehicle information is missing.',
      );
      return;
    }

    if (items.isEmpty) {
      showMessage(
        'Please add at least one service item.',
      );
      return;
    }

    setState(() {
      isSavingRecord = true;
    });

    try {
      if (quotationId != null &&
          quotationId.isNotEmpty) {
        final exists =
        await quotationRecordExists(
          quotationId,
        );

        if (exists) {
          showMessage(
            'This quotation already has a service record.',
          );
          return;
        }
      }

      final total = calculateTotal(items);

      final record = await supabase
          .from('service_records')
          .insert({
        'vehicle_id': vehicleId,
        'customer_id': customerId,
        'quotation_id':
        quotationId?.isEmpty == true
            ? null
            : quotationId,
        'booking_id':
        bookingId?.isEmpty == true
            ? null
            : bookingId,
        'problem_description':
        problem.trim().isEmpty
            ? 'No description'
            : problem.trim(),
        'service_action':
        action.trim().isEmpty
            ? 'Service completed.'
            : action.trim(),
        'total_price': total,
        'status': 'Completed',
      })
          .select()
          .single();

      for (final item in items) {
        await supabase
            .from('service_record_items')
            .insert({
          'record_id': record['record_id'],
          'item_name': item['item_name'],
          'quantity':
          int.tryParse(
            item['quantity'].toString(),
          ) ??
              1,
          'price':
          double.tryParse(
            item['price'].toString(),
          ) ??
              0,
        });
      }

      if (bookingId != null &&
          bookingId.isNotEmpty) {
        await supabase.from('bookings').update({
          'status': 'Completed',
        }).eq(
          'booking_id',
          bookingId,
        ).neq(
          'status',
          'Cancelled',
        );
      }

      if (pendingId != null &&
          pendingId.isNotEmpty) {
        await supabase
            .from('pending_services')
            .delete()
            .eq(
          'pending_id',
          pendingId,
        );
      }

      if (customerId != null) {
        const title = 'Service Record Created';

        const message =
            'Your vehicle service record has been created and is now available in Service Records.';

        await supabase.from('notifications').insert({
          'customer_id': customerId,
          'vehicle_id': vehicleId,
          'booking_id':
          bookingId?.isEmpty == true
              ? null
              : bookingId,
          'quotation_id':
          quotationId?.isEmpty == true
              ? null
              : quotationId,
          'title': title,
          'message': message,
          'notification_type': 'service',
          'target_page': 'service_records',
          'is_read': false,
        });

        await sendRecordNotification(
          customerId: customerId.toString(),
          title: title,
          message: message,
          data: {
            'notification_type': 'service',
            'target_page': 'service_records',
            'record_id': record['record_id'],
            'vehicle_id': vehicleId,
            'booking_id': bookingId,
            'quotation_id': quotationId,
          },
        );
      }

      await loadData();

      showMessage(
        'Service record created successfully.',
      );
    } catch (error) {
      showMessage(
        'Failed to create record: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isSavingRecord = false;
        });
      }
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

  Widget buildInfoLine({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.black45),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildRecordCard(Map<String, dynamic> record) {
    final vehicle = record['vehicles'] ?? {};
    final customer = record['customers'] ?? {};
    final items = record['service_record_items'] as List? ?? [];
    final status = record['status'] ?? 'Completed';

    final total =
        double.tryParse(record['total_price'].toString()) ?? calculateTotal(items);

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
        onTap: () => showBillDetailDialog(record),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: Color(0xFFD7E5FA),
                child: Icon(
                  Icons.assignment,
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
                      '${vehicle['plate_number'] ?? ''} - ${vehicle['car_model'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    buildInfoLine(
                      icon: Icons.person,
                      text: 'Customer: ${displayCustomer(customer['name'])}',
                    ),
                    const SizedBox(height: 5),
                    buildInfoLine(
                      icon: Icons.event,
                      text: 'Date: ${formatDate(record['created_at'])}',
                    ),
                    const SizedBox(height: 5),
                    buildInfoLine(
                      icon: Icons.build,
                      text:
                      'Problem: ${record['problem_description'] ?? 'No description'}',
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
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 15,
                          color: Colors.black38,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF339BFF)),
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Future<void> showManualRecordDialog({
    Map<String, dynamic>? pendingService,
  }) async {
    final pendingVehicle =
        pendingService?['vehicles'] ?? <String, dynamic>{};

    final pendingCustomer =
        pendingService?['customers'] ?? <String, dynamic>{};

    final quotation = pendingService?['quotations'];

    final quotationItems =
        quotation?['quotation_items'] as List? ?? [];

    Map<String, dynamic>? selectedVehicle =
    pendingService == null
        ? null
        : {
      'vehicle_id': pendingService['vehicle_id'],
      'customer_id': pendingService['customer_id'],
      'plate_number': pendingVehicle['plate_number'],
      'car_model': pendingVehicle['car_model'],
      'customers': pendingCustomer,
    };

    final vehicleSearchController =
    TextEditingController();

    final problemController =
    TextEditingController(
      text: pendingService == null
          ? ''
          : quotation?['problem_description']
          ?.toString() ??
          pendingService['note']?.toString() ??
          '',
    );

    final actionController =
    TextEditingController(
      text: pendingService == null
          ? ''
          : 'Service completed from pending service workflow.',
    );

    final itemNameController =
    TextEditingController();

    final qtyController =
    TextEditingController(text: '1');

    final priceController =
    TextEditingController();

    final List<Map<String, dynamic>> tempItems =
    quotationItems.map<Map<String, dynamic>>(
          (item) {
        return {
          'item_name':
          item['item_name']?.toString() ??
              'Service Item',
          'quantity':
          int.tryParse(
            item['quantity'].toString(),
          ) ??
              1,
          'price':
          double.tryParse(
            item['price'].toString(),
          ) ??
              0,
        };
      },
    ).toList();

    Widget sectionTitle(
        String title,
        IconData icon,
        ) {
      return Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF339BFF),
            size: 20,
          ),
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

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            final search =
            vehicleSearchController.text
                .trim()
                .toLowerCase();

            final searchedVehicles =
            vehicles.where((vehicle) {
              final plate =
              (vehicle['plate_number'] ?? '')
                  .toString()
                  .toLowerCase();

              final model =
              (vehicle['car_model'] ?? '')
                  .toString()
                  .toLowerCase();

              final customerName =
              (vehicle['customers']?['name'] ?? '')
                  .toString()
                  .toLowerCase();

              return plate.contains(search) ||
                  model.contains(search) ||
                  customerName.contains(search);
            }).toList();

            final total =
            calculateTotal(tempItems);

            return Dialog(
              insetPadding:
              const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(28),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding:
                  const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient:
                          const LinearGradient(
                            colors: [
                              Color(0xFF339BFF),
                              Color(0xFF63B3FF),
                            ],
                          ),
                          borderRadius:
                          BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.assignment,
                              color: Colors.white,
                              size: 42,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              pendingService == null
                                  ? 'Manual Service Record'
                                  : 'Completed Service Record',
                              style:
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pendingService == null
                                  ? 'Create a completed service report manually.'
                                  : 'Complete the service record for this pending service.',
                              textAlign:
                              TextAlign.center,
                              style:
                              const TextStyle(
                                color:
                                Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      sectionTitle(
                        'Vehicle Information',
                        Icons.directions_car,
                      ),

                      const SizedBox(height: 12),

                      if (pendingService != null)
                        Container(
                          width: double.infinity,
                          padding:
                          const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                            const Color(0xFFEAF4FF),
                            borderRadius:
                            BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(
                                0xFF339BFF,
                              ).withOpacity(0.18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Completed Pending Service',
                                style: TextStyle(
                                  color:
                                  Color(0xFF339BFF),
                                  fontWeight:
                                  FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${selectedVehicle?['plate_number'] ?? 'Not Provided'} - '
                                    '${selectedVehicle?['car_model'] ?? 'Not Provided'}',
                                style:
                                const TextStyle(
                                  fontWeight:
                                  FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Customer: ${displayCustomer(
                                  selectedVehicle?['customers']
                                  ?['name'],
                                )}',
                                style:
                                const TextStyle(
                                  color:
                                  Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Service Type: ${pendingService['service_type'] ?? 'Service'}',
                                style:
                                const TextStyle(
                                  color:
                                  Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'This vehicle is linked to the selected completed pending service.',
                                style: TextStyle(
                                  color:
                                  Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        TextField(
                          controller:
                          vehicleSearchController,
                          onChanged: (_) {
                            setDialogState(() {});
                          },
                          decoration:
                          InputDecoration(
                            hintText:
                            'Search plate, model or customer',
                            prefixIcon:
                            const Icon(
                              Icons.search,
                              color:
                              Color(0xFF339BFF),
                            ),
                            suffixIcon:
                            vehicleSearchController
                                .text
                                .isNotEmpty
                                ? IconButton(
                              onPressed: () {
                                vehicleSearchController
                                    .clear();

                                setDialogState(
                                      () {},
                                );
                              },
                              icon:
                              const Icon(
                                Icons.clear,
                              ),
                            )
                                : null,
                            filled: true,
                            fillColor:
                            const Color(
                              0xFFF5F7FA,
                            ),
                            border:
                            OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(
                                18,
                              ),
                              borderSide:
                              BorderSide.none,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (selectedVehicle != null)
                          Container(
                            width: double.infinity,
                            padding:
                            const EdgeInsets.all(
                              14,
                            ),
                            decoration:
                            BoxDecoration(
                              color: const Color(
                                0xFFEAF4FF,
                              ),
                              borderRadius:
                              BorderRadius.circular(
                                18,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                              children: [
                                Text(
                                  '${selectedVehicle!['plate_number'] ?? 'Not Provided'} - '
                                      '${selectedVehicle!['car_model'] ?? 'Not Provided'}',
                                  style:
                                  const TextStyle(
                                    fontWeight:
                                    FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(
                                  height: 6,
                                ),
                                Text(
                                  'Customer: ${displayCustomer(
                                    selectedVehicle![
                                    'customers']
                                    ?['name'],
                                  )}',
                                  style:
                                  const TextStyle(
                                    color:
                                    Colors.black54,
                                  ),
                                ),
                                const SizedBox(
                                  height: 6,
                                ),
                                Align(
                                  alignment:
                                  Alignment
                                      .centerRight,
                                  child:
                                  TextButton.icon(
                                    onPressed: () {
                                      setDialogState(
                                            () {
                                          selectedVehicle =
                                          null;

                                          vehicleSearchController
                                              .clear();
                                        },
                                      );
                                    },
                                    icon:
                                    const Icon(
                                      Icons
                                          .change_circle_outlined,
                                    ),
                                    label:
                                    const Text(
                                      'Change Vehicle',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            height: 160,
                            child:
                            searchedVehicles
                                .isEmpty
                                ? const Center(
                              child: Text(
                                'No vehicle found.',
                                style:
                                TextStyle(
                                  color: Colors
                                      .black54,
                                ),
                              ),
                            )
                                : ListView.builder(
                              itemCount:
                              searchedVehicles
                                  .length,
                              itemBuilder:
                                  (
                                  context,
                                  index,
                                  ) {
                                final vehicle =
                                searchedVehicles[
                                index];

                                final customer =
                                    vehicle['customers'] ??
                                        {};

                                return Card(
                                  elevation:
                                  0,
                                  color:
                                  const Color(
                                    0xFFF5F7FA,
                                  ),
                                  shape:
                                  RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(
                                      16,
                                    ),
                                  ),
                                  child:
                                  ListTile(
                                    leading:
                                    const CircleAvatar(
                                      backgroundColor:
                                      Color(
                                        0xFFD7E5FA,
                                      ),
                                      child:
                                      Icon(
                                        Icons
                                            .directions_car,
                                        color:
                                        Color(
                                          0xFF339BFF,
                                        ),
                                      ),
                                    ),
                                    title:
                                    Text(
                                      '${vehicle['plate_number'] ?? ''} - '
                                          '${vehicle['car_model'] ?? ''}',
                                      style:
                                      const TextStyle(
                                        fontWeight:
                                        FontWeight.bold,
                                      ),
                                    ),
                                    subtitle:
                                    Text(
                                      'Customer: ${displayCustomer(
                                        customer[
                                        'name'],
                                      )}',
                                    ),
                                    trailing:
                                    const Text(
                                      'SELECT',
                                      style:
                                      TextStyle(
                                        color:
                                        Color(
                                          0xFF339BFF,
                                        ),
                                        fontWeight:
                                        FontWeight.bold,
                                        fontSize:
                                        10,
                                      ),
                                    ),
                                    onTap:
                                        () {
                                      setDialogState(
                                            () {
                                          selectedVehicle =
                                              vehicle;
                                        },
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                      ],

                      const SizedBox(height: 22),

                      sectionTitle(
                        'Service Details',
                        Icons.build_circle,
                      ),

                      const SizedBox(height: 12),

                      buildInputBox(
                        controller:
                        problemController,
                        hint:
                        'Problem description',
                        icon: Icons
                            .report_problem_outlined,
                        maxLines: 2,
                      ),

                      const SizedBox(height: 12),

                      buildInputBox(
                        controller:
                        actionController,
                        hint:
                        'Service action / repair notes',
                        icon: Icons
                            .build_circle_outlined,
                        maxLines: 2,
                      ),

                      const SizedBox(height: 22),

                      sectionTitle(
                        'Parts / Labour',
                        Icons.handyman,
                      ),

                      const SizedBox(height: 12),

                      buildInputBox(
                        controller:
                        itemNameController,
                        hint:
                        'Part / labour name',
                        icon: Icons.build,
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: buildInputBox(
                              controller:
                              qtyController,
                              hint: 'Qty',
                              icon:
                              Icons.numbers,
                              keyboardType:
                              TextInputType
                                  .number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildInputBox(
                              controller:
                              priceController,
                              hint: 'Unit price',
                              icon: Icons
                                  .payments_outlined,
                              keyboardType:
                              const TextInputType
                                  .numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child:
                        OutlinedButton.icon(
                          onPressed: () {
                            final itemName =
                            itemNameController
                                .text
                                .trim();

                            final quantity =
                            int.tryParse(
                              qtyController.text
                                  .trim(),
                            );

                            final price =
                            double.tryParse(
                              priceController.text
                                  .trim(),
                            );

                            if (itemName.isEmpty ||
                                quantity == null ||
                                price == null) {
                              showMessage(
                                'Please complete item information correctly.',
                              );
                              return;
                            }

                            if (quantity <= 0) {
                              showMessage(
                                'Quantity must be more than 0.',
                              );
                              return;
                            }

                            if (price < 0) {
                              showMessage(
                                'Price cannot be negative.',
                              );
                              return;
                            }

                            setDialogState(() {
                              tempItems.add({
                                'item_name':
                                itemName,
                                'quantity':
                                quantity,
                                'price': price,
                              });

                              itemNameController
                                  .clear();

                              qtyController.text =
                              '1';

                              priceController
                                  .clear();
                            });
                          },
                          icon:
                          const Icon(Icons.add),
                          label:
                          const Text('Add Item'),
                        ),
                      ),

                      const SizedBox(height: 14),

                      if (tempItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding:
                          const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                            const Color(0xFFF5F7FA),
                            borderRadius:
                            BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'No service items added.',
                            textAlign:
                            TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                            ),
                          ),
                        )
                      else
                        ...tempItems.asMap().entries.map(
                              (entry) {
                            final index =
                                entry.key;

                            final item =
                                entry.value;

                            final quantity =
                                int.tryParse(
                                  item['quantity']
                                      .toString(),
                                ) ??
                                    1;

                            final price =
                                double.tryParse(
                                  item['price']
                                      .toString(),
                                ) ??
                                    0;

                            final subtotal =
                                quantity * price;

                            return Card(
                              elevation: 0,
                              color:
                              const Color(
                                0xFFF5F7FA,
                              ),
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                  16,
                                ),
                              ),
                              child: ListTile(
                                leading:
                                const Icon(
                                  Icons
                                      .check_circle,
                                  color:
                                  Colors.green,
                                ),
                                title: Text(
                                  item['item_name']
                                      ?.toString() ??
                                      'Service Item',
                                  style:
                                  const TextStyle(
                                    fontWeight:
                                    FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Qty: $quantity × RM ${price.toStringAsFixed(2)}',
                                ),
                                trailing: Row(
                                  mainAxisSize:
                                  MainAxisSize.min,
                                  children: [
                                    Text(
                                      'RM ${subtotal.toStringAsFixed(2)}',
                                      style:
                                      const TextStyle(
                                        color: Color(
                                          0xFF339BFF,
                                        ),
                                        fontWeight:
                                        FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon:
                                      const Icon(
                                        Icons.delete,
                                        color:
                                        Colors.red,
                                      ),
                                      onPressed: () {
                                        setDialogState(
                                              () {
                                            tempItems
                                                .removeAt(
                                              index,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                          const Color(0xFFEAF4FF),
                          borderRadius:
                          BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'RM ${total.toStringAsFixed(2)}',
                              style:
                              const TextStyle(
                                color:
                                Color(0xFF339BFF),
                                fontWeight:
                                FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child:
                            OutlinedButton(
                              onPressed: () {
                                Navigator.pop(
                                  dialogContext,
                                );
                              },
                              child:
                              const Text(
                                'Cancel',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                            ElevatedButton.icon(
                              style:
                              ElevatedButton
                                  .styleFrom(
                                backgroundColor:
                                const Color(
                                  0xFF339BFF,
                                ),
                                foregroundColor:
                                Colors.white,
                              ),
                              onPressed: () async {
                                if (selectedVehicle ==
                                    null) {
                                  showMessage(
                                    'Please select a vehicle.',
                                  );
                                  return;
                                }

                                if (tempItems
                                    .isEmpty) {
                                  showMessage(
                                    'Please add at least one service item.',
                                  );
                                  return;
                                }

                                if (isSavingRecord) {
                                  return;
                                }

                                Navigator.pop(
                                  dialogContext,
                                );

                                await createRecord(
                                  vehicle:
                                  selectedVehicle!,
                                  problem:
                                  problemController
                                      .text
                                      .trim(),
                                  action:
                                  actionController
                                      .text
                                      .trim(),
                                  items: List<
                                      Map<String,
                                          dynamic>>.from(
                                    tempItems,
                                  ),
                                  quotationId:
                                  pendingService?[
                                  'quotation_id']
                                      ?.toString(),
                                  bookingId:
                                  pendingService?[
                                  'booking_id']
                                      ?.toString(),
                                  pendingId:
                                  pendingService?[
                                  'pending_id']
                                      ?.toString(),
                                );
                              },
                              icon:
                              const Icon(
                                Icons.save,
                              ),
                              label:
                              const Text(
                                'Save Record',
                              ),
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

    vehicleSearchController.dispose();
    problemController.dispose();
    actionController.dispose();
    itemNameController.dispose();
    qtyController.dispose();
    priceController.dispose();
  }

  void showAddRecordSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: Color(0xFFD7E5FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create Service Record',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFD7E5FA),
                  child: Icon(Icons.edit_note, color: Color(0xFF339BFF)),
                ),
                title: const Text(
                  'Manual Service Record',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Create record for walk-in or old service.'),
                onTap: () {
                  Navigator.pop(context);
                  showManualRecordDialog();
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFD7E5FA),
                  child: Icon(Icons.car_repair, color: Color(0xFF339BFF)),
                ),
                title: const Text(
                  'From Completed Pending Service',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Create record only after service status is completed.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  showCompletedPendingServiceDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> createRecordFromPendingService(
      Map<String, dynamic> pendingService,
      ) async {
    try {
      final status =
      pendingService['status']?.toString();

      if (status != 'Completed') {
        showMessage(
          'Only a completed pending service can create a service record.',
        );
        return;
      }

      final quotation =
      pendingService['quotations'];

      final quotationId =
      pendingService['quotation_id']?.toString();

      final quotationItems =
          quotation?['quotation_items'] as List? ?? [];

      // Online customer / confirmed quotation:
      // Directly create the service record using quotation items.
      if (quotationId != null &&
          quotationId.isNotEmpty &&
          quotationItems.isNotEmpty) {
        final items =
        quotationItems.map<Map<String, dynamic>>(
              (item) {
            return {
              'item_name':
              item['item_name']?.toString() ??
                  'Service Item',
              'quantity':
              int.tryParse(
                item['quantity'].toString(),
              ) ??
                  1,
              'price':
              double.tryParse(
                item['price'].toString(),
              ) ??
                  0,
            };
          },
        ).toList();

        final vehicle = {
          'vehicle_id':
          pendingService['vehicle_id'],
          'customer_id':
          pendingService['customer_id'],
        };

        await createRecord(
          vehicle: vehicle,
          quotationId: quotationId,
          bookingId:
          pendingService['booking_id']
              ?.toString(),
          pendingId:
          pendingService['pending_id']
              ?.toString(),
          problem:
          quotation?['problem_description']
              ?.toString() ??
              pendingService['note']
                  ?.toString() ??
              'No description',
          action:
          'Service completed according to the confirmed quotation.',
          items: items,
        );

        return;
      }

      // Walk-in / no quotation:
      // Open manual form so Admin can enter the actual items and price.
      showManualRecordDialog(
        pendingService: pendingService,
      );
    } catch (error) {
      showMessage(
        'Failed to create record from completed pending service: $error',
      );
    }
  }

  void showCompletedPendingServiceDialog() {
    Map<String, dynamic>? selectedPendingService;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 28,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0xFF339BFF),
                          child: Icon(
                            Icons.car_repair,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Completed Pending Service',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 320,
                      child: completedPendingServices.isEmpty
                          ? const Center(
                        child: Text('No completed pending service found.'),
                      )
                          : ListView.builder(
                        itemCount: completedPendingServices.length,
                        itemBuilder: (context, index) {
                          final pending =
                          completedPendingServices[index];
                          final vehicle = pending['vehicles'] ?? {};
                          final customer = pending['customers'] ?? {};
                          final quotation = pending['quotations'];
                          final items =
                              quotation?['quotation_items'] as List? ?? [];
                          final total = calculateTotal(items);
                          final isSelected =
                              selectedPendingService == pending;

                          return Card(
                            child: ListTile(
                              title: Text(
                                '${vehicle['plate_number'] ?? ''} - ${vehicle['car_model'] ?? ''}',
                              ),
                              subtitle: Text(
                                'Customer: ${displayCustomer(customer['name'])}\n'
                                    'Type: ${pending['service_type'] ?? 'Service'}\n'
                                    'Total: RM ${total.toStringAsFixed(2)}',
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                                  : null,
                              onTap: () {
                                setDialogState(() {
                                  selectedPendingService = pending;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
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
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF339BFF),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              if (selectedPendingService == null) {
                                showMessage(
                                  'Please select a completed pending service.',
                                );
                                return;
                              }

                              Navigator.pop(context);
                              await createRecordFromPendingService(
                                selectedPendingService!,
                              );
                            },
                            child: const Text('Create Record'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void showBillDetailDialog(Map<String, dynamic> record) {
    final vehicle = record['vehicles'] ?? {};
    final customer = record['customers'] ?? {};
    final items = record['service_record_items'] as List? ?? [];
    final total =
        double.tryParse(record['total_price'].toString()) ?? calculateTotal(items);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
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
                          'Service Report',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Completed vehicle service details',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  buildReportSection(
                    title: 'Customer & Vehicle',
                    icon: Icons.directions_car,
                    children: [
                      buildReportRow('Customer', displayCustomer(customer['name'])),
                      buildReportRow('Phone', customer['phone'] ?? 'Not Provided'),
                      buildReportRow('Plate Number', vehicle['plate_number'] ?? ''),
                      buildReportRow('Car Model', vehicle['car_model'] ?? ''),
                      buildReportRow('Date', formatDate(record['created_at'])),
                    ],
                  ),

                  const SizedBox(height: 14),

                  buildReportSection(
                    title: 'Service Details',
                    icon: Icons.build_circle,
                    children: [
                      buildReportRow(
                        'Problem',
                        record['problem_description'] ?? 'No description',
                      ),
                      buildReportRow(
                        'Action',
                        record['service_action'] ?? 'No action notes',
                      ),
                      buildReportRow('Status', record['status'] ?? 'Completed'),
                    ],
                  ),

                  const SizedBox(height: 14),

                  buildReportSection(
                    title: 'Changed / Fixed Items',
                    icon: Icons.handyman,
                    children: [
                      if (items.isEmpty)
                        const Text(
                          'No items found.',
                          style: TextStyle(color: Colors.black54),
                        )
                      else
                        ...items.map((item) {
                          final qty =
                              int.tryParse(item['quantity'].toString()) ?? 1;
                          final price =
                              double.tryParse(item['price'].toString()) ?? 0;
                          final subtotal = qty * price;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['item_name']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Qty $qty × RM ${price.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'RM ${subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF339BFF),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),

                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'RM ${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF339BFF),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
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
                            await PdfService.viewServiceReport(record);
                          },
                          icon: const Icon(Icons.visibility),
                          label: const Text('View PDF'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await PdfService.shareServiceReport(record);
                              },
                              icon: const Icon(Icons.share),
                              label: const Text('Share'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ),
                        ],
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
  }

  Widget buildReportSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF339BFF).withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF339BFF), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget buildReportRow(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toString().isEmpty ? 'Not Provided' : value.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayRecords = filteredRecords;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Service Records'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
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
                      'Service History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Create and view completed vehicle service records',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.assignment,
                          title: 'Records',
                          value: '${records.length}',
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
                      controller: searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by plate number',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                          onPressed: () {
                            searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedModel,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.directions_car),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: carModels.map((model) {
                        return DropdownMenuItem(
                          value: model,
                          child: Text(model),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedModel = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (displayRecords.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No service records found.',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildRecordCard(displayRecords[index]);
                    },
                    childCount: displayRecords.length,
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
            heroTag: 'addRecord',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: showAddRecordSourceDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Record'),
          ),
        ],
      ),
    );
  }
}