import 'package:flutter/material.dart';
import 'customer_booking_calendar_page.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';

class BookServicePage extends StatefulWidget {
  const BookServicePage({super.key});

  @override
  State<BookServicePage> createState() => _BookServicePageState();
}

class _BookServicePageState extends State<BookServicePage> {
  String selectedFilter = 'Upcoming';
  bool isLoading = false;
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;
  Map<String, dynamic>? currentCustomer;
  List<Map<String, dynamic>> bookings = [];

  @override
  void initState() {
    super.initState();

    loadBookings();

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

  Future<void> loadBookings() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await updateExpiredBookings();
      await fetchBookings();
    }catch (error) {
      showMessage('Failed to load bookings: $error');
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

  Future<void> fetchBookings() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('bookings')
        .select('''
          *,
          vehicles(plate_number, car_model),
          booking_services(
            services(service_id, service_name, price)
          ),
          pending_services!pending_services_booking_id_fkey(
            pending_id,
            service_type,
            status,
            note,
            updated_at
          )
        ''')
        .eq('customer_id', currentCustomer!['customer_id'])
        .order('appointment_date', ascending: true);

    bookings = List<Map<String, dynamic>>.from(response);
  }

  Future<void> updateExpiredBookings() async {
    if (currentCustomer == null) return;

    final now = DateTime.now();

    final todaySql = toSqlDate(
      DateTime(
        now.year,
        now.month,
        now.day,
      ),
    );

    await supabase
        .from('bookings')
        .update({
      'status': 'Cancelled',
    })
        .eq(
      'customer_id',
      currentCustomer!['customer_id'],
    )
        .eq(
      'status',
      'Booked',
    )
        .lt(
      'appointment_date',
      todaySql,
    );
  }

