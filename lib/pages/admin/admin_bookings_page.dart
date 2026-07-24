import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_sidebar.dart';
import 'admin_appointment_calendar_page.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../../services/customer_notification_service.dart';
import '../common/app_result_message.dart';

class AdminBookingsPage extends StatefulWidget {
  final String? initialBookingId;

  const AdminBookingsPage({
    super.key,
    this.initialBookingId,
  });

  @override
  State<AdminBookingsPage> createState() =>
      _AdminBookingsPageState();
}

class _AdminBookingsPageState extends State<AdminBookingsPage> {
  String selectedFilter = 'Today';
  String selectedSort = 'Nearest';
  String searchText = '';
  bool isLoading = false;

  final TextEditingController searchController =
  TextEditingController();

  String? highlightedBookingId;
  bool initialBookingHandled = false;

  final Map<String, GlobalKey> bookingCardKeys = {};
  bool isProcessingArrival = false;

  List<Map<String, dynamic>> bookings = [];
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  RealtimeChannel? bookingsRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    final initialBookingId =
    widget.initialBookingId?.trim();

    if (initialBookingId != null &&
        initialBookingId.isNotEmpty) {
      highlightedBookingId = initialBookingId;
    }

    fetchBookings();
    setupRealtimeSubscription();

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
    realtimeRefreshTimer?.cancel();

    final channel = bookingsRealtimeChannel;

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
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  Future<void> fetchBookings({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final response = await supabase
          .from('bookings')
          .select('''
          *,
          customers(name, phone, email, fcm_token),
          vehicles(plate_number, car_model),
          booking_services(
            services(service_name, price)
          )
        ''')
          .order(
        'appointment_date',
        ascending: true,
      );

      if (!mounted) return;

      setState(() {
        bookings =
        List<Map<String, dynamic>>.from(
          response,
        );
      });

      scheduleInitialBookingFocus();
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load bookings: $error',
        );
      } else {
        debugPrint(
          'Realtime booking refresh failed: $error',
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
  void scheduleInitialBookingFocus() {
    final bookingId =
    highlightedBookingId?.trim();

    if (initialBookingHandled ||
        bookingId == null ||
        bookingId.isEmpty ||
        bookings.isEmpty) {
      return;
    }

    Map<String, dynamic>? matchedBooking;

    for (final booking in bookings) {
      if (booking['booking_id']
          ?.toString()
          .trim() ==
          bookingId) {
        matchedBooking = booking;
        break;
      }
    }

    if (matchedBooking == null) {
      initialBookingHandled = true;

      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        if (!mounted) return;

        AppResultMessage.info(
          context,
          message:
          'The related booking could not be found. It may have been deleted or changed.',
        );
      });

      return;
    }

    final appointmentDate = parseBookingDate(
      matchedBooking['appointment_date']
          .toString(),
    );

    final bookingOnlyDate = DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
    );

    final requiredFilter =
    bookingOnlyDate.isBefore(today)
        ? 'Past'
        : bookingOnlyDate
        .isAtSameMomentAs(today)
        ? 'Today'
        : 'Future';

    searchController.clear();

    setState(() {
      selectedFilter = requiredFilter;
      selectedSort = 'Nearest';
      searchText = '';
      highlightedBookingId = bookingId;
    });

