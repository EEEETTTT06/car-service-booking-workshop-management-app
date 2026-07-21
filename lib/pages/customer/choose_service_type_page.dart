import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';

class ChooseServiceTypePage extends StatefulWidget {
  final String selectedDate;
  final Function(Map<String, dynamic>) onBookingConfirmed;

  const ChooseServiceTypePage({
    super.key,
    required this.selectedDate,
    required this.onBookingConfirmed,
  });

  @override
  State<ChooseServiceTypePage> createState() => _ChooseServiceTypePageState();
}

class _ChooseServiceTypePageState extends State<ChooseServiceTypePage> {
  bool isLoading = false;
  bool isSubmitting = false;
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  Map<String, dynamic>? currentCustomer;
  Map<String, dynamic>? selectedVehicle;

  final TextEditingController problemController = TextEditingController();

  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> services = [];
  List<Map<String, dynamic>> selectedServices = [];

  RealtimeChannel? servicesRealtimeChannel;
  Timer? servicesRealtimeTimer;
  bool isRefreshingServicesRealtime = false;

  @override
  void initState() {
    super.initState();

    loadData();
    setupServicesRealtimeSubscription();

    scrollController.addListener(() {
      if (!mounted) return;

      final shouldShow = scrollController.offset > 180;

      if (shouldShow != showBackToTop) {
        setState(() {
          showBackToTop = shouldShow;
        });
      }
    });
  }

  void scrollToTop() {
    if (!scrollController.hasClients) return;

    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await fetchVehicles();
      await fetchServices();
    } catch (error) {
      showMessage('Failed to load data: $error');
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

  Future<void> fetchVehicles() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('vehicles')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .order('created_at', ascending: false);

    vehicles = List<Map<String, dynamic>>.from(response);

    if (vehicles.isNotEmpty) {
      selectedVehicle = vehicles.first;
    }
  }

  Future<void> fetchServices({
    bool refreshUi = false,
  }) async {
    final response = await supabase
        .from('services')
        .select()
        .order(
      'service_name',
      ascending: true,
    );

    final latestServices =
    List<Map<String, dynamic>>.from(
      response,
    );

    final latestServicesById = <String, Map<String, dynamic>>{
      for (final service in latestServices)
        service['service_id'].toString(): service,
    };

    final updatedSelectedServices =
    <Map<String, dynamic>>[];

    for (final selectedService in selectedServices) {
      final serviceId =
      selectedService['service_id']?.toString();

      if (serviceId == null) {
        continue;
      }

      final latestService =
      latestServicesById[serviceId];

      if (latestService == null) {
        continue;
      }

      if (!isServiceAvailable(latestService)) {
        continue;
      }

      updatedSelectedServices.add(
        latestService,
      );
    }

    services = latestServices;
    selectedServices = updatedSelectedServices;

    if (refreshUi && mounted) {
      setState(() {});
    }
  }

  void setupServicesRealtimeSubscription() {
    if (servicesRealtimeChannel != null) {
      return;
    }

    servicesRealtimeChannel = supabase
        .channel(
      'customer-service-selection-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'services',
      callback: (payload) {
        debugPrint(
          'Customer service list changed: '
              '${payload.eventType}',
        );

        scheduleServicesRealtimeRefresh();
      },
    )
        .subscribe();
  }

  void scheduleServicesRealtimeRefresh() {
    servicesRealtimeTimer?.cancel();

    servicesRealtimeTimer = Timer(
      const Duration(milliseconds: 350),
      refreshServicesFromRealtime,
    );
  }

  Future<void> refreshServicesFromRealtime() async {
    if (!mounted ||
        isRefreshingServicesRealtime) {
      return;
    }

    isRefreshingServicesRealtime = true;

    try {
      await fetchServices(
        refreshUi: true,
      );
    } catch (error) {
      debugPrint(
        'Realtime service selection refresh failed: '
            '$error',
      );
    } finally {
      isRefreshingServicesRealtime = false;
    }
  }


  String get sqlDate {
    if (widget.selectedDate.contains('/')) {
      final parts = widget.selectedDate.split('/');
      final day = parts[0].padLeft(2, '0');
      final month = parts[1].padLeft(2, '0');
      final year = parts[2];
      return '$year-$month-$day';
    }

    return widget.selectedDate;
  }

  bool isServiceAvailable(Map<String, dynamic> service) {
    final status = (service['availability_status'] ?? 'Available').toString();
    return status == 'Available';
  }

  double get totalPrice {
    double total = 0;

    for (final service in selectedServices) {
      total += double.tryParse(service['price'].toString()) ?? 0;
    }

    return total;
  }

  void toggleService(Map<String, dynamic> service) {
    if (!isServiceAvailable(service)) {
      showMessage('This service is currently not available.');
      return;
    }

    setState(() {
      final alreadySelected = selectedServices.any(
            (item) => item['service_id'] == service['service_id'],
      );

      if (alreadySelected) {
        selectedServices.removeWhere(
              (item) => item['service_id'] == service['service_id'],
        );
      } else {
        selectedServices.add(service);
      }
    });
  }

