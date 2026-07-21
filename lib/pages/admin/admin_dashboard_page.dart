import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_sidebar.dart';
import 'admin_quotations_page.dart';
import 'pending_service_page.dart';
import 'vehicle_management_page.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';

class AdminDashboardPage extends StatefulWidget {
  final Function(int) onNavigate;

  const AdminDashboardPage({
    super.key,
    required this.onNavigate,
  });

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool isLoading = false;

  int bookingCount = 0;
  int customerCount = 0;
  int serviceCount = 0;
  int recordCount = 0;

  String selectedMonth = '';

  static String? rememberedSelectedMonth;

  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> vehicleChartData = [];

  RealtimeChannel? dashboardRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    setDefaultMonth();
    loadDashboardData();
    setupRealtimeSubscription();
  }
  @override
  void dispose() {
    realtimeRefreshTimer?.cancel();

    final channel = dashboardRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    super.dispose();
  }
  void setDefaultMonth() {
    if (rememberedSelectedMonth != null &&
        rememberedSelectedMonth!.isNotEmpty) {
      selectedMonth = rememberedSelectedMonth!;
      return;
    }

    final now = DateTime.now();

    selectedMonth =
    '${getMonthName(now.month)} ${now.year}';

    rememberedSelectedMonth = selectedMonth;
  }

  Future<void> loadDashboardData({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      await fetchDashboardCounts();
      await fetchVehicles();

      final months = <String>{};

      for (final vehicle in vehicles) {
        final createdAt = vehicle['created_at'];

        if (createdAt == null) continue;

        final date =
        DateTime.parse(createdAt.toString()).toLocal();

        months.add(
          '${getMonthName(date.month)} ${date.year}',
        );
      }

      if (months.isNotEmpty &&
          !months.contains(selectedMonth)) {
        final sortedMonths = months.toList();

        sortedMonths.sort((a, b) {
          return parseMonthYear(b).compareTo(
            parseMonthYear(a),
          );
        });

        selectedMonth = sortedMonths.first;
        rememberedSelectedMonth = selectedMonth;
      }

      generateVehicleChartData();

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load dashboard: $error',
        );
      } else {
        debugPrint(
          'Realtime dashboard refresh failed: $error',
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

  Future<void> fetchDashboardCounts() async {
    final bookingsResponse = await supabase.from('bookings').select();
    final customersResponse = await supabase.from('customers').select();
    final servicesResponse = await supabase.from('services').select();
    final recordsResponse = await supabase.from('service_records').select();

    bookingCount = List<Map<String, dynamic>>.from(bookingsResponse).length;
    customerCount = List<Map<String, dynamic>>.from(customersResponse).length;
    serviceCount = List<Map<String, dynamic>>.from(servicesResponse).length;
    recordCount = List<Map<String, dynamic>>.from(recordsResponse).length;
  }

  Future<void> fetchVehicles() async {
    final response = await supabase
        .from('vehicles')
        .select()
        .order('created_at', ascending: false);

    vehicles = List<Map<String, dynamic>>.from(response);
  }

  void setupRealtimeSubscription() {
    if (dashboardRealtimeChannel != null) {
      return;
    }

    dashboardRealtimeChannel = supabase
        .channel(
      'admin-dashboard-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      callback: (payload) {
        scheduleDashboardRefresh(
          'Booking',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'customers',
      callback: (payload) {
        scheduleDashboardRefresh(
          'Customer',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'services',
      callback: (payload) {
        scheduleDashboardRefresh(
          'Service',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'service_records',
      callback: (payload) {
        scheduleDashboardRefresh(
          'Service record',
          payload.eventType,
        );
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vehicles',
      callback: (payload) {
        scheduleDashboardRefresh(
          'Vehicle',
          payload.eventType,
        );
      },
    )
        .subscribe();
  }

  void scheduleDashboardRefresh(
      String source,
      dynamic eventType,
      ) {
    debugPrint(
      'Dashboard $source changed: $eventType',
    );

    realtimeRefreshTimer?.cancel();

    realtimeRefreshTimer = Timer(
      const Duration(milliseconds: 350),
      refreshDashboardFromRealtime,
    );
  }

  Future<void> refreshDashboardFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await loadDashboardData(
        showLoading: false,
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  List<String> get availableMonths {
    final months = <String>{};

    for (final vehicle in vehicles) {
      final createdAt = vehicle['created_at'];
      if (createdAt == null) continue;

      final date = DateTime.parse(createdAt).toLocal();
      months.add('${getMonthName(date.month)} ${date.year}');
    }

    final list = months.toList();

    list.sort((a, b) {
      final aDate = parseMonthYear(a);
      final bDate = parseMonthYear(b);
      return bDate.compareTo(aDate);
    });

    if (list.isEmpty) return [selectedMonth];

    if (!list.contains(selectedMonth)) {
      selectedMonth = list.first;
      rememberedSelectedMonth = selectedMonth;
    }

    return list;
  }

  void generateVehicleChartData() {
    final Map<String, int> grouped = {};

    for (final vehicle in vehicles) {
      final createdAt = vehicle['created_at'];
      if (createdAt == null) continue;

      final date = DateTime.parse(createdAt).toLocal();
      final vehicleMonth = '${getMonthName(date.month)} ${date.year}';

      if (vehicleMonth != selectedMonth) continue;

      final model = (vehicle['car_model'] ?? 'Unknown').toString().trim();
      final brand = getCarBrand(model);

      grouped[brand] = (grouped[brand] ?? 0) + 1;
    }

    vehicleChartData = grouped.entries.map((entry) {
      return {
        'type': entry.key,
        'count': entry.value,
      };
    }).toList();

    vehicleChartData.sort((a, b) {
      return (b['count'] as int).compareTo(a['count'] as int);
    });
  }

  String getCarBrand(String model) {
    final text = model.toLowerCase();

    if (text.contains('honda')) return 'Honda';
    if (text.contains('toyota')) return 'Toyota';
    if (text.contains('perodua')) return 'Perodua';
    if (text.contains('proton')) return 'Proton';
    if (text.contains('nissan')) return 'Nissan';
    if (text.contains('mazda')) return 'Mazda';
    if (text.contains('bmw')) return 'BMW';
    if (text.contains('mercedes')) return 'Mercedes';
    if (text.contains('hyundai')) return 'Hyundai';
    if (text.contains('kia')) return 'Kia';

    final parts = model.trim().split(' ');
    return parts.isEmpty || parts.first.isEmpty ? 'Unknown' : parts.first;
  }

  String getMonthName(int month) {
    const months = [
      '',
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

    return months[month];
  }

  int getMonthNumber(String monthName) {
    const months = {
      'January': 1,
      'February': 2,
      'March': 3,
      'April': 4,
      'May': 5,
      'June': 6,
      'July': 7,
      'August': 8,
      'September': 9,
      'October': 10,
      'November': 11,
      'December': 12,
    };

    return months[monthName] ?? 1;
  }

  DateTime parseMonthYear(String value) {
    final parts = value.split(' ');
    final month = getMonthNumber(parts[0]);
    final year = int.tryParse(parts[1]) ?? DateTime.now().year;

    return DateTime(year, month);
  }

  void openPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Color getBarColor(int index) {
    final colors = [
      const Color(0xFF339BFF),
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.brown,
      Colors.indigo,
    ];

    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final months = availableMonths;
    final carData = vehicleChartData;

    final int maxCount = carData.isEmpty
        ? 1
        : carData
        .map((car) => car['count'] as int)
        .reduce((a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
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
        onRefresh: () => loadDashboardData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle('Overview'),
              const SizedBox(height: 10),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    dashboardCard(
                      title: 'Bookings',
                      value: '$bookingCount',
                      icon: Icons.calendar_month,
                      pageIndex: 1,
                    ),
                    dashboardCard(
                      title: 'Customers',
                      value: '$customerCount',
                      icon: Icons.people,
                      pageIndex: 2,
                    ),
                    dashboardCard(
                      title: 'Services',
                      value: '$serviceCount',
                      icon: Icons.build,
                      pageIndex: 3,
                    ),
                    dashboardCard(
                      title: 'Records',
                      value: '$recordCount',
                      icon: Icons.assignment,
                      pageIndex: 4,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              sectionTitle('Quick Actions'),
              const SizedBox(height: 10),
              SizedBox(
                height: 108,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    shortcutCard(
                      title: 'Quotation',
                      icon: Icons.receipt_long,
                      page: const AdminQuotationsPage(),
                    ),
                    shortcutCard(
                      title: 'Pending Service',
                      icon: Icons.car_repair,
                      page: const PendingServicePage(),
                    ),
                    shortcutCard(
                      title: 'Vehicles',
                      icon: Icons.directions_car,
                      page: const VehicleManagementPage(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Vehicle Statistics',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        monthDropdown(months),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Vehicle brand summary for $selectedMonth',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 255,
                      child: carData.isEmpty
                          ? const Center(
                        child: Text(
                          'No vehicle data for this month.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                          : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment:
                          CrossAxisAlignment.end,
                          children:
                          carData.asMap().entries.map((entry) {
                            final index = entry.key;
                            final car = entry.value;

                            final int count =
                            car['count'] as int;
                            final double barHeight = maxCount == 0
                                ? 0
                                : (count / maxCount) * 165;

                            return Container(
                              width: 76,
                              margin:
                              const EdgeInsets.only(right: 14),
                              child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '$count',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedContainer(
                                    duration: const Duration(
                                      milliseconds: 500,
                                    ),
                                    height: barHeight,
                                    width: 42,
                                    decoration: BoxDecoration(
                                      color: getBarColor(index),
                                      borderRadius:
                                      BorderRadius.circular(16),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    car['type'].toString(),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),
              sectionTitle('Monthly Report Data'),
              const SizedBox(height: 10),
              if (carData.isEmpty)
                emptyCard('No monthly report data available.')
              else
                ...carData.asMap().entries.map((entry) {
                  return monthlyReportCard(
                    entry.value,
                    getBarColor(entry.key),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1F2937),
      ),
    );
  }

  Widget monthDropdown(List<String> months) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF339BFF).withOpacity(0.18),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedMonth,
          borderRadius: BorderRadius.circular(18),
          dropdownColor: Colors.white,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF339BFF),
          ),
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: months.map((month) {
            return DropdownMenuItem(
              value: month,
              child: Text(month),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              selectedMonth = value;
              rememberedSelectedMonth = value;
              generateVehicleChartData();
            });
          },
        ),
      ),
    );
  }
  Color getDashboardColor(String title) {
    if (title == 'Bookings') return const Color(0xFF339BFF);
    if (title == 'Customers') return Colors.green;
    if (title == 'Services') return Colors.orange;
    if (title == 'Records') return Colors.purple;
    return const Color(0xFF339BFF);
  }

  Color getDashboardBgColor(String title) {
    if (title == 'Bookings') return const Color(0xFFEAF4FF);
    if (title == 'Customers') return Colors.green.shade50;
    if (title == 'Services') return Colors.orange.shade50;
    if (title == 'Records') return Colors.purple.shade50;
    return const Color(0xFFEAF4FF);
  }
  Widget dashboardCard({
    required String title,
    required String value,
    required IconData icon,
    required int pageIndex,
  }) {
    final color = getDashboardColor(title);
    final bgColor = getDashboardBgColor(title);

    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: color.withOpacity(0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          widget.onNavigate(pageIndex);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: bgColor,
                child: Icon(
                  icon,
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget shortcutCard({
    required String title,
    required IconData icon,
    required Widget page,
  }) {
    Color color = const Color(0xFF339BFF);

    if (title.contains('Quotation')) color = Colors.purple;
    if (title.contains('Pending')) color = Colors.orange;
    if (title.contains('Vehicles')) color = Colors.green;

    return Container(
      width: 92,
      margin: const EdgeInsets.only(right: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: () {
          openPage(page);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: color.withOpacity(0.13),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity(0.25),
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget monthlyReportCard(Map<String, dynamic> car, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFD7E5FA),
            child: Icon(
              Icons.directions_car,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              car['type'].toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFD7E5FA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${car['count']} cars',
              style: const TextStyle(
                color: Color(0xFF339BFF),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }
}