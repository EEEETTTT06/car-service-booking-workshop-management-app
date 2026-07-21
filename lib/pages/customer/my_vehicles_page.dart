import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'book_service_page.dart';
import 'service_records_page.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';

class MyVehiclesPage extends StatefulWidget {
  const MyVehiclesPage({super.key});

  @override
  State<MyVehiclesPage> createState() => _MyVehiclesPageState();
}

class _MyVehiclesPageState extends State<MyVehiclesPage> {
  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;
  String searchText = '';

  Map<String, dynamic>? currentCustomer;
  List<Map<String, dynamic>> vehicles = [];
  Map<String, Map<String, dynamic>> vehicleBookings = {};

  RealtimeChannel? vehiclesRealtimeChannel;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    loadData();

    scrollController.addListener(() {
      if (scrollController.offset > 350 && !showBackToTop) {
        setState(() {
          showBackToTop = true;
        });
      } else if (scrollController.offset <= 350 && showBackToTop) {
        setState(() {
          showBackToTop = false;
        });
      }
    });
  }

  @override
  void dispose() {
    final channel = vehiclesRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

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

  Future<void> loadData() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await fetchVehicles();
      await fetchVehicleBookings();
      setupRealtimeSubscription();
    } catch (error) {
      showMessage('Failed to load vehicles: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
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
  }

  Future<void> fetchVehicleBookings() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('bookings')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .neq('status', 'Cancelled')
        .gte('appointment_date', toSqlDate(DateTime.now()))
        .order('appointment_date', ascending: true);

    final Map<String, Map<String, dynamic>> temp = {};

    for (final booking in response) {
      final vehicleId = booking['vehicle_id'].toString();

      if (!temp.containsKey(vehicleId)) {
        temp[vehicleId] = Map<String, dynamic>.from(booking);
      }
    }

    vehicleBookings = temp;
  }

  void setupRealtimeSubscription() {
    if (currentCustomer == null) return;

    // Prevent duplicate Realtime subscriptions.
    if (vehiclesRealtimeChannel != null) {
      return;
    }

    final customerId =
    currentCustomer!['customer_id'].toString();

    vehiclesRealtimeChannel = supabase
        .channel(
      'customer-vehicles-$customerId',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vehicles',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        debugPrint(
          'Customer vehicle changed: '
              '${payload.eventType}',
        );

        refreshVehiclesFromRealtime();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        debugPrint(
          'Customer vehicle booking changed: '
              '${payload.eventType}',
        );

        refreshVehiclesFromRealtime();
      },
    )
        .subscribe();
  }

  Future<void> refreshVehiclesFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await fetchVehicles();
      await fetchVehicleBookings();

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      debugPrint(
        'Realtime vehicle refresh failed: $error',
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  String toSqlDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String formatDate(String date) {
    final parsedDate = DateTime.parse(date);
    return '${parsedDate.day}/${parsedDate.month}/${parsedDate.year}';
  }

  String getDisplayStatus(String status) {
    if (status == 'Link Record' || status == 'Verified') {
      return 'Link Record';
    }

    return 'Pending Claim';
  }

  Color getStatusColor(String status) {
    if (status == 'Link Record' || status == 'Verified') {
      return Colors.green;
    }

    return Colors.orange;
  }

  Color getStatusBackgroundColor(String status) {
    if (status == 'Link Record' || status == 'Verified') {
      return Colors.green.shade50;
    }

    return Colors.orange.shade50;
  }

  int get pendingClaimCount {
    return vehicles.where((vehicle) {
      final status = vehicle['verification_status'] ?? 'Pending Claim';
      return status != 'Link Record' && status != 'Verified';
    }).length;
  }

  List<Map<String, dynamic>> get filteredVehicles {
    final search = searchText.trim().toLowerCase();

    if (search.isEmpty) {
      return vehicles;
    }

    return vehicles.where((vehicle) {
      final plate =
      (vehicle['plate_number'] ?? '').toString().toLowerCase();

      final model =
      (vehicle['car_model'] ?? '').toString().toLowerCase();

      final status =
      getDisplayStatus(
        vehicle['verification_status'] ?? 'Pending Claim',
      ).toLowerCase();

      return plate.contains(search) ||
          model.contains(search) ||
          status.contains(search);
    }).toList();
  }

  void goToServiceRecords(String plate) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceRecordsPage(initialPlate: plate),
      ),
    );
  }

  void goToBookingPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BookServicePage(),
      ),
    );
  }
  Future<void> notifyAdminsVehicleClaim({
    required String plate,
    required String model,
  }) async {
    try {
      final customerName = currentCustomer?['name'] ?? 'A customer';

      const title = 'New Vehicle Claim Request';
      final body =
          '$customerName submitted a vehicle claim request for $plate - $model.';

      final admins = await supabase
          .from('admins')
          .select('admin_id, notification_enabled');

      for (final admin in admins) {
        await supabase.from('admin_notifications').insert({
          'admin_id': admin['admin_id'],
          'title': title,
          'message': body,
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
      debugPrint('Vehicle claim notify admin error: $error');
    }
  }

  Future<void> addVehicle({
    required String plate,
    required String model,
  }) async {
    if (currentCustomer == null) return;

    final upperPlate = plate.toUpperCase();
    final upperModel = model.toUpperCase();

    try {
      final existingVehicle = await supabase
          .from('vehicles')
          .select()
          .eq('plate_number', upperPlate)
          .maybeSingle();

      if (existingVehicle != null) {
        final existingCustomerId = existingVehicle['customer_id'];
        final existingStatus =
            existingVehicle['verification_status'] ?? 'Pending Claim';

        if (existingCustomerId != null &&
            existingCustomerId != currentCustomer!['customer_id'] &&
            (existingStatus == 'Link Record' || existingStatus == 'Verified')) {
          showMessage('This vehicle is already linked to another customer.');
          return;
        }

        await supabase.from('vehicles').update({
          'customer_id': currentCustomer!['customer_id'],
          'customer_name': currentCustomer!['name'].toString().toUpperCase(),
          'car_model': upperModel,
          'verification_status': 'Pending Claim',
        }).eq('vehicle_id', existingVehicle['vehicle_id']);
      } else {
        await supabase.from('vehicles').insert({
          'plate_number': upperPlate,
          'car_model': upperModel,
          'customer_id': currentCustomer!['customer_id'],
          'customer_name': currentCustomer!['name'].toString().toUpperCase(),
          'verification_status': 'Pending Claim',
        });
      }

      await notifyAdminsVehicleClaim(
        plate: upperPlate,
        model: upperModel,
      );

      await loadData();

      showMessage(
        'Vehicle added. You can book appointment while waiting for admin confirmation.',
      );
    } catch (error) {
      showMessage('Failed to add vehicle: $error');
    }
  }

  Future<void> updateVehicle({
    required String vehicleId,
    required String plate,
    required String model,
  }) async {
    final upperPlate = plate.toUpperCase();
    final upperModel = model.toUpperCase();
    try {
      await supabase.from('vehicles').update({
        'plate_number': upperPlate,
        'car_model': upperModel,
        'verification_status': 'Pending Claim',
      }).eq('vehicle_id', vehicleId);

      await notifyAdminsVehicleClaim(
        plate: upperPlate,
        model: upperModel,
      );
      await loadData();
      showMessage('Vehicle updated. Status changed to Pending Claim.');
    } catch (error) {
      showMessage('Failed to update vehicle: $error');
    }
  }

  Future<void> deleteVehicle(String vehicleId) async {
    try {
      await supabase.from('vehicles').delete().eq('vehicle_id', vehicleId);

      await loadData();
      showMessage('Vehicle deleted successfully.');
    } catch (error) {
      showMessage('Failed to delete vehicle: $error');
    }
  }

  void showAddVehicleDialog() {
    final plateController = TextEditingController();
    final modelController = TextEditingController();

    showVehicleFormDialog(
      title: 'Add Vehicle',
      subtitle: 'Enter your vehicle information to create a booking profile.',
      plateController: plateController,
      modelController: modelController,
      buttonText: 'Add Vehicle',
      onSave: () async {
        final plate = plateController.text.trim();
        final model = modelController.text.trim();

        if (plate.isEmpty || model.isEmpty) {
          showMessage('Please complete vehicle information.');
          return;
        }

        Navigator.pop(context);

        await addVehicle(
          plate: plate,
          model: model,
        );
      },
    );
  }

  void showEditVehicleDialog(Map<String, dynamic> vehicle) {
    final plateController = TextEditingController(
      text: vehicle['plate_number'] ?? '',
    );

    final modelController = TextEditingController(
      text: vehicle['car_model'] ?? '',
    );

    showVehicleFormDialog(
      title: 'Edit Vehicle',
      subtitle: 'Update your vehicle information. Admin will verify again.',
      plateController: plateController,
      modelController: modelController,
      buttonText: 'Save Changes',
      onSave: () async {
        final plate = plateController.text.trim();
        final model = modelController.text.trim();

        if (plate.isEmpty || model.isEmpty) {
          showMessage('Please complete vehicle information.');
          return;
        }

        Navigator.pop(context);

        await updateVehicle(
          vehicleId: vehicle['vehicle_id'].toString(),
          plate: plate,
          model: model,
        );
      },
    );
  }

  void showVehicleFormDialog({
    required String title,
    required String subtitle,
    required TextEditingController plateController,
    required TextEditingController modelController,
    required String buttonText,
    required Future<void> Function() onSave,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 28,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7E5FA),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 32,
                          backgroundColor: Color(0xFF339BFF),
                          child: Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  buildInputBox(
                    controller: plateController,
                    label: 'Vehicle Plate Number',
                    hintText: 'Example: JSA9259',
                    icon: Icons.confirmation_number,
                  ),

                  const SizedBox(height: 16),

                  buildInputBox(
                    controller: modelController,
                    label: 'Car Model',
                    hintText: 'Example: HONDA CITY',
                    icon: Icons.directions_car,
                  ),

                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.35),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'New vehicles will be saved as Pending Claim. You can still book an appointment while waiting for admin confirmation.',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF339BFF),
                              side: const BorderSide(
                                color: Color(0xFF339BFF),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF339BFF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              await onSave();
                            },
                            child: Text(
                              buttonText,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
  }

  void showVehicleDetailDialog(Map<String, dynamic> vehicle) {
    final booking = vehicleBookings[vehicle['vehicle_id'].toString()];
    final status = vehicle['verification_status'] ?? 'Pending Claim';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Vehicle Details'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SizedBox(
            width: 330,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildDetailRow('Plate Number', vehicle['plate_number'] ?? ''),
                buildDetailRow('Car Model', vehicle['car_model'] ?? ''),
                buildDetailRow('Record Status', getDisplayStatus(status)),
                const SizedBox(height: 12),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Appointment Information',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                if (booking != null)
                  buildDetailRow(
                    'Appointment Date',
                    formatDate(booking['appointment_date'].toString()),
                  )
                else
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Appointment: None',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showEditVehicleDialog(vehicle);
              },
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showDeleteVehicleDialog(vehicle['vehicle_id'].toString());
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
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

  void showDeleteVehicleDialog(String vehicleId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Vehicle'),
          content: const Text('Are you sure you want to delete this vehicle?'),
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
                await deleteVehicle(vehicleId);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
  }) {
    return SizedBox(
      height: 76,
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          TextInputFormatter.withFunction((oldValue, newValue) {
            return newValue.copyWith(
              text: newValue.text.toUpperCase(),
              selection: newValue.selection,
            );
          }),
        ],
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(icon, color: const Color(0xFF339BFF)),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildDetailRow(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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

  Widget buildAppointmentText(Map<String, dynamic>? booking) {
    if (booking == null) {
      return const Text(
        'Appointment: None',
        style: TextStyle(
          color: Colors.black54,
          fontSize: 13,
        ),
      );
    }

    return Text(
      'Appointment Date: ${formatDate(booking['appointment_date'].toString())}',
      style: const TextStyle(
        color: Color(0xFF339BFF),
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: SizedBox(
        height: 42,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
            onPressed == null ? Colors.grey.shade300 : const Color(0xFF339BFF),
            foregroundColor: onPressed == null ? Colors.black45 : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildVehicleCard(Map<String, dynamic> vehicle) {
    final status = vehicle['verification_status'] ?? 'Pending Claim';
    final booking = vehicleBookings[vehicle['vehicle_id'].toString()];

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
          showVehicleDetailDialog(vehicle);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Color(0xFFD7E5FA),
                    child: Icon(
                      Icons.directions_car,
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
                        const SizedBox(height: 8),
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
                            getDisplayStatus(status),
                            style: TextStyle(
                              color: getStatusColor(status),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildAppointmentText(booking),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  buildActionButton(
                    icon: Icons.history,
                    label: 'Service Record',
                    onPressed: () {
                      goToServiceRecords(vehicle['plate_number'] ?? '');
                    },
                  ),
                  const SizedBox(width: 10),
                  buildActionButton(
                    icon: Icons.calendar_month,
                    label: 'Book Service',
                    onPressed: goToBookingPage,
                  ),
                ],
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
    final displayVehicles = filteredVehicles;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('My Vehicles'),
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
                      'My Vehicle List',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Manage your vehicles, service records and appointments',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.directions_car,
                          title: 'Vehicles',
                          value: '${vehicles.length}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.pending_actions,
                          title: 'Pending',
                          value: '$pendingClaimCount',
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
                        'Search by plate, model or status',
                        prefixIcon: const Icon(
                          Icons.search,
                        ),
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

            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),

            if (displayVehicles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    searchText.trim().isEmpty
                        ? 'No vehicles added yet.'
                        : 'No matching vehicles found.',
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
                      return buildVehicleCard(
                        displayVehicles[index],
                      );
                    },
                    childCount: displayVehicles.length,
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
              heroTag: 'myVehiclesBackToTop',
              backgroundColor: const Color(0xFF339BFF),
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
            heroTag: 'myVehiclesAddVehicle',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: showAddVehicleDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Vehicle'),
          ),
        ],
      ),
    );
  }
}