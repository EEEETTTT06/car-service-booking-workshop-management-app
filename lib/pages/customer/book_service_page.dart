import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_booking_calendar_page.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../common/app_result_message.dart';

class BookServicePage extends StatefulWidget {
  const BookServicePage({super.key});

  @override
  State<BookServicePage> createState() => _BookServicePageState();
}

class _BookServicePageState extends State<BookServicePage>
    with WidgetsBindingObserver {
  String selectedFilter = 'Upcoming';
  String selectedSort = 'Near to Far';
  bool isLoading = false;
  bool isProcessingBooking = false;
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;
  Map<String, dynamic>? currentCustomer;
  List<Map<String, dynamic>> bookings = [];
  List<Map<String, dynamic>> walkInPendingServices = [];
  List<Map<String, dynamic>> walkInServiceRecords = [];
  RealtimeChannel? bookingRealtimeChannel;

  Timer? realtimeRefreshTimer;

  bool isRealtimeRefreshing = false;
  bool hasPendingRealtimeRefresh = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

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

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    if (state == AppLifecycleState.resumed) {
      scheduleRealtimeRefresh();
    }
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
      setupRealtimeSubscription();
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

    final customerId =
    currentCustomer!['customer_id'].toString();

    final responses = await Future.wait([
      supabase
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
              created_at,
              estimated_completion_at,
              updated_at
            )
          ''')
          .eq('customer_id', customerId)
          .order('appointment_date', ascending: true),
      supabase
          .from('pending_services')
          .select('''
            *,
            vehicles(plate_number, car_model),
            quotations(
              quotation_id,
              booking_id,
              status,
              is_arrived,
              problem_description,
              total,
              quotation_items(
                item_id,
                item_name,
                quantity,
                price
              )
            )
          ''')
          .eq('customer_id', customerId)
          .isFilter('booking_id', null)
          .order('created_at', ascending: false),
      supabase
          .from('service_records')
          .select('''
            *,
            vehicles(plate_number, car_model),
            service_record_items(
              item_id,
              item_name,
              quantity,
              price
            )
          ''')
          .eq('customer_id', customerId)
          .isFilter('booking_id', null)
          .order('created_at', ascending: false),
    ]);

    bookings =
    List<Map<String, dynamic>>.from(
      responses[0] as List,
    );

    walkInPendingServices =
    List<Map<String, dynamic>>.from(
      responses[1] as List,
    );

    walkInServiceRecords =
    List<Map<String, dynamic>>.from(
      responses[2] as List,
    );
  }

  String dateOnlyFromTimestamp(dynamic value) {
    final rawValue = value?.toString().trim() ?? '';

    final parsed = DateTime.tryParse(rawValue)
        ?.toLocal() ??
        DateTime.now();

    return toSqlDate(parsed);
  }

  bool isWalkInEntry(Map<String, dynamic> entry) {
    return entry['_entry_type']
        ?.toString()
        .startsWith('walk_in') ==
        true;
  }

  Map<String, dynamic> buildWalkInPendingEntry(
      Map<String, dynamic> pending,
      ) {
    final quotationValue = pending['quotations'];

    final quotation = quotationValue is Map
        ? Map<String, dynamic>.from(
      quotationValue,
    )
        : <String, dynamic>{};

    final status =
        pending['status']?.toString() ??
            'Waiting Fix';

    return {
      '_entry_type': 'walk_in_pending',
      '_source_id': pending['pending_id'],
      'booking_id': null,
      'quotation_id':
      pending['quotation_id'],
      'appointment_date':
      dateOnlyFromTimestamp(
        pending['created_at'] ??
            pending['updated_at'],
      ),
      'arrived_at':
      pending['created_at'] ??
          pending['updated_at'],
      'problem_description':
      quotation['problem_description'] ??
          pending['note'] ??
          '',
      'status':
      status == 'Completed'
          ? 'Completed'
          : 'Arrived',
      'rejection_reason': null,
      'vehicles':
      pending['vehicles'] ?? {},
      'booking_services': const [],
      'pending_services': [
        Map<String, dynamic>.from(
          pending,
        ),
      ],
      '_service_items':
      normalizeRelatedRows(
        quotation['quotation_items'],
      ),
      '_quotation_total':
      quotation['total'],
      '_quotation_status':
      quotation['status'],
      '_service_type': 'Walk-in',
    };
  }

  Map<String, dynamic> buildWalkInRecordEntry(
      Map<String, dynamic> record,
      ) {
    return {
      '_entry_type': 'walk_in_record',
      '_source_id': record['record_id'],
      'booking_id': null,
      'quotation_id':
      record['quotation_id'],
      'appointment_date':
      dateOnlyFromTimestamp(
        record['created_at'],
      ),
      'arrived_at': null,
      'problem_description':
      record['problem_description'] ?? '',
      'status': 'Completed',
      'rejection_reason': null,
      'vehicles':
      record['vehicles'] ?? {},
      'booking_services': const [],
      'pending_services': [
        {
          'pending_id': null,
          'service_type': 'Walk-in',
          'status': 'Completed',
          'note': record['service_action'],
          'estimated_completion_at': null,
          'updated_at': record['created_at'],
        },
      ],
      '_service_items':
      normalizeRelatedRows(
        record['service_record_items'],
      ),
      '_record_total':
      record['total_price'],
      '_service_type': 'Walk-in',
      '_service_action':
      record['service_action'],
    };
  }

  List<Map<String, dynamic>>
  get allServiceEntries {
    final entries =
    <Map<String, dynamic>>[];

    for (final booking in bookings) {
      entries.add({
        ...booking,
        '_entry_type': 'appointment',
        '_service_type': 'Appointment',
      });
    }

    final completedQuotationIds =
    walkInServiceRecords
        .map(
          (record) =>
          record['quotation_id']
              ?.toString(),
    )
        .whereType<String>()
        .where(
          (id) => id.isNotEmpty,
    )
        .toSet();

    for (final pending
    in walkInPendingServices) {
      final quotationId =
      pending['quotation_id']
          ?.toString();

      final status =
      pending['status']?.toString();

      if (status == 'Completed' &&
          quotationId != null &&
          completedQuotationIds
              .contains(quotationId)) {
        continue;
      }

      entries.add(
        buildWalkInPendingEntry(
          pending,
        ),
      );
    }

    for (final record
    in walkInServiceRecords) {
      entries.add(
        buildWalkInRecordEntry(
          record,
        ),
      );
    }

    return entries;
  }

  void setupRealtimeSubscription() {
    if (currentCustomer == null) return;

    if (bookingRealtimeChannel != null) {
      return;
    }

    final customerId =
    currentCustomer!['customer_id']
        .toString();

    void handleChange(
        String source,
        dynamic eventType,
        ) {
      debugPrint(
        '$source changed: $eventType',
      );

      scheduleRealtimeRefresh();
    }

    bookingRealtimeChannel = supabase
        .channel(
      'customer-service-tracking-$customerId',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type:
        PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        handleChange(
          'Customer booking',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'pending_services',
      filter: PostgresChangeFilter(
        type:
        PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        handleChange(
          'Customer pending service',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotations',
      filter: PostgresChangeFilter(
        type:
        PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        handleChange(
          'Customer quotation',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotation_items',
      callback: (payload) {
        handleChange(
          'Quotation item',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'service_records',
      filter: PostgresChangeFilter(
        type:
        PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        handleChange(
          'Customer service record',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'service_record_items',
      callback: (payload) {
        handleChange(
          'Service record item',
          payload.eventType,
        );
      },
    )
        .subscribe(
          (status, error) {
        debugPrint(
          'Customer service tracking '
              'Realtime status: $status'
              '${error == null ? '' : ' - $error'}',
        );
      },
    );
  }

  void scheduleRealtimeRefresh() {
    realtimeRefreshTimer?.cancel();

    realtimeRefreshTimer = Timer(
      const Duration(milliseconds: 350),
      refreshBookingsFromRealtime,
    );
  }

  Future<void> refreshBookingsFromRealtime() async {
    if (!mounted) {
      return;
    }

    if (isRealtimeRefreshing) {
      hasPendingRealtimeRefresh = true;
      return;
    }

    isRealtimeRefreshing = true;

    try {
      do {
        hasPendingRealtimeRefresh = false;

        await fetchBookings();

        if (mounted) {
          setState(() {});
        }
      } while (
      mounted &&
          hasPendingRealtimeRefresh
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Realtime booking refresh failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  Future<void> updateExpiredBookings() async {
    try {
      final rpcResult = await supabase.rpc(
        'customer_cancel_expired_bookings',
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid expired booking result was returned.',
        );
      }

      final result = Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['processed'] != true) {
        throw Exception(
          'Expired bookings were not processed correctly.',
        );
      }

      final cancelledCount =
          int.tryParse(
            result['cancelled_count']
                ?.toString() ??
                '0',
          ) ??
              0;

      if (cancelledCount > 0) {
        debugPrint(
          '$cancelledCount expired booking(s) changed to Cancelled.',
        );
      }
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
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

  List<Map<String, dynamic>> normalizeRelatedRows(dynamic value) {
    if (value == null) return [];

    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (value is Map) {
      return [Map<String, dynamic>.from(value)];
    }

    return [];
  }

  List<Map<String, dynamic>> getPendingServices(Map<String, dynamic> booking) {
    return normalizeRelatedRows(booking['pending_services']);
  }

  Map<String, dynamic>? getLatestPendingService(
      Map<String, dynamic> booking,
      ) {
    final pending = List<Map<String, dynamic>>.from(
      getPendingServices(booking),
    );

    if (pending.isEmpty) return null;

    pending.sort((a, b) {
      final aDate =
          DateTime.tryParse(
            a['updated_at']?.toString() ?? '',
          ) ??
              DateTime.fromMillisecondsSinceEpoch(0);

      final bDate =
          DateTime.tryParse(
            b['updated_at']?.toString() ?? '',
          ) ??
              DateTime.fromMillisecondsSinceEpoch(0);

      return bDate.compareTo(aDate);
    });

    return pending.first;
  }

  String? getServiceProgress(
      Map<String, dynamic> booking,
      ) {
    return getLatestPendingService(
      booking,
    )?['status']?.toString();
  }

  String? getEstimatedCompletionAt(
      Map<String, dynamic> booking,
      ) {
    final value = getLatestPendingService(
      booking,
    )?['estimated_completion_at']
        ?.toString()
        .trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String? getArrivedAt(
      Map<String, dynamic> booking,
      ) {
    final value = booking['arrived_at']
        ?.toString()
        .trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  String formatDateTimeValue(
      String? value, {
        required String fallback,
      }) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }

    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      return fallback;
    }

    final local = parsed.toLocal();

    final day =
    local.day.toString().padLeft(2, '0');
    final month =
    local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final minute =
    local.minute.toString().padLeft(2, '0');

    final isPm = local.hour >= 12;
    final displayHour =
    local.hour % 12 == 0
        ? 12
        : local.hour % 12;

    final period = isPm ? 'PM' : 'AM';

    return '$day/$month/$year '
        '${displayHour.toString().padLeft(2, '0')}:'
        '$minute $period';
  }

  String getDisplayStatus(
      Map<String, dynamic> booking,
      ) {
    final bookingStatus =
        booking['status']
            ?.toString()
            .trim() ??
            'Booked';

    final progress =
    getServiceProgress(booking)
        ?.trim();

    if (progress == 'Completed' ||
        bookingStatus == 'Completed') {
      return 'Completed';
    }

    if (bookingStatus == 'Cancelled' ||
        bookingStatus == 'Rejected') {
      return 'Cancelled';
    }

    /*
   * Once the vehicle has arrived, it remains
   * inside the Arrived section while service
   * progress changes.
   */
    if (bookingStatus == 'Arrived' ||
        progress == 'Arrived' ||
        progress == 'Waiting Fix' ||
        progress == 'Waiting to Fix' ||
        progress == 'In Progress') {
      return 'Arrived';
    }

    if (isPastBooking(
      booking['appointment_date']
          .toString(),
    ) &&
        bookingStatus != 'Arrived' &&
        bookingStatus != 'Completed') {
      return 'Cancelled';
    }

    return 'Upcoming';
  }

  List<Map<String, dynamic>> sortBookingList(
      List<Map<String, dynamic>> source,
      ) {
    final result =
    List<Map<String, dynamic>>.from(
      source,
    );

    result.sort((a, b) {
      final aDate = parseDate(
        a['appointment_date'].toString(),
      );

      final bDate = parseDate(
        b['appointment_date'].toString(),
      );

      final now = DateTime.now();

      final today = DateTime(
        now.year,
        now.month,
        now.day,
      );

      final aDistance = aDate
          .difference(today)
          .inDays
          .abs();

      final bDistance = bDate
          .difference(today)
          .inDays
          .abs();

      final distanceComparison =
      aDistance.compareTo(bDistance);

      if (distanceComparison != 0) {
        return selectedSort ==
            'Near to Far'
            ? distanceComparison
            : -distanceComparison;
      }

      return selectedSort ==
          'Near to Far'
          ? aDate.compareTo(bDate)
          : bDate.compareTo(aDate);
    });

    return result;
  }

  List<Map<String, dynamic>>
  get filteredBookings {
    final result =
    allServiceEntries.where((entry) {
      return getDisplayStatus(entry) ==
          selectedFilter;
    }).toList();

    return sortBookingList(result);
  }

  List<Map<String, dynamic>>
  get cancelledBookings {
    final result =
    allServiceEntries.where((entry) {
      return !isWalkInEntry(entry) &&
          getDisplayStatus(entry) ==
              'Cancelled';
    }).toList();

    return sortBookingList(result);
  }

  int getStatusCount(String filter) {
    return allServiceEntries.where((entry) {
      return getDisplayStatus(entry) ==
          filter;
    }).length;
  }

  List<Map<String, dynamic>> getServices(
      Map<String, dynamic> booking,
      ) {
    if (isWalkInEntry(booking)) {
      return normalizeRelatedRows(
        booking['_service_items'],
      ).map((item) {
        return {
          'service_id': item['item_id'],
          'service_name':
          item['item_name'] ??
              'Service Item',
          'quantity':
          int.tryParse(
            item['quantity']?.toString() ??
                '1',
          ) ??
              1,
          'price':
          double.tryParse(
            item['price']?.toString() ??
                '0',
          ) ??
              0,
        };
      }).toList();
    }

    final bookingServices =
    normalizeRelatedRows(
      booking['booking_services'],
    );

    return bookingServices
        .map<Map<String, dynamic>?>((item) {
      final service = item['services'];

      if (service is Map) {
        return Map<String, dynamic>.from(
          service,
        );
      }

      return null;
    })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  double getTotalPrice(
      Map<String, dynamic> booking,
      ) {
    final storedRecordTotal =
    double.tryParse(
      booking['_record_total']?.toString() ??
          '',
    );

    if (storedRecordTotal != null &&
        storedRecordTotal > 0) {
      return storedRecordTotal;
    }

    final storedQuotationTotal =
    double.tryParse(
      booking['_quotation_total']
          ?.toString() ??
          '',
    );

    if (storedQuotationTotal != null &&
        storedQuotationTotal > 0) {
      return storedQuotationTotal;
    }

    double total = 0;

    for (final service
    in getServices(booking)) {
      final quantity = int.tryParse(
        service['quantity']?.toString() ??
            '1',
      ) ??
          1;

      final price = double.tryParse(
        service['price']?.toString() ??
            '0',
      ) ??
          0;

      total += quantity * price;
    }

    return total;
  }

  Color getStatusColor(String status) {
    if (status == 'Booked') {
      return Colors.blue;
    }

    if (status == 'Approved') {
      return Colors.green;
    }

    if (status == 'Arrived') {
      return Colors.orange;
    }

    if (status == 'Waiting Fix' ||
        status == 'Waiting to Fix') {
      return Colors.orange;
    }

    if (status == 'In Progress') {
      return Colors.blue;
    }

    if (status == 'Completed') {
      return Colors.green;
    }

    if (status == 'Rejected' ||
        status == 'Cancelled') {
      return Colors.red;
    }

    return Colors.grey;
  }

  Color getStatusBackgroundColor(
      String status,
      ) {
    if (status == 'Booked') {
      return Colors.blue.shade50;
    }

    if (status == 'Approved') {
      return Colors.green.shade50;
    }

    if (status == 'Arrived') {
      return Colors.orange.shade50;
    }

    if (status == 'Waiting Fix' ||
        status == 'Waiting to Fix') {
      return Colors.orange.shade50;
    }

    if (status == 'In Progress') {
      return Colors.blue.shade50;
    }

    if (status == 'Completed') {
      return Colors.green.shade50;
    }

    if (status == 'Rejected' ||
        status == 'Cancelled') {
      return Colors.red.shade50;
    }

    return Colors.grey.shade100;
  }

  Color getProgressColor(String status) {
    if (status == 'Waiting Fix' ||
        status == 'Waiting to Fix') {
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
    if (status == 'Waiting Fix' ||
        status == 'Waiting to Fix') {
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
    if (status == 'Waiting Fix' ||
        status == 'Waiting to Fix') {
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

  bool canModifyBooking(String status) {
    return status == 'Booked';
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

  Future<void> cancelBooking(
      Map<String, dynamic> booking,
      ) async {
    if (isProcessingBooking) return;

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
        isProcessingBooking = true;
      });
    }

    try {
      final rpcResult = await supabase.rpc(
        'customer_cancel_booking',
        params: {
          'p_booking_id': bookingId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid booking cancellation result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['cancelled'] != true ||
          result['status'] != 'Cancelled') {
        throw Exception(
          'The booking was not cancelled correctly.',
        );
      }

      /*
       * Notify admins only after the database
       * transaction succeeds.
       */
      try {
        await notifyAdminsAboutCancelledBooking(
          booking: booking,
        );
      } catch (
      notificationError,
      stackTrace
      ) {
        debugPrint(
          'Cancel booking notification failed: '
              '$notificationError',
        );

        debugPrint(
          stackTrace.toString(),
        );
      }

      await loadBookings();

      showMessage(
        'Booking cancelled successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadBookings();
    } catch (error, stackTrace) {
      debugPrint(
        'Customer cancel booking failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to cancel booking: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isProcessingBooking = false;
        });
      }
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
    required List<Map<String, dynamic>>
    selectedServices,
  }) async {
    if (isProcessingBooking) return;

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

    final serviceIds = selectedServices
        .map(
          (service) =>
          service['service_id']
              ?.toString()
              .trim(),
    )
        .whereType<String>()
        .where(
          (serviceId) =>
      serviceId.isNotEmpty,
    )
        .toSet()
        .toList();

    if (serviceIds.isEmpty) {
      showMessage(
        'Please select at least one service.',
      );
      return;
    }

    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final newDateOnly = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
    );

    if (!newDateOnly.isAfter(today)) {
      showMessage(
        'Same-day appointment updates are not available. '
            'Please select tomorrow or a later date.',
      );
      return;
    }

    final newSqlDate = toSqlDate(
      newDateOnly,
    );

    if (mounted) {
      setState(() {
        isProcessingBooking = true;
      });
    }

    try {
      final rpcResult = await supabase.rpc(
        'customer_update_booking',
        params: {
          'p_booking_id':
          bookingId,
          'p_appointment_date':
          newSqlDate,
          'p_problem_description':
          problem.trim(),
          'p_service_ids':
          serviceIds,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid booking update result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['updated'] != true ||
          result['booking_id'] == null) {
        throw Exception(
          'The booking was not updated correctly.',
        );
      }

      /*
       * Notify admins only after the database
       * transaction succeeds.
       */
      try {
        await notifyAdminsAboutUpdatedBooking(
          booking: booking,
          newDate: newDate,
        );
      } catch (
      notificationError,
      stackTrace
      ) {
        debugPrint(
          'Update booking notification failed: '
              '$notificationError',
        );

        debugPrint(
          stackTrace.toString(),
        );
      }

      await loadBookings();

      showMessage(
        'Booking updated successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadBookings();
    } catch (error, stackTrace) {
      debugPrint(
        'Customer update booking failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to update booking: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isProcessingBooking = false;
        });
      }
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
    final isWalkIn = isWalkInEntry(booking);
    final status =
        booking['status']?.toString() ?? 'Booked';

    final progress = getServiceProgress(booking);

    final isAutoCancelled =
        !isWalkIn &&
            getDisplayStatus(booking) == 'Cancelled' &&
            isPastBooking(
              booking['appointment_date'].toString(),
            ) &&
            status != 'Cancelled' &&
            status != 'Rejected' &&
            status != 'Completed';

    final bookingCategory =
    getDisplayStatus(booking);

    final displayedStatus =
    progress == 'Completed'
        ? 'Completed'
        : isAutoCancelled
        ? 'Cancelled'
        : bookingCategory == 'Arrived' &&
        progress != null
        ? progress
        : status;

    final date = formatDate(
      booking['appointment_date'].toString(),
    );
    final problem = booking['problem_description'] ?? '';
    final rejectionReason = booking['rejection_reason'] ?? '';
    final total = getTotalPrice(booking);

    final arrivedAt = getArrivedAt(booking);
    final estimatedCompletionAt =
    getEstimatedCompletionAt(booking);

    final showServiceTiming =
        bookingCategory == 'Arrived' ||
            arrivedAt != null ||
            estimatedCompletionAt != null;

    final arrivedTimeText =
    formatDateTimeValue(
      arrivedAt,
      fallback: 'Not Recorded',
    );

    final estimatedCompletionText =
    formatDateTimeValue(
      estimatedCompletionAt,
      fallback: 'Not Provided Yet',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            isWalkIn
                ? 'Walk-in Service Details'
                : 'Booking Details',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildDetailBox('Plate Number', vehicle['plate_number'] ?? ''),
                  buildDetailBox(
                    'Car Model',
                    vehicle['car_model'] ?? '',
                  ),
                  buildDetailBox(
                    'Service Type',
                    isWalkIn
                        ? 'Walk-in'
                        : 'Appointment',
                  ),
                  buildDetailBox(
                    isWalkIn
                        ? 'Walk-in Date'
                        : 'Appointment Date',
                    date,
                  ),
                  buildDetailBox(
                    isWalkIn
                        ? 'Service Status'
                        : 'Booking Status',
                    displayedStatus,
                  ),
                  if (showServiceTiming)
                    buildDetailBox(
                      'Arrived Time',
                      arrivedTimeText,
                    ),
                  if (showServiceTiming)
                    buildDetailBox(
                      'Estimated Completion',
                      estimatedCompletionText,
                    ),
                  if (status == 'Rejected' &&
                      rejectionReason.toString().isNotEmpty)
                    buildRejectReasonBox(rejectionReason.toString()),
                  if (progress != null) buildProgressBox(progress),
                  if (problem.toString().isNotEmpty)
                    buildDetailBox('Notes', problem),
                  const SizedBox(height: 14),
                  const Text(
                    'Service Items',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...services.map((service) {
                    final price =
                        double.tryParse(service['price'].toString()) ?? 0;

                    final quantity =
                        int.tryParse(
                          service['quantity']
                              ?.toString() ??
                              '1',
                        ) ??
                            1;

                    return buildServiceItem(
                      service['service_name'] ?? '',
                      price,
                      quantity: quantity,
                    );
                  }),
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: RM ${total.toStringAsFixed(2)}',
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
            if (!isWalkIn && canModifyBooking(status))
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  showEditBookingDialog(booking);
                },
                child: const Text('Edit Booking'),
              ),
            if (!isWalkIn && canModifyBooking(status))
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

                                final today = DateTime(
                                  now.year,
                                  now.month,
                                  now.day,
                                );

                                final minimumDate = today.add(
                                  const Duration(days: 1),
                                );

                                final maximumDate = DateTime(
                                  now.year + 1,
                                  now.month,
                                  now.day,
                                );

                                DateTime initialPickerDate =
                                    selectedDate;

                                if (selectedDate.isBefore(minimumDate)) {
                                  initialPickerDate = minimumDate;
                                } else if (
                                selectedDate.isAfter(maximumDate)
                                ) {
                                  initialPickerDate = maximumDate;
                                }

                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: initialPickerDate,
                                  firstDate: minimumDate,
                                  lastDate: maximumDate,
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

  Widget buildServiceTimingBox({
    required String arrivedTime,
    required String estimatedCompletionTime,
  }) {
    Widget buildTimeRow({
      required IconData icon,
      required String title,
      required String value,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color: const Color(0xFF339BFF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF339BFF)
              .withOpacity(0.25),
        ),
      ),
      child: Column(
        children: [
          buildTimeRow(
            icon: Icons.login,
            title: 'Arrived Time',
            value: arrivedTime,
          ),
          const SizedBox(height: 11),
          const Divider(height: 1),
          const SizedBox(height: 11),
          buildTimeRow(
            icon: Icons.schedule,
            title: 'Estimated Completion',
            value: estimatedCompletionTime,
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

  Widget buildServiceItem(
      String name,
      double price, {
        int quantity = 1,
      }) {
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
            quantity > 1
                ? 'Qty $quantity × RM ${price.toStringAsFixed(2)}'
                : 'RM ${price.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
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

  Widget buildSortControl() {
    const sortOptions = <String>[
      'Near to Far',
      'Far to Near',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.sort,
            color: Color(0xFF339BFF),
          ),

          const SizedBox(width: 10),

          const Text(
            'Date Order',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),

          const Spacer(),

          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedSort,
              borderRadius:
              BorderRadius.circular(14),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Color(0xFF339BFF),
              ),
              items: sortOptions.map((option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Text(
                    option,
                    style: const TextStyle(
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null ||
                    value == selectedSort) {
                  return;
                }

                setState(() {
                  selectedSort = value;
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
    final isWalkIn = isWalkInEntry(booking);
    final status = booking['status'] ?? 'Booked';
    final progress = getServiceProgress(booking);
    final isToday =
        !isWalkIn &&
            isTodayBooking(
              booking['appointment_date'],
            );
    final date = formatDate(booking['appointment_date']);
    final problem = booking['problem_description'] ?? '';
    final rejectionReason = booking['rejection_reason'] ?? '';
    final isAutoCancelled =
        !isWalkIn &&
            getDisplayStatus(booking) == 'Cancelled' &&
            isPastBooking(
              booking['appointment_date'].toString(),
            ) &&
            status != 'Cancelled' &&
            status != 'Rejected' &&
            status != 'Completed';
    final bookingCategory =
    getDisplayStatus(booking);

    final displayedStatus =
    progress == 'Completed'
        ? 'Completed'
        : isAutoCancelled
        ? 'Cancelled'
        : bookingCategory == 'Arrived' &&
        progress != null
        ? progress
        : status;

    final arrivedTimeText =
    formatDateTimeValue(
      getArrivedAt(booking),
      fallback: 'Not Recorded',
    );

    final estimatedCompletionText =
    formatDateTimeValue(
      getEstimatedCompletionAt(booking),
      fallback: 'Not Provided Yet',
    );

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
              if (isWalkIn)
                Container(
                  margin: const EdgeInsets.only(
                    bottom: 12,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius:
                    BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.purple.shade200,
                    ),
                  ),
                  child: const Text(
                    'WALK-IN SERVICE',
                    style: TextStyle(
                      color: Colors.purple,
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
                    isWalkIn
                        ? 'Walk-in: $date'
                        : date,
                    style: TextStyle(
                      color: isToday ? Colors.red : Colors.black87,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (bookingCategory == 'Arrived') ...[
                const SizedBox(height: 12),
                buildServiceTimingBox(
                  arrivedTime: arrivedTimeText,
                  estimatedCompletionTime:
                  estimatedCompletionText,
                ),
              ],
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

    AppResultMessage.show(
      context,
      message: message,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    );

    realtimeRefreshTimer?.cancel();

    final channel = bookingRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayBookings = filteredBookings;
    final displayCancelledBookings = cancelledBookings;

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
                      'My Vehicle Services',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Track appointments and walk-in service progress',
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
                          icon: Icons.car_repair,
                          title: 'Arrived',
                          value: '${getStatusCount('Arrived')}',
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
                    const SizedBox(width: 8),
                    buildFilterButton('Arrived'),
                    const SizedBox(width: 8),
                    buildFilterButton('Completed'),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 12),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: buildSortControl(),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
            if (displayBookings.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 35,
                  ),
                  child: Center(
                    child: Text(
                      'No $selectedFilter services.',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
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
                  0,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildBookingCard(
                        displayBookings[index],
                      );
                    },
                    childCount: displayBookings.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 28),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cancel_outlined,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Cancelled Bookings',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${displayCancelledBookings.length}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 12),
            ),
            if (displayCancelledBookings.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Center(
                    child: Text(
                      'No cancelled bookings.',
                      style: TextStyle(
                        color: Colors.black54,
                      ),
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
                      return buildBookingCard(
                        displayCancelledBookings[index],
                      );
                    },
                    childCount: displayCancelledBookings.length,
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
