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
  const AdminBookingsPage({super.key});

  @override
  State<AdminBookingsPage> createState() => _AdminBookingsPageState();
}

class _AdminBookingsPageState extends State<AdminBookingsPage> {
  String selectedFilter = 'Today';
  String selectedSort = 'Nearest';
  String searchText = '';
  bool isLoading = false;
  bool isProcessingDecision = false;

  List<Map<String, dynamic>> bookings = [];
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  RealtimeChannel? bookingsRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

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

  Future<void> confirmApproveAppointment(
      Map<String, dynamic> booking,
      ) async {
    final isRejected = booking['status'] == 'Rejected';

    final confirmed = await showActionConfirmation(
      title: isRejected ? 'Approve Again?' : 'Approve Appointment?',
      message: isRejected
          ? 'Are you sure you want to approve this previously rejected appointment?'
          : 'Are you sure you want to approve this appointment?',
      confirmText: 'Approve',
      confirmColor: Colors.green,
      icon: Icons.check_circle_outline,
    );

    if (!confirmed) return;

    await approveAppointment(booking);
  }

  Future<void> confirmCustomerArrived(
      Map<String, dynamic> booking,
      ) async {
    final confirmed = await showActionConfirmation(
      title: 'Customer Arrived?',
      message:
      'Confirm that the customer and vehicle have arrived at the workshop.',
      confirmText: 'Confirm Arrival',
      confirmColor: Colors.orange,
      icon: Icons.directions_car,
    );

    if (!confirmed) return;

    await markCustomerArrived(booking);
  }