  Future<void> notifyAdminsAboutNewBooking({
    required Map<String, dynamic> booking,
  }) async {
    try {
      debugPrint('===== notifyAdminsAboutNewBooking START =====');

      final customerName = currentCustomer?['name'] ?? 'A customer';
      final plate = selectedVehicle?['plate_number'] ?? 'Unknown Vehicle';

      const title = 'New Appointment Booking';
      final body =
          '$customerName booked an appointment for $plate on ${widget.selectedDate}.';

      debugPrint('Notification title: $title');
      debugPrint('Notification body: $body');

      final admins = await supabase
          .from('admins')
          .select('admin_id, notification_enabled');

      debugPrint('Admins found: $admins');

      for (final admin in admins) {
        debugPrint('Inserting notification for admin: ${admin['admin_id']}');

        await supabase.from('admin_notifications').insert({
          'admin_id': admin['admin_id'],
          'title': title,
          'message': body,
          'is_read': false,
          'notification_type': 'booking',
        });

        debugPrint('Insert success for admin: ${admin['admin_id']}');
      }

      final enabledAdminIds = admins
          .where((admin) => admin['notification_enabled'] != false)
          .map((admin) => admin['admin_id'])
          .toList();

      debugPrint('Enabled admin IDs: $enabledAdminIds');

      if (enabledAdminIds.isEmpty) {
        debugPrint('No admin has notification enabled.');
        return;
      }

      final tokens = await supabase
          .from('admin_fcm_tokens')
          .select('fcm_token, admin_id');

      debugPrint('All admin tokens found: $tokens');

      int sentCount = 0;

      for (final row in tokens) {
        final tokenAdminId = row['admin_id'];
        final token = row['fcm_token'];

        if (!enabledAdminIds.contains(tokenAdminId)) {
          continue;
        }

        if (token == null || token.toString().isEmpty) {
          continue;
        }

        await supabase.functions.invoke(
          'send-fcm',
          body: {
            'token': token,
            'title': title,
            'body': body,
          },
        );

        sentCount++;
      }

      debugPrint('Notification sent to $sentCount enabled admin device(s).');
      debugPrint('===== notifyAdminsAboutNewBooking END =====');
    } catch (error, stackTrace) {
      debugPrint('Notify Admin Error: $error');
      debugPrint(stackTrace.toString());
    }
  }

