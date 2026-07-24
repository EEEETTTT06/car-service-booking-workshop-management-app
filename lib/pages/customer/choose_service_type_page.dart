import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../common/app_result_message.dart';

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

      final customerName =
          currentCustomer?['name'] ?? 'A customer';

      final plate =
          selectedVehicle?['plate_number'] ??
              'Unknown Vehicle';

      final bookingId =
      booking['booking_id']
          ?.toString()
          .trim();

      final vehicleId =
      selectedVehicle?['vehicle_id']
          ?.toString()
          .trim();

      final customerId =
      currentCustomer?['customer_id']
          ?.toString()
          .trim();

      const targetPage = 'admin_bookings';
      const notificationType = 'booking';

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

        await supabase
            .from('admin_notifications')
            .insert({
          'admin_id': admin['admin_id'],
          'title': title,
          'message': body,
          'is_read': false,
          'notification_type':
          notificationType,
          'target_page': targetPage,
          'booking_id': bookingId,
          'vehicle_id': vehicleId,
          'customer_id': customerId,
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
            'data': {
              'target_page': targetPage,
              'notification_type':
              notificationType,
              if (bookingId != null &&
                  bookingId.isNotEmpty)
                'booking_id': bookingId,
              if (vehicleId != null &&
                  vehicleId.isNotEmpty)
                'vehicle_id': vehicleId,
              if (customerId != null &&
                  customerId.isNotEmpty)
                'customer_id': customerId,
            },
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

    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final appointmentDateOnly = DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
    );

    if (!appointmentDateOnly.isAfter(today)) {
      showMessage(
        'Same-day booking is not available. '
            'Please select tomorrow or a later date.',
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

      AppResultMessage.success(
        context,
        message: 'Booking confirmed successfully.',
      );

      navigator.pop();
      navigator.pop();
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
      showMessage(
        'Please select at least one service.',
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final plateNumber =
            selectedVehicle!['plate_number']
                ?.toString() ??
                '';

        final carModel =
            selectedVehicle!['car_model']
                ?.toString() ??
                '';

        final notes =
        problemController.text.trim();

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
          const EdgeInsets.symmetric(
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
                  0.88,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color:
                    Colors.black.withOpacity(
                      0.16,
                    ),
                    blurRadius: 28,
                    offset:
                    const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding:
                    const EdgeInsets.fromLTRB(
                      18,
                      17,
                      10,
                      17,
                    ),
                    decoration:
                    const BoxDecoration(
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
                          width: 52,
                          height: 52,
                          decoration:
                          BoxDecoration(
                            color: Colors.white
                                .withOpacity(0.18),
                            borderRadius:
                            BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: const Icon(
                            Icons
                                .event_available_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                        ),
                        const SizedBox(width: 13),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Text(
                                'Confirm Booking',
                                style: TextStyle(
                                  color:
                                  Colors.white,
                                  fontSize: 19,
                                  fontWeight:
                                  FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Review the information before submitting',
                                style: TextStyle(
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
                          onPressed: isSubmitting
                              ? null
                              : () {
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
                    child:
                    SingleChildScrollView(
                      padding:
                      const EdgeInsets.all(
                        18,
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          buildConfirmationSection(
                            icon: Icons
                                .directions_car_rounded,
                            title:
                            'Vehicle & Appointment',
                            children: [
                              buildConfirmationRow(
                                title:
                                'Plate Number',
                                value:
                                plateNumber,
                              ),
                              buildConfirmationRow(
                                title: 'Car Model',
                                value: carModel,
                              ),
                              buildConfirmationRow(
                                title:
                                'Booking Date',
                                value: widget
                                    .selectedDate,
                                showDivider:
                                false,
                              ),
                            ],
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(
                              height: 13,
                            ),
                            buildConfirmationSection(
                              icon: Icons
                                  .description_outlined,
                              title:
                              'Problem / Notes',
                              children: [
                                Text(
                                  notes,
                                  style:
                                  const TextStyle(
                                    color: Color(
                                      0xFF374151,
                                    ),
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(
                            height: 13,
                          ),
                          buildConfirmationSection(
                            icon:
                            Icons.build_rounded,
                            title:
                            'Selected Services',
                            children: [
                              ...selectedServices.map(
                                    (service) {
                                  final price =
                                      double.tryParse(
                                        service[
                                        'price']
                                            .toString(),
                                      ) ??
                                          0;

                                  return Container(
                                    margin:
                                    const EdgeInsets
                                        .only(
                                      bottom: 9,
                                    ),
                                    padding:
                                    const EdgeInsets
                                        .all(
                                      12,
                                    ),
                                    decoration:
                                    BoxDecoration(
                                      color:
                                      const Color(
                                        0xFFF7F9FC,
                                      ),
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                        14,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons
                                              .check_circle_rounded,
                                          color: Color(
                                            0xFF339BFF,
                                          ),
                                          size: 20,
                                        ),
                                        const SizedBox(
                                          width: 9,
                                        ),
                                        Expanded(
                                          child: Text(
                                            service[
                                            'service_name']
                                                ?.toString() ??
                                                '',
                                            style:
                                            const TextStyle(
                                              color: Color(
                                                0xFF1F2937,
                                              ),
                                              fontSize:
                                              12.5,
                                              fontWeight:
                                              FontWeight
                                                  .w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 8,
                                        ),
                                        Text(
                                          'RM ${price.toStringAsFixed(2)}',
                                          style:
                                          const TextStyle(
                                            color: Color(
                                              0xFF339BFF,
                                            ),
                                            fontSize:
                                            12.5,
                                            fontWeight:
                                            FontWeight
                                                .bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: 13,
                          ),
                          Container(
                            width: double.infinity,
                            padding:
                            const EdgeInsets.all(
                              16,
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
                              border: Border.all(
                                color: const Color(
                                  0xFF339BFF,
                                ).withOpacity(0.18),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Estimated Total',
                                        style:
                                        TextStyle(
                                          color:
                                          Colors.black54,
                                          fontSize: 13,
                                          fontWeight:
                                          FontWeight
                                              .w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'RM ${totalPrice.toStringAsFixed(2)}',
                                      style:
                                      const TextStyle(
                                        color: Color(
                                          0xFF339BFF,
                                        ),
                                        fontSize: 20,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: 8,
                                ),
                                const Row(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    Icon(
                                      Icons
                                          .info_outline_rounded,
                                      color: Color(
                                        0xFF339BFF,
                                      ),
                                      size: 17,
                                    ),
                                    SizedBox(
                                      width: 7,
                                    ),
                                    Expanded(
                                      child: Text(
                                        'The final price may change after the workshop inspection.',
                                        style:
                                        TextStyle(
                                          color:
                                          Colors.black54,
                                          fontSize: 11,
                                          height: 1.35,
                                        ),
                                      ),
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
                          child:
                          OutlinedButton(
                            style:
                            OutlinedButton
                                .styleFrom(
                              foregroundColor:
                              const Color(
                                0xFF1F2937,
                              ),
                              side: BorderSide(
                                color: Colors
                                    .grey.shade300,
                              ),
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
                            onPressed:
                            isSubmitting
                                ? null
                                : () {
                              Navigator.pop(
                                dialogContext,
                              );
                            },
                            child:
                            const Text(
                              'Back',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
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
                            onPressed:
                            isSubmitting
                                ? null
                                : () async {
                              Navigator.pop(
                                dialogContext,
                              );
                              await confirmBooking();
                            },
                            icon:
                            isSubmitting
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                              CircularProgressIndicator(
                                strokeWidth: 2,
                                color:
                                Colors.white,
                              ),
                            )
                                : const Icon(
                              Icons
                                  .check_circle_outline_rounded,
                            ),
                            label: Text(
                              isSubmitting
                                  ? 'Saving...'
                                  : 'Confirm Booking',
                              style:
                              const TextStyle(
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
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
  }

  Widget buildConfirmationSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(0.035),
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
                  color:
                  const Color(0xFFEAF4FF),
                  borderRadius:
                  BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color:
                  const Color(0xFF339BFF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color:
                    Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ...children,
        ],
      ),
    );
  }

  Widget buildConfirmationRow({
    required String title,
    required String value,
    bool showDivider = true,
  }) {
    final displayValue =
    value.trim().isEmpty
        ? 'Not Provided'
        : value.trim();

    return Column(
      children: [
        Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight:
                  FontWeight.w600,
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
                  color:
                  Color(0xFF1F2937),
                  fontSize: 12,
                  fontWeight:
                  FontWeight.bold,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 10),
        ],
      ],
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
      margin:
      const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF339BFF)
              .withOpacity(0.16),
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(0.05),
            blurRadius: 11,
            offset: const Offset(0, 5),
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                  const Color(0xFFEAF4FF),
                  borderRadius:
                  BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons
                      .description_outlined,
                  color:
                  Color(0xFF339BFF),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Problem / Service Notes',
                      style: TextStyle(
                        color:
                        Color(0xFF1F2937),
                        fontWeight:
                        FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Help the workshop understand your request.',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: const Text(
                  'OPTIONAL',
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 9.5,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: problemController,
            maxLines: 4,
            maxLength: 300,
            textCapitalization:
            TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText:
              'Example: Engine noise, brake sound, aircond not cold, or warning light appeared...',
              hintStyle: const TextStyle(
                color: Colors.black38,
                fontSize: 12.5,
                height: 1.4,
              ),
              prefixIcon: const Padding(
                padding:
                EdgeInsets.only(bottom: 70),
                child: Icon(
                  Icons.edit_note_rounded,
                  color:
                  Color(0xFF339BFF),
                ),
              ),
              filled: true,
              fillColor:
              const Color(0xFFF7F9FC),
              counterStyle: const TextStyle(
                color: Colors.black38,
                fontSize: 10,
              ),
              border: OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder:
              OutlineInputBorder(
                borderRadius:
                BorderRadius.circular(16),
                borderSide:
                const BorderSide(
                  color:
                  Color(0xFF339BFF),
                  width: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildServiceCard(
      Map<String, dynamic> service,
      ) {
    final isAvailable =
    isServiceAvailable(service);

    final isSelected =
    selectedServices.any(
          (item) =>
      item['service_id'] ==
          service['service_id'],
    );

    final price =
        double.tryParse(
          service['price'].toString(),
        ) ??
            0;

    return AnimatedContainer(
      duration:
      const Duration(milliseconds: 180),
      margin:
      const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isAvailable
            ? Colors.white
            : Colors.grey.shade200,
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF339BFF)
              : const Color(0xFF339BFF)
              .withOpacity(0.08),
          width: isSelected ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFF339BFF)
                .withOpacity(0.11)
                : Colors.black.withOpacity(
              0.045,
            ),
            blurRadius:
            isSelected ? 14 : 9,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(22),
        onTap: () =>
            toggleService(service),
        child: Padding(
          padding:
          const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isAvailable
                      ? isSelected
                      ? const Color(
                    0xFF339BFF,
                  )
                      : const Color(
                    0xFFEAF4FF,
                  )
                      : Colors.grey.shade300,
                  borderRadius:
                  BorderRadius.circular(
                    17,
                  ),
                ),
                child: Icon(
                  Icons
                      .car_repair_rounded,
                  color: isAvailable
                      ? isSelected
                      ? Colors.white
                      : const Color(
                    0xFF339BFF,
                  )
                      : Colors.grey,
                  size: 27,
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
                      service[
                      'service_name']
                          ?.toString() ??
                          '',
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isAvailable
                            ? const Color(
                          0xFF1F2937,
                        )
                            : Colors.black45,
                        fontWeight:
                        FontWeight.bold,
                        fontSize: 15.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Row(
                      children: [
                        Container(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration:
                          BoxDecoration(
                            color:
                            getServiceStatusBackgroundColor(
                              isAvailable,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              20,
                            ),
                          ),
                          child: Row(
                            mainAxisSize:
                            MainAxisSize.min,
                            children: [
                              Icon(
                                isAvailable
                                    ? Icons
                                    .check_circle_outline_rounded
                                    : Icons
                                    .block_rounded,
                                color:
                                getServiceStatusColor(
                                  isAvailable,
                                ),
                                size: 13,
                              ),
                              const SizedBox(
                                width: 5,
                              ),
                              Text(
                                isAvailable
                                    ? 'Available'
                                    : 'Not Available',
                                style:
                                TextStyle(
                                  color:
                                  getServiceStatusColor(
                                    isAvailable,
                                  ),
                                  fontWeight:
                                  FontWeight
                                      .bold,
                                  fontSize: 10.5,
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
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment:
                CrossAxisAlignment.end,
                children: [
                  Text(
                    'RM ${price.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: isAvailable
                          ? const Color(
                        0xFF339BFF,
                      )
                          : Colors.black38,
                      fontSize: 14.5,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedContainer(
                    duration: const Duration(
                      milliseconds: 180,
                    ),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(
                        0xFF339BFF,
                      )
                          : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isAvailable
                            ? const Color(
                          0xFF339BFF,
                        )
                            : Colors.grey,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isSelected
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                      color: isSelected
                          ? Colors.white
                          : isAvailable
                          ? const Color(
                        0xFF339BFF,
                      )
                          : Colors.grey,
                      size: 19,
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

  Widget buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
          Colors.white.withOpacity(0.97),
          borderRadius:
          BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color:
              Colors.black.withOpacity(0.05),
              blurRadius: 9,
              offset:
              const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color:
                const Color(0xFFEAF4FF),
                borderRadius:
                BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color:
                const Color(0xFF339BFF),
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
                      color:
                      Color(0xFF1F2937),
                      fontSize: 21,
                      fontWeight:
                      FontWeight.bold,
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
                      fontWeight:
                      FontWeight.w600,
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

    AppResultMessage.show(
      context,
      message: message,
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
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                                    .looks_two_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'STEP 2 OF 2',
                                style: TextStyle(
                                  color:
                                  Colors.white,
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
                    const SizedBox(height: 11),
                    const Text(
                      'Select Your Service',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose your vehicle and the services required.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withOpacity(0.16),
                        borderRadius:
                        BorderRadius.circular(
                          14,
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons
                                .calendar_month_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            widget.selectedDate,
                            style:
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons
                              .home_repair_service_rounded,
                          title:
                          'Available Services',
                          value:
                          '$availableCount',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons
                              .check_circle_rounded,
                          title:
                          'Selected Services',
                          value:
                          '${selectedServices.length}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding:
                      const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                        BorderRadius.circular(
                          19,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(0.06),
                            blurRadius: 10,
                            offset:
                            const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons
                                    .directions_car_rounded,
                                color: Color(
                                  0xFF339BFF,
                                ),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Select Vehicle',
                                style: TextStyle(
                                  color: Color(
                                    0xFF1F2937,
                                  ),
                                  fontSize: 14,
                                  fontWeight:
                                  FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (vehicles.isEmpty)
                            Container(
                              width: double.infinity,
                              padding:
                              const EdgeInsets.all(
                                13,
                              ),
                              decoration:
                              BoxDecoration(
                                color:
                                Colors.orange.shade50,
                                borderRadius:
                                BorderRadius.circular(
                                  14,
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons
                                        .warning_amber_rounded,
                                    color:
                                    Colors.orange,
                                  ),
                                  SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      'No vehicle is linked to this account.',
                                      style:
                                      TextStyle(
                                        color:
                                        Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            DropdownButtonFormField<
                                String>(
                              value: selectedVehicle?[
                              'vehicle_id'],
                              isExpanded: true,
                              decoration:
                              InputDecoration(
                                prefixIcon:
                                const Icon(
                                  Icons
                                      .garage_rounded,
                                  color: Color(
                                    0xFF339BFF,
                                  ),
                                ),
                                filled: true,
                                fillColor:
                                const Color(
                                  0xFFF7F9FC,
                                ),
                                contentPadding:
                                const EdgeInsets
                                    .symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                                border:
                                OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius
                                      .circular(
                                    15,
                                  ),
                                  borderSide:
                                  BorderSide.none,
                                ),
                                focusedBorder:
                                OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius
                                      .circular(
                                    15,
                                  ),
                                  borderSide:
                                  const BorderSide(
                                    color: Color(
                                      0xFF339BFF,
                                    ),
                                  ),
                                ),
                              ),
                              items:
                              vehicles.map(
                                    (vehicle) {
                                  return DropdownMenuItem<
                                      String>(
                                    value: vehicle[
                                    'vehicle_id'],
                                    child: Text(
                                      '${vehicle['plate_number']}  •  '
                                          '${vehicle['car_model']}',
                                      overflow:
                                      TextOverflow
                                          .ellipsis,
                                      style:
                                      const TextStyle(
                                        color: Color(
                                          0xFF1F2937,
                                        ),
                                        fontWeight:
                                        FontWeight
                                            .w600,
                                      ),
                                    ),
                                  );
                                },
                              ).toList(),
                              onChanged: (value) {
                                setState(() {
                                  selectedVehicle =
                                      vehicles
                                          .firstWhere(
                                            (vehicle) =>
                                        vehicle[
                                        'vehicle_id'] ==
                                            value,
                                      );
                                });
                              },
                            ),
                        ],
                      ),
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
                  margin:
                  const EdgeInsets.fromLTRB(
                    16,
                    6,
                    16,
                    0,
                  ),
                  padding:
                  const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.circular(
                      22,
                    ),
                    border: Border.all(
                      color:
                      const Color(0xFF339BFF)
                          .withOpacity(0.12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withOpacity(0.07),
                        blurRadius: 14,
                        offset:
                        const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration:
                            BoxDecoration(
                              color: const Color(
                                0xFFEAF4FF,
                              ),
                              borderRadius:
                              BorderRadius
                                  .circular(
                                13,
                              ),
                            ),
                            child: const Icon(
                              Icons
                                  .receipt_long_rounded,
                              color: Color(
                                0xFF339BFF,
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                              children: [
                                Text(
                                  '${selectedServices.length} service(s) selected',
                                  style:
                                  const TextStyle(
                                    color: Color(
                                      0xFF1F2937,
                                    ),
                                    fontSize: 12.5,
                                    fontWeight:
                                    FontWeight
                                        .w600,
                                  ),
                                ),
                                const SizedBox(
                                  height: 3,
                                ),
                                const Text(
                                  'Estimated Total',
                                  style:
                                  TextStyle(
                                    color:
                                    Colors.black45,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'RM ${totalPrice.toStringAsFixed(2)}',
                            style:
                            const TextStyle(
                              color: Color(
                                0xFF339BFF,
                              ),
                              fontWeight:
                              FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
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
                            elevation: 0,
                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius
                                  .circular(
                                16,
                              ),
                            ),
                          ),
                          onPressed:
                          isSubmitting
                              ? null
                              : showConfirmBookingDialog,
                          icon: isSubmitting
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                            CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                              Colors.white,
                            ),
                          )
                              : const Icon(
                            Icons
                                .calendar_month_rounded,
                          ),
                          label: Text(
                            isSubmitting
                                ? 'Creating Booking...'
                                : 'Review & Book Service',
                            style:
                            const TextStyle(
                              fontWeight:
                              FontWeight.bold,
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