  Future<List<Map<String, dynamic>>> fetchAllServices() async {
    final response = await supabase
        .from('services')
        .select()
        .eq('availability_status', 'Available')
        .order('service_name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  String formatDate(String date) {
    final parsed = DateTime.parse(date);
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String toSqlDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime parseDate(String date) => DateTime.parse(date);

  bool isTodayBooking(String date) {
    final bookingDate = parseDate(date);
    final today = DateTime.now();

    return bookingDate.year == today.year &&
        bookingDate.month == today.month &&
        bookingDate.day == today.day;
  }

  bool isPastBooking(String date) {
    final bookingDate = parseDate(date);
    final now = DateTime.now();

    final todayOnly = DateTime(now.year, now.month, now.day);
    final bookingOnly = DateTime(
      bookingDate.year,
      bookingDate.month,
      bookingDate.day,
    );

    return bookingOnly.isBefore(todayOnly);
  }

  List<Map<String, dynamic>> getPendingServices(Map<String, dynamic> booking) {
    final pending = booking['pending_services'] as List? ?? [];
    return List<Map<String, dynamic>>.from(pending);
  }

  String? getServiceProgress(Map<String, dynamic> booking) {
    final pending = getPendingServices(booking);

    if (pending.isEmpty) return null;

    pending.sort((a, b) {
      final aDate = DateTime.tryParse(a['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return bDate.compareTo(aDate);
    });

    return pending.first['status']?.toString();
  }

  String getDisplayStatus(Map<String, dynamic> booking) {
    final bookingStatus =
        booking['status']?.toString() ?? 'Booked';

    final progress = getServiceProgress(booking);

    if (progress == 'Completed' ||
        bookingStatus == 'Completed') {
      return 'Completed';
    }

    if (bookingStatus == 'Cancelled' ||
        bookingStatus == 'Rejected') {
      return 'Cancelled';
    }

    if (isPastBooking(
      booking['appointment_date'].toString(),
    ) &&
        bookingStatus != 'Arrived' &&
        bookingStatus != 'Completed') {
      return 'Cancelled';
    }

    return 'Upcoming';
  }

  List<Map<String, dynamic>> get filteredBookings {
    final result = bookings.where((booking) {
      return getDisplayStatus(booking) == selectedFilter;
    }).toList();

    if (selectedFilter == 'Upcoming') {
      result.sort((a, b) {
        final aDate = parseDate(a['appointment_date']);
        final bDate = parseDate(b['appointment_date']);

        final aToday = isTodayBooking(a['appointment_date']);
        final bToday = isTodayBooking(b['appointment_date']);

        if (aToday && !bToday) return -1;
        if (!aToday && bToday) return 1;

        return aDate.compareTo(bDate);
      });
    }

    return result;
  }

  int getStatusCount(String filter) {
    return bookings.where((booking) {
      return getDisplayStatus(booking) == filter;
    }).length;
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

  Color getProgressColor(String status) {
    if (status == 'Waiting Fix') {
      return Colors.orange;
    }

    if (status == 'In Progress') {
      return Colors.blue;
    }

    if (status == 'Completed') {
      return Colors.green;
    }

    return Colors.grey;
  }

  Color getProgressBackgroundColor(String status) {
    if (status == 'Waiting Fix') {
      return Colors.orange.shade50;
    }

    if (status == 'In Progress') {
      return Colors.blue.shade50;
    }

    if (status == 'Completed') {
      return Colors.green.shade50;
    }

    return Colors.grey.shade100;
  }

  IconData getProgressIcon(String status) {
    if (status == 'Waiting Fix') {
      return Icons.pending_actions;
    }

    if (status == 'In Progress') {
      return Icons.build_circle;
    }

    if (status == 'Completed') {
      return Icons.check_circle;
    }

    return Icons.info;
  }

  bool canModifyBooking(String appointmentDate, String status) {
    if (status != 'Booked') return false;

    final date = parseDate(appointmentDate);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final appointmentOnly = DateTime(date.year, date.month, date.day);

    return appointmentOnly.difference(todayOnly).inDays >= 3;
  }

  Future<void> notifyAdminsAboutCancelledBooking({
    required Map<String, dynamic> booking,
  }) async {
    try {
      final vehicle = booking['vehicles'] ?? {};
      final customerName = currentCustomer?['name'] ?? 'A customer';
      final plate = vehicle['plate_number'] ?? 'Unknown Vehicle';
      final date = formatDate(booking['appointment_date'].toString());

      const title = 'Booking Cancelled';
      final body = '$customerName cancelled booking for $plate on $date.';

      final admins = await supabase
          .from('admins')
          .select('admin_id, notification_enabled');

      for (final admin in admins) {
        await supabase.from('admin_notifications').insert({
          'admin_id': admin['admin_id'],
          'title': title,
          'message': body,
          'is_read': false,
          'notification_type': 'booking',
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
      debugPrint('Cancel booking notify admin error: $error');
    }
  }

  Future<void> cancelBooking(Map<String, dynamic> booking) async {
    try {
      await supabase.from('bookings').update({
        'status': 'Cancelled',
      }).eq('booking_id', booking['booking_id']);

      await notifyAdminsAboutCancelledBooking(booking: booking);

      await loadBookings();
      showMessage('Booking cancelled successfully.');
    } catch (error) {
      showMessage('Failed to cancel booking: $error');
    }
  }
  Future<void> notifyAdminsAboutUpdatedBooking({
    required Map<String, dynamic> booking,
    required DateTime newDate,
  }) async {
    try {
      final vehicle = booking['vehicles'] ?? {};
      final customerName = currentCustomer?['name'] ?? 'A customer';
      final plate = vehicle['plate_number'] ?? 'Unknown Vehicle';
      final date = formatDate(toSqlDate(newDate));

      const title = 'Booking Updated';
      final body = '$customerName updated booking for $plate to $date.';

      final admins = await supabase
          .from('admins')
          .select('admin_id, notification_enabled');

      for (final admin in admins) {
        await supabase.from('admin_notifications').insert({
          'admin_id': admin['admin_id'],
          'title': title,
          'message': body,
          'is_read': false,
          'notification_type': 'booking',
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
      debugPrint('Update booking notify admin error: $error');
    }
  }
  Future<void> updateBooking({
    required Map<String, dynamic> booking,
    required DateTime newDate,
    required String problem,
    required List<Map<String, dynamic>> selectedServices,
  }) async {
    try {
      final newSqlDate = toSqlDate(newDate);

      final existingBooking = await supabase
          .from('bookings')
          .select('booking_id')
          .eq(
        'vehicle_id',
        booking['vehicle_id'],
      )
          .eq(
        'appointment_date',
        newSqlDate,
      )
          .neq(
        'booking_id',
        booking['booking_id'],
      )
          .neq(
        'status',
        'Cancelled',
      )
          .limit(1);

      if (existingBooking.isNotEmpty) {
        showMessage(
          'This vehicle already has another booking on the selected date.',
        );
        return;
      }
      await supabase.from('bookings').update({
        'appointment_date': newSqlDate,
        'problem_description': problem.trim(),
      }).eq('booking_id', booking['booking_id']);

      await supabase.from('booking_services').delete().eq(
        'booking_id',
        booking['booking_id'],
      );

      for (final service in selectedServices) {
        await supabase.from('booking_services').insert({
          'booking_id': booking['booking_id'],
          'service_id': service['service_id'],
        });
      }

      await notifyAdminsAboutUpdatedBooking(
        booking: booking,
        newDate: newDate,
      );

      await loadBookings();
      showMessage('Booking updated successfully.');
    } catch (error) {
      showMessage('Failed to update booking: $error');
    }
  }

  Future<void> goToCalendarPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerBookingCalendarPage(
          onBookingConfirmed: (_) {},
        ),
      ),
    );

    if (!mounted) return;

    await loadBookings();
  }

  void showBookingDetailDialog(Map<String, dynamic> booking) {
    final vehicle = booking['vehicles'] ?? {};
    final services = getServices(booking);
    final status =
        booking['status']?.toString() ?? 'Booked';

    final progress = getServiceProgress(booking);

    final isAutoCancelled =
        getDisplayStatus(booking) == 'Cancelled' &&
            isPastBooking(
              booking['appointment_date'].toString(),
            ) &&
            status != 'Cancelled' &&
            status != 'Rejected' &&
            status != 'Completed';

    final displayedStatus = progress == 'Completed'
        ? 'Completed'
        : isAutoCancelled
        ? 'Cancelled'
        : status;

    final date = formatDate(
      booking['appointment_date'].toString(),
    );
    final problem = booking['problem_description'] ?? '';
    final rejectionReason = booking['rejection_reason'] ?? '';
    final total = getTotalPrice(booking);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Booking Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildDetailBox('Plate Number', vehicle['plate_number'] ?? ''),
                  buildDetailBox('Car Model', vehicle['car_model'] ?? ''),
                  buildDetailBox('Appointment Date', date),
                  buildDetailBox(
                    'Booking Status',
                    displayedStatus,
                  ),
                  if (status == 'Rejected' &&
                      rejectionReason.toString().isNotEmpty)
                    buildRejectReasonBox(rejectionReason.toString()),
                  if (progress != null) buildProgressBox(progress),
                  if (problem.toString().isNotEmpty)
                    buildDetailBox('Notes', problem),
                  const SizedBox(height: 14),
                  const Text(
                    'Selected Services',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
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
            if (canModifyBooking(booking['appointment_date'], status))
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  showEditBookingDialog(booking);
                },
                child: const Text('Edit Booking'),
              ),
            if (canModifyBooking(booking['appointment_date'], status))
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  showCancelConfirmDialog(booking);
                },
                child: const Text(
                  'Cancel Booking',
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

  void showEditBookingDialog(Map<String, dynamic> booking) async {
    final allServices = await fetchAllServices();

    DateTime selectedDate = parseDate(booking['appointment_date']);
    final notesController = TextEditingController(
      text: booking['problem_description'] ?? '',
    );

    List<Map<String, dynamic>> selectedServices =
    List<Map<String, dynamic>>.from(
      getServices(booking),
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double editTotal = 0;
            for (final service in selectedServices) {
              editTotal += double.tryParse(service['price'].toString()) ?? 0;
            }

            bool isSelected(Map<String, dynamic> service) {
              return selectedServices.any(
                    (item) => item['service_id'] == service['service_id'],
              );
            }

            void toggleService(Map<String, dynamic> service) {
              setDialogState(() {
                if (isSelected(service)) {
                  selectedServices.removeWhere(
                        (item) => item['service_id'] == service['service_id'],
                  );
                } else {
                  selectedServices.add(service);
                }
              });
            }

            return AlertDialog(
              insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Text(
                'Edit Booking',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 430,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event,
                              color: Color(0xFF339BFF),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Appointment Date: ${formatDate(toSqlDate(selectedDate))}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final now = DateTime.now();
                                final minimumDate = DateTime(
                                  now.year,
                                  now.month,
                                  now.day,
                                ).add(
                                  const Duration(days: 3),
                                );

                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: minimumDate,
                                  lastDate: DateTime(
                                    now.year + 1,
                                    now.month,
                                    now.day,
                                  ),
                                );

                                if (picked != null) {
                                  setDialogState(() {
                                    selectedDate = picked;
                                  });
                                }
                              },
                              child: const Text('Change'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: notesController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Problem / Service Notes',
                          hintText:
                          'Describe any issue, noise, warning light, or special request.',
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select Services',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...allServices.map((service) {
                        final selected = isSelected(service);
                        final price =
                            double.tryParse(service['price'].toString()) ?? 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF339BFF)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: CheckboxListTile(
                            activeColor: const Color(0xFF339BFF),
                            value: selected,
                            onChanged: (_) => toggleService(service),
                            title: Text(
                              service['service_name'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'RM ${price.toStringAsFixed(2)}',
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Estimated Total: RM ${editTotal.toStringAsFixed(2)}',
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedServices.isEmpty) {
                      showMessage('Please select at least one service.');
                      return;
                    }

                    Navigator.pop(context);

                    await updateBooking(
                      booking: booking,
                      newDate: selectedDate,
                      problem: notesController.text,
                      selectedServices: selectedServices,
                    );
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showCancelConfirmDialog(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel Booking'),
          content: const Text(
            'Are you sure you want to cancel this booking?',
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
                await cancelBooking(booking);
              },
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget buildRejectReasonBox(String reason) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cancel, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reject Reason: $reason',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildProgressBox(String status) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: getProgressBackgroundColor(status),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: getProgressColor(status).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(
            getProgressIcon(status),
            color: getProgressColor(status),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Service Progress',
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            status,
            style: TextStyle(
              color: getProgressColor(status),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
            'RM ${price.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget buildFilterButton(String title) {
    final isSelected = selectedFilter == title;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedFilter = title;
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
            color: isSelected ? const Color(0xFF339BFF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
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
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF339BFF),
                fontWeight: FontWeight.bold,
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
              child: Icon(
                icon,
                color: const Color(0xFF339BFF),
              ),
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

  Widget buildServiceChip(String serviceName) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFD7E5FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        serviceName,
        style: const TextStyle(
          color: Color(0xFF1F2937),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget buildBookingCard(Map<String, dynamic> booking) {
    final vehicle = booking['vehicles'] ?? {};
    final services = getServices(booking);
    final status = booking['status'] ?? 'Booked';
    final progress = getServiceProgress(booking);
    final isToday = isTodayBooking(booking['appointment_date']);
    final date = formatDate(booking['appointment_date']);
    final problem = booking['problem_description'] ?? '';
    final rejectionReason = booking['rejection_reason'] ?? '';
    final isAutoCancelled = getDisplayStatus(booking) == 'Cancelled' &&
        isPastBooking(booking['appointment_date'].toString()) &&
        status != 'Cancelled' &&
        status != 'Rejected' &&
        status != 'Completed';
    final displayedStatus = progress == 'Completed'
        ? 'Completed'
        : isAutoCancelled
        ? 'Cancelled'
        : status;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isToday ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: isToday
            ? Border.all(color: Colors.red, width: 1.8)
            : Border.all(color: Colors.transparent),
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
          showBookingDetailDialog(booking);
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isToday)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'TODAY APPOINTMENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFFD7E5FA),
                    child: Icon(
                      Icons.directions_car,
                      color: Color(0xFF339BFF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: getStatusBackgroundColor(
                        displayedStatus,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      displayedStatus,
                      style: TextStyle(
                        color: getStatusColor(
                          displayedStatus,
                        ),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.event, size: 17, color: Colors.black45),
                  const SizedBox(width: 8),
                  Text(
                    date,
                    style: TextStyle(
                      color: isToday ? Colors.red : Colors.black87,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (status == 'Rejected' &&
                  rejectionReason.toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Reject Reason: $rejectionReason',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              if (isAutoCancelled) ...[
                const SizedBox(height: 10),
                const Text(
                  'This appointment date has passed without arrival confirmation.',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 12),
                buildProgressBox(progress),
              ],
              const SizedBox(height: 12),
              const Text(
                'Services',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
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
              if (problem.toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Notes: $problem',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
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
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayBookings = filteredBookings;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Book Service'),
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
        onRefresh: loadBookings,
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
                      'My Service Bookings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'View and manage your workshop appointments',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.upcoming,
                          title: 'Upcoming',
                          value: '${getStatusCount('Upcoming')}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.check_circle,
                          title: 'Completed',
                          value: '${getStatusCount('Completed')}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    buildFilterButton('Upcoming'),
                    const SizedBox(width: 10),
                    buildFilterButton('Completed'),
                    const SizedBox(width: 10),
                    buildFilterButton('Cancelled'),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),

            if (displayBookings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No $selectedFilter bookings.',
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
                  120,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final booking = displayBookings[index];

                      return buildBookingCard(booking);
                    },
                    childCount: displayBookings.length,
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
              heroTag: 'bookServiceBackToTop',
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
            heroTag: 'bookServiceNewBooking',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: goToCalendarPage,
            icon: const Icon(Icons.add),
            label: const Text(
              'New Booking',
            ),
          ),
        ],
      ),
    );
  }
}