  Future<void> approveAppointment(
      Map<String, dynamic> booking,
      ) async {
    if (isProcessingDecision) return;

    final bookingId =
    booking['booking_id']?.toString().trim();

    if (bookingId == null || bookingId.isEmpty) {
      showMessage('Booking information is missing.');
      return;
    }

    if (mounted) {
      setState(() {
        isProcessingDecision = true;
      });
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_decide_booking',
        params: {
          'p_booking_id': bookingId,
          'p_decision': 'approve',
          'p_rejection_reason': null,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid booking decision result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['updated'] != true ||
          result['status'] != 'Approved') {
        throw Exception(
          'The appointment was not approved correctly.',
        );
      }

      final customerId =
      result['customer_id']?.toString().trim();

      final title =
          result['title']?.toString() ??
              'Appointment Approved';

      final message =
          result['message']?.toString() ??
              'Your appointment has been approved.';

      if (customerId != null && customerId.isNotEmpty) {
        try {
          await sendFcmPushNotification(
            customerId: customerId,
            title: title,
            message: message,
            data: {
              'notification_type': 'booking',
              'target_page': 'my_bookings',
              'booking_id': result['booking_id'] ?? bookingId,
              'vehicle_id':
              result['vehicle_id'] ?? booking['vehicle_id'],
            },
          );
        } catch (notificationError, stackTrace) {
          debugPrint(
            'Appointment approval push failed: '
                '$notificationError',
          );
          debugPrint(stackTrace.toString());
        }
      }

      await fetchBookings(showLoading: false);
      showMessage('Appointment approved.');
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchBookings(showLoading: false);
    } catch (error, stackTrace) {
      debugPrint(
        'Admin approve appointment failed: $error',
      );
      debugPrint(stackTrace.toString());

      showMessage(
        'Failed to approve appointment: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isProcessingDecision = false;
        });
      }
    }
  }

  Future<void> rejectAppointment({
    required Map<String, dynamic> booking,
    required String reason,
  }) async {
    if (isProcessingDecision) return;

    final bookingId =
    booking['booking_id']?.toString().trim();

    final normalizedReason = reason.trim();

    if (bookingId == null || bookingId.isEmpty) {
      showMessage('Booking information is missing.');
      return;
    }

    if (normalizedReason.isEmpty) {
      showMessage('Please enter rejection reason.');
      return;
    }

    if (mounted) {
      setState(() {
        isProcessingDecision = true;
      });
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_decide_booking',
        params: {
          'p_booking_id': bookingId,
          'p_decision': 'reject',
          'p_rejection_reason': normalizedReason,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid booking decision result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['updated'] != true ||
          result['status'] != 'Rejected') {
        throw Exception(
          'The appointment was not rejected correctly.',
        );
      }

      final customerId =
      result['customer_id']?.toString().trim();

      final title =
          result['title']?.toString() ??
              'Appointment Rejected';

      final message =
          result['message']?.toString() ??
              'Your appointment has been rejected.';

      if (customerId != null && customerId.isNotEmpty) {
        try {
          await sendFcmPushNotification(
            customerId: customerId,
            title: title,
            message: message,
            data: {
              'notification_type': 'booking',
              'target_page': 'my_bookings',
              'booking_id': result['booking_id'] ?? bookingId,
              'vehicle_id':
              result['vehicle_id'] ?? booking['vehicle_id'],
            },
          );
        } catch (notificationError, stackTrace) {
          debugPrint(
            'Appointment rejection push failed: '
                '$notificationError',
          );
          debugPrint(stackTrace.toString());
        }
      }

      await fetchBookings(showLoading: false);
      showMessage('Appointment rejected.');
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchBookings(showLoading: false);
    } catch (error, stackTrace) {
      debugPrint(
        'Admin reject appointment failed: $error',
      );
      debugPrint(stackTrace.toString());

      showMessage(
        'Failed to reject appointment: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isProcessingDecision = false;
        });
      }
    }
  }

  Future<void> markCustomerArrived(
      Map<String, dynamic> booking,
      ) async {
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
    }
  }

  void showRejectReasonDialog(Map<String, dynamic> booking) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject Appointment'),
          content: TextField(
            controller: reasonController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Enter rejection reason',
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
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
                final reason = reasonController.text.trim();

                if (reason.isEmpty) {
                  showMessage('Please enter rejection reason.');
                  return;
                }

                Navigator.pop(context);

                final confirmed = await showActionConfirmation(
                  title: 'Reject Appointment?',
                  message:
                  'Are you sure you want to reject this appointment?\n\nReason: $reason',
                  confirmText: 'Reject',
                  confirmColor: Colors.red,
                  icon: Icons.cancel_outlined,
                );

                if (!confirmed) return;

                await rejectAppointment(
                  booking: booking,
                  reason: reason,
                );
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  void showBookingDetails(Map<String, dynamic> booking) {
    final customerName = booking['customers']?['name'] ?? 'Not Provided';
    final customerPhone = booking['customers']?['phone'] ?? 'Not Provided';
    final customerEmail = booking['customers']?['email'] ?? 'Not Provided';
    final vehiclePlate = booking['vehicles']?['plate_number'] ?? '';
    final vehicleModel = booking['vehicles']?['car_model'] ?? '';
    final date = formatDate(booking['appointment_date'].toString());
    final problem = booking['problem_description'] ?? 'No description';
    final services = getServices(booking);
    final total = getTotalPrice(booking);
    final status = booking['status'] ?? 'Booked';
    final rejectionReason = booking['rejection_reason'];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 35,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Booking Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  buildDetailRow('Customer', customerName),
                  buildDetailRow('Phone', customerPhone),
                  buildDetailRow('Email', customerEmail),
                  buildDetailRow('Vehicle', '$vehiclePlate • $vehicleModel'),
                  buildDetailRow('Date', date),
                  buildDetailRow('Problem', problem),
                  buildDetailRow('Status', status),
                  if (rejectionReason != null &&
                      rejectionReason.toString().isNotEmpty)
                    buildDetailRow(
                      'Reject Reason',
                      rejectionReason.toString(),
                    ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Selected Services',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (services.isEmpty)
                    buildServiceItem('No service found', 0)
                  else
                    ...services.map((service) {
                      final price =
                          double.tryParse(service['price'].toString()) ?? 0;

                      return buildServiceItem(
                        service['service_name'] ?? '',
                        price,
                      );
                    }),
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Estimated Total: RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF339BFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildServiceItem(String name, double price) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.build,
            color: Color(0xFF339BFF),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            price == 0 ? 'RM 0.00' : 'RM ${price.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget buildBookingCard(Map<String, dynamic> booking) {
    final status = booking['status'] ?? 'Booked';

    final customerName = booking['customers']?['name'] ?? 'Not Provided';
    final vehiclePlate = booking['vehicles']?['plate_number'] ?? '';
    final vehicleModel = booking['vehicles']?['car_model'] ?? '';
    final date = formatDate(booking['appointment_date'].toString());
    final services = getServices(booking);
    final rejectionReason = booking['rejection_reason'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
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

              if (status == 'Booked')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          showRejectReasonDialog(booking);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          confirmApproveAppointment(booking);
                        },
                      ),
                    ),
                  ],
                ),

              if (status == 'Rejected')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Approve Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      confirmApproveAppointment(booking);
                    },
                  ),
                ),

              if (status == 'Approved')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.directions_car, size: 18),
                    label: const Text('Customer Arrived'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      confirmCustomerArrived(booking);
                    },
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
            'Manage appointments and booking status',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
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
              onChanged: (value) {
                setState(() {
                  searchText = value;
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
                child: Center(
                  child: Text(
                    'No $selectedFilter bookings.',
                    style: const TextStyle(fontSize: 16),
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