    initialBookingHandled = true;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      focusAndOpenBooking(
        bookingId,
        matchedBooking!,
      );
    });
  }

  Future<void> focusAndOpenBooking(
      String bookingId,
      Map<String, dynamic> booking,
      ) async {
    await Future<void>.delayed(
      const Duration(milliseconds: 220),
    );

    if (!mounted) return;

    final cardContext =
        bookingCardKeys[bookingId]
            ?.currentContext;

    if (cardContext != null) {
      await Scrollable.ensureVisible(
        cardContext,
        duration:
        const Duration(milliseconds: 650),
        curve: Curves.easeInOut,
        alignment: 0.22,
      );
    }

    await Future<void>.delayed(
      const Duration(milliseconds: 220),
    );

    if (!mounted) return;

    showBookingDetails(
      booking,
      openedFromNotification: true,
    );
  }

  void clearBookingHighlight() {
    if (highlightedBookingId == null) {
      return;
    }

    setState(() {
      highlightedBookingId = null;
    });
  }

  void setupRealtimeSubscription() {
    if (bookingsRealtimeChannel != null) {
      return;
    }

    bookingsRealtimeChannel = supabase
        .channel('admin-bookings-realtime')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      callback: (payload) {
        debugPrint(
          'Admin booking changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'booking_services',
      callback: (payload) {
        debugPrint(
          'Booking service changed: '
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
      refreshBookingsFromRealtime,
    );
  }

  Future<void> refreshBookingsFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await fetchBookings(
        showLoading: false,
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }


  DateTime get today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime parseBookingDate(String date) => DateTime.parse(date);

  String formatDate(String date) {
    final parsedDate = DateTime.parse(date);
    return '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}';
  }

  List<Map<String, dynamic>> getServices(Map<String, dynamic> booking) {
    final bookingServices = booking['booking_services'] as List? ?? [];

    return bookingServices.map<Map<String, dynamic>>((item) {
      final service = item['services'] ?? {};
      return Map<String, dynamic>.from(service);
    }).toList();
  }

  double getTotalPrice(Map<String, dynamic> booking) {
    double total = 0;

    for (final service in getServices(booking)) {
      total += double.tryParse(service['price'].toString()) ?? 0;
    }

    return total;
  }

  List<Map<String, dynamic>> get filteredBookings {
    final filtered = bookings.where((booking) {
      final appointmentDate =
      parseBookingDate(booking['appointment_date'].toString());

      final bookingOnlyDate = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );

      bool matchFilter = false;

      if (selectedFilter == 'Past') {
        matchFilter = bookingOnlyDate.isBefore(today);
      } else if (selectedFilter == 'Today') {
        matchFilter = bookingOnlyDate.isAtSameMomentAs(today);
      } else {
        matchFilter = bookingOnlyDate.isAfter(today);
      }

      final customerName =
      (booking['customers']?['name'] ?? '').toString().toLowerCase();

      final plate =
      (booking['vehicles']?['plate_number'] ?? '').toString().toLowerCase();

      final model =
      (booking['vehicles']?['car_model'] ?? '').toString().toLowerCase();

      final serviceText = getServices(booking)
          .map((service) => service['service_name'].toString().toLowerCase())
          .join(' ');

      final search = searchText.toLowerCase();

      final matchSearch = customerName.contains(search) ||
          plate.contains(search) ||
          model.contains(search) ||
          serviceText.contains(search);

      return matchFilter && matchSearch;
    }).toList();

    filtered.sort((a, b) {
      final aDate = parseBookingDate(a['appointment_date'].toString());
      final bDate = parseBookingDate(b['appointment_date'].toString());

      if (selectedSort == 'Nearest') {
        if (selectedFilter == 'Past') {
          return bDate.compareTo(aDate);
        }
        return aDate.compareTo(bDate);
      }

      if (selectedFilter == 'Past') {
        return aDate.compareTo(bDate);
      }
      return bDate.compareTo(aDate);
    });

    return filtered;
  }

  int get pastCount {
    return bookings.where((booking) {
      final appointmentDate =
      parseBookingDate(booking['appointment_date'].toString());

      final bookingOnlyDate = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );

      return bookingOnlyDate.isBefore(today);
    }).length;
  }

  int get todayCount {
    return bookings.where((booking) {
      final appointmentDate =
      parseBookingDate(booking['appointment_date'].toString());

      final bookingOnlyDate = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );

      return bookingOnlyDate.isAtSameMomentAs(today);
    }).length;
  }

  int get futureCount {
    return bookings.where((booking) {
      final appointmentDate =
      parseBookingDate(booking['appointment_date'].toString());

      final bookingOnlyDate = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );

      return bookingOnlyDate.isAfter(today);
    }).length;
  }

  Color getStatusColor(String status) {
    if (status == 'Booked') return Colors.blue;
    if (status == 'Approved') return Colors.green;
    if (status == 'Rejected') return Colors.red;
    if (status == 'Arrived') return Colors.orange;
    if (status == 'Completed') return Colors.green;
    if (status == 'Cancelled') return Colors.red;
    return Colors.grey;
  }

  Color getStatusBackgroundColor(String status) {
    if (status == 'Booked') return Colors.blue.shade50;
    if (status == 'Approved') return Colors.green.shade50;
    if (status == 'Rejected') return Colors.red.shade50;
    if (status == 'Arrived') return Colors.orange.shade50;
    if (status == 'Completed') return Colors.green.shade50;
    if (status == 'Cancelled') return Colors.red.shade50;
    return Colors.grey.shade100;
  }

  Future<void> sendFcmPushNotification({
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

  Future<void> createBookingNotification({
    required Map<String, dynamic> booking,
    required String title,
    required String message,
  }) async {
    final customerId = booking['customer_id'];

    if (customerId == null) return;

    await supabase.from('notifications').insert({
      'customer_id': customerId,
      'booking_id': booking['booking_id'],
      'vehicle_id': booking['vehicle_id'],
      'title': title,
      'message': message,
      'notification_type': 'booking',
      'target_page': 'my_bookings',
      'is_read': false,
    });

    await sendFcmPushNotification(
      customerId: customerId.toString(),
      title: title,
      message: message,
      data: {
        'notification_type': 'booking',
        'target_page': 'my_bookings',
        'booking_id': booking['booking_id'],
        'vehicle_id': booking['vehicle_id'],
      },
    );
  }

  Future<bool> showActionConfirmation({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
    IconData icon = Icons.help_outline,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: confirmColor.withOpacity(0.12),
                child: Icon(icon, color: confirmColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> confirmCustomerArrived(
      Map<String, dynamic> booking,
      ) async {
    final vehicle = booking['vehicles'] ?? <String, dynamic>{};
    final plate = vehicle['plate_number']?.toString().trim() ?? '';
    final model = vehicle['car_model']?.toString().trim() ?? '';
    final displayPlate = plate.isEmpty ? 'Not Provided' : plate;
    final displayModel = model.isEmpty ? 'Not Provided' : model;

    final confirmed = await showActionConfirmation(
      title: 'Confirm Vehicle Arrival',
      message:
      'Please physically check the plate number before continuing.\n\n'
          'Plate Number: $displayPlate\n'
          'Car Model: $displayModel\n\n'
          'Confirm that this booked vehicle has arrived and move it to Pending Services?',
      confirmText: 'Arrived: $displayPlate',
      confirmColor: Colors.orange,
      icon: Icons.directions_car,
    );

    if (!confirmed) return;

    await markCustomerArrived(booking);
  }

  Future<void> markCustomerArrived(
      Map<String, dynamic> booking,
      ) async {
    if (isProcessingArrival) return;

    final bookingId =
    booking['booking_id']
        ?.toString()
        .trim();

    if (bookingId == null ||
        bookingId.isEmpty) {
      showMessage(
        'Booking information is missing.',
      );
      return;
    }

    if (mounted) {
      setState(() {
        isProcessingArrival = true;
      });
    }

    try {
      final rpcResult = await supabase.rpc(
        'mark_booking_arrived',
        params: {
          'p_booking_id': bookingId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid arrival information was returned.',
        );
      }

      final arrivalResult =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final pendingId =
      arrivalResult['pending_id']
          ?.toString();

      if (pendingId == null ||
          pendingId.isEmpty) {
        throw Exception(
          'Pending Service ID was not returned.',
        );
      }

      final customerId =
          arrivalResult['customer_id'] ??
              booking['customer_id'];

      final vehicleId =
          arrivalResult['vehicle_id'] ??
              booking['vehicle_id'];

      final notificationBooking =
      Map<String, dynamic>.from(
        booking,
      );

      notificationBooking['booking_id'] =
          arrivalResult['booking_id'] ??
              bookingId;

      notificationBooking['customer_id'] =
          customerId;

      notificationBooking['vehicle_id'] =
          vehicleId;


      final plate =
          booking['vehicles']
          ?['plate_number']
              ?.toString() ??
              'your vehicle';

      if (customerId != null) {
        try {
          await createBookingNotification(
            booking: notificationBooking,
            title: 'Vehicle Arrived',
            message:
            'Your vehicle $plate has arrived at the workshop and is waiting for inspection and repair.',
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

      await fetchBookings(
        showLoading: false,
      );

      showMessage(
        'Customer marked as arrived and moved to pending service.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await fetchBookings(
        showLoading: false,
      );
    } catch (error) {
      showMessage(
        'Failed to mark customer arrived: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isProcessingArrival = false;
        });
      }
    }
  }

  void showBookingDetails(
      Map<String, dynamic> booking, {
        bool openedFromNotification = false,
      }) {
    final customerName =
        booking['customers']?['name']
            ?.toString()
            .trim() ??
            'Not Provided';

    final customerPhone =
        booking['customers']?['phone']
            ?.toString()
            .trim() ??
            'Not Provided';

    final customerEmail =
        booking['customers']?['email']
            ?.toString()
            .trim() ??
            'Not Provided';

    final vehiclePlate =
        booking['vehicles']?['plate_number']
            ?.toString()
            .trim() ??
            '';

    final vehicleModel =
        booking['vehicles']?['car_model']
            ?.toString()
            .trim() ??
            '';

    final date = formatDate(
      booking['appointment_date'].toString(),
    );

    final problem =
        booking['problem_description']
            ?.toString()
            .trim() ??
            '';

    final services = getServices(booking);
    final total = getTotalPrice(booking);

    final status =
        booking['status']?.toString() ??
            'Booked';

    final rejectionReason =
    booking['rejection_reason']
        ?.toString()
        .trim();

    final statusColor =
    getStatusColor(status);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 22,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight:
              MediaQuery.of(dialogContext)
                  .size
                  .height *
                  0.9,
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
                      0.18,
                    ),
                    blurRadius: 30,
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
                          width: 54,
                          height: 54,
                          decoration:
                          BoxDecoration(
                            color: Colors.white
                                .withOpacity(0.18),
                            borderRadius:
                            BorderRadius.circular(
                              17,
                            ),
                          ),
                          child: const Icon(
                            Icons
                                .event_note_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              const Text(
                                'Booking Details',
                                style: TextStyle(
                                  color:
                                  Colors.white,
                                  fontSize: 19,
                                  fontWeight:
                                  FontWeight.bold,
                                ),
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                openedFromNotification
                                    ? 'Opened from the related notification'
                                    : '$vehiclePlate • $date',
                                maxLines: 1,
                                overflow:
                                TextOverflow
                                    .ellipsis,
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
                    child:
                    SingleChildScrollView(
                      padding:
                      const EdgeInsets.all(
                        17,
                      ),
                      child: Column(
                        children: [
                          if (openedFromNotification)
                            Container(
                              width: double.infinity,
                              margin:
                              const EdgeInsets
                                  .only(
                                bottom: 13,
                              ),
                              padding:
                              const EdgeInsets
                                  .all(
                                13,
                              ),
                              decoration:
                              BoxDecoration(
                                color: const Color(
                                  0xFFEAF4FF,
                                ),
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  16,
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons
                                        .notifications_active_outlined,
                                    color: Color(
                                      0xFF339BFF,
                                    ),
                                    size: 20,
                                  ),
                                  SizedBox(
                                    width: 9,
                                  ),
                                  Expanded(
                                    child: Text(
                                      'This is the booking linked to the notification you selected.',
                                      style:
                                      TextStyle(
                                        color: Color(
                                          0xFF1F2937,
                                        ),
                                        fontSize: 11.5,
                                        fontWeight:
                                        FontWeight
                                            .w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          buildBookingDialogSection(
                            icon:
                            Icons.person_outline,
                            title:
                            'Customer Information',
                            children: [
                              buildBookingDialogRow(
                                title: 'Customer',
                                value:
                                customerName,
                              ),
                              buildBookingDialogRow(
                                title: 'Phone',
                                value:
                                customerPhone,
                              ),
                              buildBookingDialogRow(
                                title: 'Email',
                                value:
                                customerEmail,
                                showDivider:
                                false,
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: 13,
                          ),
                          buildBookingDialogSection(
                            icon: Icons
                                .directions_car_outlined,
                            title:
                            'Appointment Information',
                            children: [
                              buildBookingDialogRow(
                                title: 'Vehicle',
                                value:
                                '$vehiclePlate • $vehicleModel',
                              ),
                              buildBookingDialogRow(
                                title:
                                'Appointment Date',
                                value: date,
                              ),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Status',
                                      style:
                                      TextStyle(
                                        color:
                                        Colors.black54,
                                        fontSize: 12,
                                        fontWeight:
                                        FontWeight
                                            .w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding:
                                    const EdgeInsets
                                        .symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration:
                                    BoxDecoration(
                                      color:
                                      getStatusBackgroundColor(
                                        status,
                                      ),
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                        20,
                                      ),
                                    ),
                                    child: Text(
                                      status,
                                      style:
                                      TextStyle(
                                        color:
                                        statusColor,
                                        fontSize: 10.5,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (problem.isNotEmpty) ...[
                            const SizedBox(
                              height: 13,
                            ),
                            buildBookingDialogSection(
                              icon: Icons
                                  .description_outlined,
                              title:
                              'Problem / Notes',
                              children: [
                                Text(
                                  problem,
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
                          if (rejectionReason !=
                              null &&
                              rejectionReason
                                  .isNotEmpty) ...[
                            const SizedBox(
                              height: 13,
                            ),
                            Container(
                              width: double.infinity,
                              padding:
                              const EdgeInsets
                                  .all(
                                14,
                              ),
                              decoration:
                              BoxDecoration(
                                color: Colors
                                    .red.shade50,
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  17,
                                ),
                                border: Border.all(
                                  color: Colors.red
                                      .withOpacity(
                                    0.16,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                                children: [
                                  const Icon(
                                    Icons
                                        .cancel_outlined,
                                    color:
                                    Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(
                                    width: 9,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                      children: [
                                        const Text(
                                          'Rejection Reason',
                                          style:
                                          TextStyle(
                                            color:
                                            Colors.red,
                                            fontSize:
                                            12.5,
                                            fontWeight:
                                            FontWeight
                                                .bold,
                                          ),
                                        ),
                                        const SizedBox(
                                          height: 5,
                                        ),
                                        Text(
                                          rejectionReason,
                                          style:
                                          const TextStyle(
                                            color:
                                            Color(
                                              0xFF7F1D1D,
                                            ),
                                            fontSize:
                                            12,
                                            height:
                                            1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(
                            height: 13,
                          ),
                          buildBookingDialogSection(
                            icon:
                            Icons.build_outlined,
                            title:
                            'Selected Services',
                            children: [
                              if (services.isEmpty)
                                buildServiceItem(
                                  'No service found',
                                  0,
                                )
                              else
                                ...services.map(
                                      (service) {
                                    final price =
                                        double.tryParse(
                                          service[
                                          'price']
                                              .toString(),
                                        ) ??
                                            0;

                                    return buildServiceItem(
                                      service[
                                      'service_name']
                                          ?.toString() ??
                                          '',
                                      price,
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
                            const EdgeInsets
                                .all(
                              16,
                            ),
                            decoration:
                            BoxDecoration(
                              color: const Color(
                                0xFFEAF4FF,
                              ),
                              borderRadius:
                              BorderRadius
                                  .circular(
                                18,
                              ),
                            ),
                            child: Row(
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
                                  'RM ${total.toStringAsFixed(2)}',
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
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );

                          if (openedFromNotification) {
                            clearBookingHighlight();
                          }
                        },
                        icon: const Icon(
                          Icons.check_rounded,
                        ),
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
          ),
        );
      },
    );
  }

  Widget buildBookingDialogSection({
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
            offset:
            const Offset(0, 3),
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
                  color:
                  const Color(0xFF339BFF),
                  size: 19,
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

  Widget buildBookingDialogRow({
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

  Widget buildServiceItem(
      String name,
      double price,
      ) {
    return Container(
      margin:
      const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius:
        BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color:
              const Color(0xFFEAF4FF),
              borderRadius:
              BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.build_rounded,
              color:
              Color(0xFF339BFF),
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color:
                Color(0xFF1F2937),
                fontSize: 12.5,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
          Text(
            'RM ${price.toStringAsFixed(2)}',
            style: const TextStyle(
              color:
              Color(0xFF339BFF),
              fontSize: 12.5,
              fontWeight:
              FontWeight.bold,
            ),
          ),
        ],
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
              value.toString().isEmpty ? 'Not Provided' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildServiceChip(String name) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFD7E5FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Color(0xFF1F2937),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget buildFilterButton(String title) {
    final bool isSelected = selectedFilter == title;

    Color color = const Color(0xFF339BFF);
    if (title == 'Past') color = Colors.red;
    if (title == 'Today') color = const Color(0xFF339BFF);
    if (title == 'Future') color = Colors.green;

    return Expanded(
      child: SizedBox(
        height: 40,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? color : Colors.white,
            foregroundColor: isSelected ? Colors.white : color,
            elevation: isSelected ? 2 : 0,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: color.withOpacity(isSelected ? 1 : 0.30),
              ),
            ),
          ),
          onPressed: () {
            if (selectedFilter == title) return;

            setState(() {
              selectedFilter = title;
              highlightedBookingId = null;
            });
          },
          child: FittedBox(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSortControl() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF339BFF).withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.sort_rounded,
            color: Color(0xFF339BFF),
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sort by date',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedSort,
              borderRadius: BorderRadius.circular(14),
              items: const [
                DropdownMenuItem(
                  value: 'Nearest',
                  child: Text('Nearest First'),
                ),
                DropdownMenuItem(
                  value: 'Furthest',
                  child: Text('Furthest First'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  selectedSort = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    Color color = const Color(0xFF339BFF);

    if (title == 'Past') color = Colors.red;
    if (title == 'Today') color = const Color(0xFF339BFF);
    if (title == 'Future') color = Colors.green;

    return Expanded(
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBookingCard(
      Map<String, dynamic> booking,
      ) {
    final bookingId =
        booking['booking_id']
            ?.toString()
            .trim() ??
            '';

    final isHighlighted =
        bookingId.isNotEmpty &&
            highlightedBookingId ==
                bookingId;

    final cardKey =
    bookingCardKeys.putIfAbsent(
      bookingId,
          () => GlobalKey(),
    );

    final status =
        booking['status'] ?? 'Booked';

    final customerName =
        booking['customers']?['name'] ??
            'Not Provided';
    final vehiclePlate = booking['vehicles']?['plate_number'] ?? '';
    final vehicleModel = booking['vehicles']?['car_model'] ?? '';
    final date = formatDate(booking['appointment_date'].toString());
    final services = getServices(booking);
    final rejectionReason = booking['rejection_reason'];

    return AnimatedContainer(
      key: cardKey,
      duration:
      const Duration(milliseconds: 260),
      margin:
      const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFF5FAFF)
            : Colors.white,
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFF339BFF)
              : const Color(0xFF339BFF)
              .withOpacity(0.08),
          width: isHighlighted ? 2.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? const Color(0xFF339BFF)
                .withOpacity(0.18)
                : Colors.black
                .withOpacity(0.07),
            blurRadius:
            isHighlighted ? 19 : 14,
            offset:
            const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          showBookingDetails(booking);
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isHighlighted) ...[
                Container(
                  width: double.infinity,
                  margin:
                  const EdgeInsets.only(
                    bottom: 13,
                  ),
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color:
                    const Color(0xFFEAF4FF),
                    borderRadius:
                    BorderRadius.circular(
                      14,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons
                            .notifications_active_rounded,
                        color:
                        Color(0xFF339BFF),
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'BOOKING FROM NOTIFICATION',
                          style: TextStyle(
                            color:
                            Color(0xFF339BFF),
                            fontSize: 10.5,
                            fontWeight:
                            FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFFD7E5FA),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: Color(0xFF339BFF),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
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
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_car,
                          size: 17,
                          color: Color(0xFF339BFF),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$vehiclePlate • $vehicleModel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.event,
                          size: 17,
                          color: Color(0xFF339BFF),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          date,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (status == 'Rejected' &&
                  rejectionReason != null &&
                  rejectionReason.toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Reason: $rejectionReason',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              Wrap(
                children: services.isEmpty
                    ? [buildServiceChip('No service found')]
                    : services
                    .map(
                      (service) =>
                      buildServiceChip(service['service_name'] ?? ''),
                )
                    .toList(),
              ),

              const SizedBox(height: 16),

              if (status == 'Booked' ||
                  status == 'Approved') ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(
                    bottom: 11,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4FF),
                    borderRadius:
                    BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF339BFF)
                          .withOpacity(0.16),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.event_available_outlined,
                        color: Color(0xFF339BFF),
                        size: 20,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Booking confirmed. Confirm arrival only when the vehicle reaches the workshop.',
                          style: TextStyle(
                            color: Color(0xFF1F2937),
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight:
                            FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: isProcessingArrival
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(
                      Icons.directions_car,
                      size: 18,
                    ),
                    label: Text(
                      isProcessingArrival
                          ? 'Updating Arrival...'
                          : 'Customer Arrived',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      Colors.orange,
                      foregroundColor:
                      Colors.white,
                      padding:
                      const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: isProcessingArrival
                        ? null
                        : () {
                      confirmCustomerArrived(
                        booking,
                      );
                    },
                  ),
                ),
              ],

              if (status == 'Rejected')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.red,
                        size: 19,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is an old rejected booking record. Approval actions have been removed.',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 11.5,
                            fontWeight:
                            FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (status == 'Arrived')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'Vehicle moved to Pending Service',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              if (status == 'Completed')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'Service Completed',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
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

  Widget buildTopOverview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF339BFF),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Manage confirmed bookings and vehicle arrivals',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.route_outlined,
                  color: Colors.white,
                  size: 19,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Booked → Customer Arrived → Pending Service → Completed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              buildSummaryCard(
                icon: Icons.history,
                title: 'Past',
                value: '$pastCount',
              ),
              const SizedBox(width: 10),
              buildSummaryCard(
                icon: Icons.today,
                title: 'Today',
                value: '$todayCount',
              ),
              const SizedBox(width: 10),
              buildSummaryCard(
                icon: Icons.upcoming,
                title: 'Future',
                value: '$futureCount',
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {
                  searchText = value;
                  highlightedBookingId = null;
                });
              },
              decoration: const InputDecoration(
                hintText: 'Search customer, plate, model or service',
                prefixIcon: Icon(Icons.search),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCalendarShortcut() {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AdminAppointmentCalendarPage(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
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
        child: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFFD7E5FA),
              child: Icon(
                Icons.calendar_month_rounded,
                color: Color(0xFF339BFF),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Appointment Calendar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayBookings = filteredBookings;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Bookings'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,

        leading: IconButton(
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

        actions: const [
          NotificationBell(
            isAdmin: true,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: fetchBookings,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: buildTopOverview(),
            ),

            SliverPersistentHeader(
              pinned: true,
              delegate: _BookingStickyHeaderDelegate(
                child: Container(
                  color: const Color(0xFFD7E5FA),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    children: [
                      buildCalendarShortcut(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          buildFilterButton('Past'),
                          const SizedBox(width: 8),
                          buildFilterButton('Today'),
                          const SizedBox(width: 8),
                          buildFilterButton('Future'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      buildSortControl(),
                    ],
                  ),
                ),
              ),
            ),

            if (displayBookings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Container(
                    margin:
                    const EdgeInsets.all(24),
                    padding:
                    const EdgeInsets
                        .symmetric(
                      horizontal: 26,
                      vertical: 34,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(
                        22,
                      ),
                      border: Border.all(
                        color:
                        const Color(
                          0xFF339BFF,
                        ).withOpacity(0.10),
                      ),
                    ),
                    child: Column(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          decoration:
                          BoxDecoration(
                            color: const Color(
                              0xFFEAF4FF,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              23,
                            ),
                          ),
                          child: const Icon(
                            Icons
                                .event_busy_outlined,
                            color: Color(
                              0xFF339BFF,
                            ),
                            size: 35,
                          ),
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        Text(
                          'No $selectedFilter Bookings',
                          textAlign:
                          TextAlign.center,
                          style:
                          const TextStyle(
                            color:
                            Color(0xFF1F2937),
                            fontSize: 18,
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 7,
                        ),
                        const Text(
                          'Try another date filter or update the search keyword.',
                          textAlign:
                          TextAlign.center,
                          style: TextStyle(
                            color:
                            Colors.black54,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildBookingCard(displayBookings[index]);
                    },
                    childCount: displayBookings.length,
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

class _BookingStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _BookingStickyHeaderDelegate({
    required this.child,
  });

  @override
  double get minExtent => 216;

  @override
  double get maxExtent => 216;

  @override
  Widget build(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
      ) {
    return child;
  }

  @override
  bool shouldRebuild(_BookingStickyHeaderDelegate oldDelegate) {
    return true;
  }
}