  Future<void> confirmBooking() async {
    if (isSubmitting) return;

    if (currentCustomer == null) {
      showMessage(
        'Customer profile not found.',
      );
      return;
    }

    if (selectedVehicle == null) {
      showMessage(
        'Please select a vehicle.',
      );
      return;
    }

    if (selectedServices.isEmpty) {
      showMessage(
        'Please select at least one service.',
      );
      return;
    }

    final vehicleId =
    selectedVehicle!['vehicle_id']
        ?.toString();

    if (vehicleId == null ||
        vehicleId.isEmpty) {
      showMessage(
        'Vehicle information is missing.',
      );
      return;
    }

    final appointmentDate =
    DateTime.tryParse(sqlDate);

    if (appointmentDate == null) {
      showMessage(
        'Invalid appointment date.',
      );
      return;
    }

    final serviceIds = selectedServices
        .map(
          (service) =>
          service['service_id']
              ?.toString(),
    )
        .whereType<String>()
        .where(
          (serviceId) =>
      serviceId.isNotEmpty,
    )
        .toList();

    if (serviceIds.isEmpty) {
      showMessage(
        'Please select at least one valid service.',
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      /*
     * The database RPC performs all booking
     * checks and inserts the booking together
     * with its selected services in one
     * transaction.
     */
      final rpcResult = await supabase.rpc(
        'create_customer_booking',
        params: {
          'p_vehicle_id': vehicleId,
          'p_appointment_date': sqlDate,
          'p_problem_description':
          problemController.text.trim(),
          'p_service_ids': serviceIds,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'The booking was created, but the returned booking information is invalid.',
        );
      }

      final booking =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final bookingId =
      booking['booking_id']
          ?.toString();

      if (bookingId == null ||
          bookingId.isEmpty) {
        throw Exception(
          'Booking ID was not returned.',
        );
      }

      /*
     * Notification failure will not remove the
     * successfully created booking because the
     * notification method handles its own errors.
     */
      await notifyAdminsAboutNewBooking(
        booking: booking,
      );

      widget.onBookingConfirmed({
        'booking_id': bookingId,
        'plate':
        selectedVehicle!['plate_number'],
        'model':
        selectedVehicle!['car_model'],
        'date': widget.selectedDate,
        'problem':
        problemController.text.trim(),
        'services': selectedServices
            .map(
              (service) =>
              service['service_name']
                  .toString(),
        )
            .toList(),
        'estimatedTotal': totalPrice,
        'status':
        booking['status'] ?? 'Booked',
      });

      if (!mounted) return;

      final navigator =
      Navigator.of(context);

      final messenger =
      ScaffoldMessenger.of(context);

      navigator.pop();
      navigator.pop();

      messenger.hideCurrentSnackBar();

      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Booking confirmed successfully.',
          ),
        ),
      );
    } on PostgrestException catch (error) {
      /*
     * Display the clear message raised by the
     * PostgreSQL RPC, such as duplicate booking,
     * full date, closed workshop, or booking limit.
     */
      showMessage(error.message);
    } catch (error) {
      showMessage(
        'Failed to confirm booking: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  void showConfirmBookingDialog() {
    if (selectedVehicle == null) {
      showMessage('Please select a vehicle.');
      return;
    }

    if (selectedServices.isEmpty) {
      showMessage('Please select at least one service.');
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Booking'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildDetailRow(
                    'Plate Number',
                    selectedVehicle!['plate_number'] ?? '',
                  ),
                  buildDetailRow(
                    'Car Model',
                    selectedVehicle!['car_model'] ?? '',
                  ),
                  buildDetailRow('Booking Date', widget.selectedDate),
                  if (problemController.text.trim().isNotEmpty)
                    buildDetailRow('Notes', problemController.text.trim()),
                  const SizedBox(height: 12),
                  const Text(
                    'Selected Services:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...selectedServices.map((service) {
                    final price =
                        double.tryParse(service['price'].toString()) ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('• ${service['service_name']}'),
                          ),
                          Text(
                            'RM ${price.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Estimated Total: RM ${totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Note: Final price may change after workshop inspection.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                Navigator.pop(context);
                await confirmBooking();
              },
              child: Text(isSubmitting ? 'Saving...' : 'Confirm'),
            ),
          ],
        );
      },
    );
  }

  Color getServiceStatusColor(bool available) {
    return available ? Colors.green : Colors.red;
  }

  Color getServiceStatusBackgroundColor(bool available) {
    return available ? Colors.green.shade50 : Colors.red.shade50;
  }

  Widget buildDetailRow(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              '$title:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value.toString())),
        ],
      ),
    );
  }

  Widget buildProblemDescriptionCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF339BFF).withOpacity(0.35),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 9,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFD7E5FA),
                child: Icon(
                  Icons.description_outlined,
                  color: Color(0xFF339BFF),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Problem / Service Notes',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tell the workshop about any issue, noise, warning light, or special request.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: problemController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText:
              'Example: Engine noise, brake sound, aircond not cold, warning light appeared...',
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildServiceCard(Map<String, dynamic> service) {
    final isAvailable = isServiceAvailable(service);
    final isSelected = selectedServices.any(
          (item) => item['service_id'] == service['service_id'],
    );

    final price = double.tryParse(service['price'].toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isAvailable ? Colors.white : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? const Color(0xFF339BFF) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => toggleService(service),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor:
                isAvailable ? const Color(0xFFD7E5FA) : Colors.grey.shade300,
                child: Icon(
                  Icons.build,
                  color: isAvailable ? const Color(0xFF339BFF) : Colors.grey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['service_name'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isAvailable ? Colors.black : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RM ${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: getServiceStatusBackgroundColor(isAvailable),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isAvailable ? 'Available' : 'Not Available',
                        style: TextStyle(
                          color: getServiceStatusColor(isAvailable),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: isSelected,
                activeColor: const Color(0xFF339BFF),
                onChanged: isAvailable ? (_) => toggleService(service) : null,
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
                    title,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
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

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    servicesRealtimeTimer?.cancel();

    final channel = servicesRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    problemController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableCount = services.where(isServiceAvailable).length;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Choose Service Type'),
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
        onRefresh: loadData,
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
                      'Select Your Service',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'Booking Date: ${widget.selectedDate}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.build,
                          title: 'Available',
                          value: '$availableCount',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.check_circle,
                          title: 'Selected',
                          value: '${selectedServices.length}',
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: selectedVehicle?['vehicle_id'],
                      decoration: InputDecoration(
                        labelText: 'Select Vehicle',
                        prefixIcon: const Icon(
                          Icons.directions_car,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: vehicles.map((vehicle) {
                        return DropdownMenuItem<String>(
                          value: vehicle['vehicle_id'],
                          child: Text(
                            '${vehicle['plate_number']} - '
                                '${vehicle['car_model']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedVehicle = vehicles.firstWhere(
                                (vehicle) =>
                            vehicle['vehicle_id'] == value,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),

            if (services.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No services available.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 16,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      buildProblemDescriptionCard(),
                      ...services.map(
                            (service) => buildServiceCard(service),
                      ),
                    ],
                  ),
                ),
              ),

            if (services.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7E5FA),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Estimated Total: '
                              'RM ${totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF339BFF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : showConfirmBookingDialog,
                          icon: const Icon(
                            Icons.calendar_month,
                          ),
                          label: Text(
                            isSubmitting
                                ? 'Booking...'
                                : 'Book Service',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 90),
            ),
          ],
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton.small(
        heroTag: 'chooseServiceTypeBackToTop',
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