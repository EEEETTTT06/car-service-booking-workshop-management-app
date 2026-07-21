import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';

class AdminAppointmentCalendarPage extends StatefulWidget {
  const AdminAppointmentCalendarPage({super.key});

  @override
  State<AdminAppointmentCalendarPage> createState() =>
      _AdminAppointmentCalendarPageState();
}

class _AdminAppointmentCalendarPageState
    extends State<AdminAppointmentCalendarPage> {
  int defaultDailyLimit = 10;
  DateTime currentMonth = DateTime.now();

  bool isLoading = false;
  bool isMonthRefreshing = false;

  Map<String, Map<String, dynamic>> dateSettings = {};
  Map<String, int> bookingCounts = {};
  RealtimeChannel? appointmentCalendarRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;

  final DateTime today = DateTime.now();

  bool isPastDate(DateTime date) {
    final onlyDate = DateTime(date.year, date.month, date.day);
    final current = DateTime(today.year, today.month, today.day);
    return onlyDate.isBefore(current);
  }

  @override
  void initState() {
    super.initState();

    loadCalendarData();
    setupRealtimeSubscription();
  }

  @override
  void dispose() {
    realtimeRefreshTimer?.cancel();

    final channel =
        appointmentCalendarRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    super.dispose();
  }
  Future<void> loadCalendarData({
    bool showLoading = true,
    bool showMonthProgress = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    } else if (showMonthProgress && mounted) {
      setState(() {
        isMonthRefreshing = true;
      });
    }

    try {
      await fetchDefaultLimit();
      await fetchDateSettings();
      await fetchBookingCounts();

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (showLoading || showMonthProgress) {
        showMessage(
          'Failed to load calendar data: $error',
        );
      } else {
        debugPrint(
          'Realtime admin calendar refresh failed: $error',
        );
      }
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        isMonthRefreshing = false;
      });
    }
  }

  Future<void> fetchDefaultLimit() async {
    final response = await supabase
        .from('appointment_settings')
        .select()
        .eq('id', 1)
        .maybeSingle();

    if (response != null) {
      defaultDailyLimit = response['default_daily_limit'] ?? 10;
    }
  }

  Future<void> fetchDateSettings() async {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);

    final response = await supabase
        .from('appointment_date_settings')
        .select()
        .gte('appointment_date', toSqlDate(firstDay))
        .lte('appointment_date', toSqlDate(lastDay));

    final Map<String, Map<String, dynamic>> temp = {};

    for (final item in response) {
      temp[item['appointment_date']] = Map<String, dynamic>.from(item);
    }

    dateSettings = temp;
  }

  Future<void> fetchBookingCounts() async {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);

    final response = await supabase
        .from('bookings')
        .select('appointment_date, status')
        .gte('appointment_date', toSqlDate(firstDay))
        .lte('appointment_date', toSqlDate(lastDay))
        .neq('status', 'Cancelled')
        .neq('status', 'Rejected');

    final Map<String, int> temp = {};

    for (final item in response) {
      final date = item['appointment_date'].toString();
      temp[date] = (temp[date] ?? 0) + 1;
    }

    bookingCounts = temp;
  }

  void setupRealtimeSubscription() {
    if (appointmentCalendarRealtimeChannel != null) {
      return;
    }

    appointmentCalendarRealtimeChannel = supabase
        .channel(
      'admin-appointment-calendar-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'appointment_settings',
      callback: (payload) {
        debugPrint(
          'Default appointment setting changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'appointment_date_settings',
      callback: (payload) {
        debugPrint(
          'Appointment date setting changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      callback: (payload) {
        debugPrint(
          'Appointment calendar booking changed: '
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
      refreshCalendarFromRealtime,
    );
  }

  Future<void> refreshCalendarFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await loadCalendarData(
        showLoading: false,
        showMonthProgress: false,
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }
  Future<void> updateDefaultLimit(int limit) async {
    try {
      await supabase.from('appointment_settings').update({
        'default_daily_limit': limit,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', 1);

      await loadCalendarData(showLoading: false);

      showUpdatedMessage('Default appointment limit has been updated.');
    } catch (error) {
      showMessage('Failed to update default limit: $error');
    }
  }

  Future<void> sendWorkshopClosedNotice({
    required DateTime date,
    required String reason,
  }) async {
    try {
      final customers = await supabase
          .from('customers')
          .select('customer_id, fcm_token');

      final title = 'Workshop Closed Notice';
      final message =
          'Workshop will be closed on ${displayDate(date)}. Reason: $reason';

      for (final customer in customers) {
        final customerId = customer['customer_id'];
        final token = customer['fcm_token']?.toString();

        if (customerId == null) continue;

        await supabase.from('notifications').insert({
          'customer_id': customerId,
          'title': title,
          'message': message,
          'notification_type': 'Workshop Closed',
          'is_read': false,
        });

        if (token != null && token.isNotEmpty) {
          await supabase.functions.invoke(
            'send-fcm',
            body: {
              'token': token,
              'title': title,
              'body': message,
            },
          );
        }
      }
    } catch (error) {
      debugPrint('Failed to send workshop closed notice: $error');
    }
  }

  Future<void> rejectBookingsForClosedDate({
    required DateTime date,
    required String reason,
  }) async {
    final dateKey = toSqlDate(date);

    final response = await supabase.from('bookings').select('''
    booking_id,
    customer_id,
    vehicle_id,
    appointment_date,
    customers(name, fcm_token),
    vehicles(plate_number, car_model)
  ''').eq('appointment_date', dateKey)
        .neq('status', 'Cancelled')
        .neq('status', 'Rejected');

    final existingBookings = List<Map<String, dynamic>>.from(response);

    for (final booking in existingBookings) {
      await supabase.from('bookings').update({
        'status': 'Rejected',
        'rejection_reason': reason,
      }).eq('booking_id', booking['booking_id']);

      final customerId = booking['customer_id'];
      final token = booking['customers']?['fcm_token']?.toString();
      final plate = booking['vehicles']?['plate_number'] ?? 'your vehicle';

      final title = 'Appointment Rejected';
      final message =
          'Your appointment for $plate on ${displayDate(date)} has been rejected because the workshop is closed. Reason: $reason';

      if (customerId != null) {
        await supabase.from('notifications').insert({
          'customer_id': customerId,
          'booking_id': booking['booking_id'],
          'vehicle_id': booking['vehicle_id'],
          'title': title,
          'message': message,
          'notification_type': 'Appointment Rejected',
          'is_read': false,
        });
      }

      if (token != null && token.isNotEmpty) {
        await supabase.functions.invoke(
          'send-fcm',
          body: {
            'token': token,
            'title': title,
            'body': message,
          },
        );
      }
    }
  }

  Future<void> updateDateSetting({
    required DateTime date,
    required int limit,
    required bool isClosed,
    required String reason,
    bool rejectExistingBookings = false,
  }) async {
    final dateKey = toSqlDate(date);
    final finalReason = reason.trim().isEmpty
        ? 'Workshop is closed on this date.'
        : reason.trim();

    try {
      if (isClosed && rejectExistingBookings) {
        await rejectBookingsForClosedDate(
          date: date,
          reason: finalReason,
        );
      }

      await supabase.from('appointment_date_settings').upsert({
        'appointment_date': dateKey,
        'daily_limit': isClosed ? null : limit,
        'is_closed': isClosed,
        'closed_reason': isClosed ? finalReason : null,
      }, onConflict: 'appointment_date');

      if (isClosed) {
        await sendWorkshopClosedNotice(
          date: date,
          reason: finalReason,
        );
      }

      await loadCalendarData(showLoading: false);

      showUpdatedMessage(
        isClosed
            ? 'Workshop has been closed for ${displayDate(date)}.'
            : 'Appointment limit has been updated for ${displayDate(date)}.',
      );
    } catch (error) {
      showMessage('Failed to update date setting: $error');
    }
  }

  int getLimitForDate(DateTime date) {
    final setting = dateSettings[toSqlDate(date)];

    if (setting != null && setting['daily_limit'] != null) {
      return setting['daily_limit'];
    }

    return defaultDailyLimit;
  }

  bool isDateClosed(DateTime date) {
    final setting = dateSettings[toSqlDate(date)];
    return setting != null && setting['is_closed'] == true;
  }

  int getBookingCount(DateTime date) {
    return bookingCounts[toSqlDate(date)] ?? 0;
  }

  int get closedDayCount {
    return dateSettings.values.where((item) => item['is_closed'] == true).length;
  }

  String toSqlDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String displayDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  List<DateTime?> generateMonthDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    final startEmptyBoxes = firstDay.weekday - 1;

    final List<DateTime?> days = [];

    for (int i = 0; i < startEmptyBoxes; i++) {
      days.add(null);
    }

    for (int day = 1; day <= totalDays; day++) {
      days.add(DateTime(month.year, month.month, day));
    }

    return days;
  }

  void previousMonth() async {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month - 1);
      dateSettings.clear();
      bookingCounts.clear();
    });

    await loadCalendarData(showLoading: false);
  }

  void nextMonth() async {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1);
      dateSettings.clear();
      bookingCounts.clear();
    });

    await loadCalendarData(showLoading: false);
  }

  String monthTitle(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }

  void showDefaultLimitDialog() {
    final controller = TextEditingController(
      text: defaultDailyLimit.toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4FF),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFF339BFF),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Appointment Limit',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set how many customers can book per day by default.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF339BFF),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Default Daily Limit',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF339BFF)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Custom date settings will override this default limit.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
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
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          final limit = int.tryParse(controller.text);

                          if (limit == null || limit <= 0) {
                            showMessage('Please enter a valid limit.');
                            return;
                          }

                          Navigator.pop(context);
                          await updateDefaultLimit(limit);
                        },
                        child: const Text('Save'),
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
  }

  Future<bool> showCloseDateConfirmDialog({
    required DateTime date,
    required int booked,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4E4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Existing Bookings Found',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$booked customer booking(s) already exist on ${displayDate(date)}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7F7),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.red.withOpacity(0.18)),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.close_rounded, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Reject all bookings')),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.notifications_active,
                              color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Notify affected customers')),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.block_rounded, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Close this appointment date')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Close Date'),
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

    return result == true;
  }

  void showDateSettingDialog(DateTime date) {
    final setting = dateSettings[toSqlDate(date)];
    bool isClosed = setting?['is_closed'] == true;

    final limitController = TextEditingController(
      text: (setting?['daily_limit'] ?? defaultDailyLimit).toString(),
    );

    final reasonController = TextEditingController(
      text: setting?['closed_reason'] ?? '',
    );

    final booked = getBookingCount(date);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          color: isClosed
                              ? const Color(0xFFFFE4E4)
                              : const Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          isClosed
                              ? Icons.block_rounded
                              : Icons.calendar_month_rounded,
                          color: isClosed ? Colors.red : const Color(0xFF339BFF),
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        displayDate(date),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Manage appointment availability for this date.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black54,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFFEAF4FF),
                              child: Icon(
                                Icons.people_alt_rounded,
                                color: Color(0xFF339BFF),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Current Bookings',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '$booked customer booking(s)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      AnimatedOpacity(
                        opacity: isClosed ? 0.45 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: TextField(
                            controller: limitController,
                            enabled: !isClosed,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF339BFF),
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Daily Limit',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isClosed
                              ? const Color(0xFFFFF1F1)
                              : const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isClosed
                                ? Colors.red.withOpacity(0.35)
                                : Colors.transparent,
                          ),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.red,
                          title: const Text(
                            'Close Workshop',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'Customers cannot book this date.',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: isClosed,
                          onChanged: (value) {
                            setDialogState(() {
                              isClosed = value;
                            });
                          },
                        ),
                      ),

                      if (isClosed) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7F7),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: TextField(
                            controller: reasonController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Closed Reason',
                              hintText: 'Example: Public holiday',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 22),

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
                                backgroundColor:
                                isClosed ? Colors.red : const Color(0xFF339BFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                final limit = int.tryParse(limitController.text) ??
                                    defaultDailyLimit;

                                if (!isClosed && limit <= 0) {
                                  showMessage(
                                    'Please enter a valid appointment limit.',
                                  );
                                  return;
                                }

                                bool rejectExisting = false;

                                if (isClosed && booked > 0) {
                                  Navigator.pop(context);

                                  final confirm =
                                  await showCloseDateConfirmDialog(
                                    date: date,
                                    booked: booked,
                                  );

                                  if (!confirm) return;

                                  rejectExisting = true;
                                } else {
                                  Navigator.pop(context);
                                }

                                await updateDateSetting(
                                  date: date,
                                  limit: limit,
                                  isClosed: isClosed,
                                  reason: reasonController.text.trim(),
                                  rejectExistingBookings: rejectExisting,
                                );
                              },
                              child: Text(isClosed ? 'Close Date' : 'Save'),
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

  void showUpdatedMessage(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8EF),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Success',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF339BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Return to Calendar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    required String subtitle,
  }) {
    return Container(
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
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFFD7E5FA),
        child: Icon(
          icon,
          size: 17,
          color: const Color(0xFF339BFF),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = generateMonthDays(currentMonth);

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Appointment Calendar'),
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
          : Stack(
        children: [
          Column(
            children: [
              Container(
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
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: buildSummaryCard(
                            icon: Icons.event_available,
                            title: 'Daily Limit',
                            value: '$defaultDailyLimit',
                            subtitle: 'Bookings / day',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildSummaryCard(
                            icon: Icons.block,
                            title: 'Closed Days',
                            value: '$closedDayCount',
                            subtitle: 'This month',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF339BFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: showDefaultLimitDialog,
                        icon: const Icon(Icons.tune),
                        label: const Text(
                          'Manage Appointment Limit',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      circleIconButton(
                        icon: Icons.arrow_back_ios_new,
                        onTap: previousMonth,
                      ),
                      Text(
                        monthTitle(currentMonth),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      circleIconButton(
                        icon: Icons.arrow_forward_ios,
                        onTap: nextMonth,
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: Center(child: Text('Mon'))),
                    Expanded(child: Center(child: Text('Tue'))),
                    Expanded(child: Center(child: Text('Wed'))),
                    Expanded(child: Center(child: Text('Thu'))),
                    Expanded(child: Center(child: Text('Fri'))),
                    Expanded(child: Center(child: Text('Sat'))),
                    Expanded(child: Center(child: Text('Sun'))),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;

                    if (velocity < 0) {
                      nextMonth();
                    } else if (velocity > 0) {
                      previousMonth();
                    }
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: days.length,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 0.72,
                    ),
                    itemBuilder: (context, index) {
                      final date = days[index];

                      if (date == null) {
                        return const SizedBox();
                      }

                      final isClosed = isDateClosed(date);
                      final limit = getLimitForDate(date);
                      final booked = getBookingCount(date);
                      final isFull = !isClosed && booked >= limit;
                      final isPast = isPastDate(date);

                      return GestureDetector(
                        onTap: () {
                          if (isPast) {
                            showMessage('Past dates cannot be modified.');
                            return;
                          }

                          showDateSettingDialog(date);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isPast
                                ? Colors.grey.shade200
                                : isClosed
                                ? Colors.red.shade50
                                : isFull
                                ? Colors.orange.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isPast
                                  ? Colors.grey
                                  : isClosed
                                  ? Colors.red
                                  : isFull
                                  ? Colors.orange
                                  : const Color(0xFF339BFF)
                                  .withOpacity(0.18),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isPast
                                      ? Colors.grey
                                      : isClosed
                                      ? Colors.red
                                      : isFull
                                      ? Colors.orange
                                      : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isPast
                                      ? Colors.grey.shade300
                                      : isClosed
                                      ? Colors.red.shade100
                                      : isFull
                                      ? Colors.orange.shade100
                                      : const Color(0xFFD7E5FA),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: FittedBox(
                                  child: Text(
                                    isPast
                                        ? 'Past'
                                        : isClosed
                                        ? 'Closed'
                                        : isFull
                                        ? 'Full'
                                        : '$booked/$limit',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: isPast
                                          ? Colors.grey.shade700
                                          : isClosed
                                          ? Colors.red
                                          : isFull
                                          ? Colors.orange
                                          : const Color(
                                          0xFF339BFF),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (isMonthRefreshing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 3,
                color: Colors.white,
                backgroundColor: Color(0xFFD7E5FA),
              ),
            ),
        ],
      ),
    );
  }
}