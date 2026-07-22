import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import 'package:url_launcher/url_launcher.dart';
import '../common/app_result_message.dart';

class CustomerDashboardContent extends StatefulWidget {
  final Function(int) onNavigate;

  const CustomerDashboardContent({
    super.key,
    required this.onNavigate,
  });

  @override
  State<CustomerDashboardContent> createState() =>
      _CustomerDashboardContentState();
}

class _CustomerDashboardContentState
    extends State<CustomerDashboardContent> {
  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  String selectedType = 'Monthly';
  String selectedPeriod = '';

  Map<String, dynamic>? currentCustomer;
  Map<String, dynamic>? workshopProfile;
  List<Map<String, dynamic>> workshopPhotos = [];

  int vehicleCount = 0;
  int bookingCount = 0;
  int quotationCount = 0;
  int recordCount = 0;

  List<Map<String, dynamic>> customerVehicles = [];
  List<Map<String, dynamic>> serviceRecords = [];
  List<Map<String, dynamic>> analysisData = [];

  @override
  void initState() {
    super.initState();

    loadDashboardData();

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

  Future<void> loadDashboardData() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await fetchWorkshopProfile();
      await fetchWorkshopPhotos();
      await fetchVehicles();
      await fetchBookings();
      await fetchQuotations();
      await fetchServiceRecords();

      generateAnalysisPeriods();
      generateAnalysisData();
    } catch (error) {
      showMessage('Failed to load dashboard: $error');
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

  Future<void> fetchWorkshopProfile() async {
    final response = await supabase
        .from('workshop_profile')
        .select()
        .eq('id', 1)
        .maybeSingle();

    workshopProfile = response == null
        ? null
        : Map<String, dynamic>.from(response);
  }

  Future<void> fetchWorkshopPhotos() async {
    final response = await supabase
        .from('workshop_photos')
        .select()
        .order('display_order', ascending: true);

    workshopPhotos = List<Map<String, dynamic>>.from(response);
  }

  Future<void> fetchVehicles() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('vehicles')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .order('created_at', ascending: false);

    customerVehicles = List<Map<String, dynamic>>.from(response);
    vehicleCount = customerVehicles.length;
  }

  Future<void> fetchBookings() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('bookings')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .eq('status', 'Booked');

    bookingCount = List<Map<String, dynamic>>.from(response).length;
  }

  Future<void> fetchQuotations() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('quotations')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .eq('status', 'Sent');

    quotationCount = List<Map<String, dynamic>>.from(response).length;
  }

  Future<void> fetchServiceRecords() async {
    if (customerVehicles.isEmpty) {
      serviceRecords = [];
      recordCount = 0;
      return;
    }

    final vehicleIds = customerVehicles
        .map((vehicle) => vehicle['vehicle_id'])
        .where((id) => id != null)
        .toList();

    final response = await supabase.from('service_records').select('''
      *,
      vehicles(plate_number, car_model),
      service_record_items(item_id, item_name, quantity, price)
    ''')
        .inFilter('vehicle_id', vehicleIds)
        .order('created_at', ascending: false);

    serviceRecords = List<Map<String, dynamic>>.from(response);
    recordCount = serviceRecords.length;
  }

  List<String> get availablePeriods {
    final periods = <String>{};

    for (final record in serviceRecords) {
      final createdAt = record['created_at'];
      if (createdAt == null) continue;

      final date = DateTime.parse(createdAt).toLocal();

      if (selectedType == 'Monthly') {
        periods.add('${getMonthName(date.month)} ${date.year}');
      } else {
        periods.add(date.year.toString());
      }
    }

    final list = periods.toList();

    list.sort((a, b) {
      if (selectedType == 'Yearly') {
        return int.parse(b).compareTo(int.parse(a));
      }

      final aDate = parseMonthYear(a);
      final bDate = parseMonthYear(b);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  void generateAnalysisPeriods() {
    final periods = availablePeriods;

    if (periods.isNotEmpty) {
      selectedPeriod = periods.first;
    } else {
      final now = DateTime.now();
      selectedPeriod = selectedType == 'Monthly'
          ? '${getMonthName(now.month)} ${now.year}'
          : now.year.toString();
    }
  }

  void generateAnalysisData() {
    final Map<String, Map<String, dynamic>> grouped = {};

    for (final record in serviceRecords) {
      final createdAt = record['created_at'];
      if (createdAt == null) continue;

      final date = DateTime.parse(createdAt).toLocal();

      final recordPeriod = selectedType == 'Monthly'
          ? '${getMonthName(date.month)} ${date.year}'
          : date.year.toString();

      if (recordPeriod != selectedPeriod) continue;

      final vehicle = record['vehicles'] ?? {};
      final plate = vehicle['plate_number'] ?? 'Unknown';

      final total = double.tryParse(record['total_price'].toString()) ?? 0;

      if (!grouped.containsKey(plate)) {
        grouped[plate] = {
          'plate': plate,
          'count': 0,
          'spend': 0.0,
        };
      }

      grouped[plate]!['count'] = grouped[plate]!['count'] + 1;
      grouped[plate]!['spend'] = grouped[plate]!['spend'] + total;
    }

    analysisData = grouped.values.toList();
  }

  DateTime parseMonthYear(String value) {
    final parts = value.split(' ');
    final month = getMonthNumber(parts[0]);
    final year = int.parse(parts[1]);
    return DateTime(year, month);
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

  double get totalSpend {
    double total = 0;

    for (final item in analysisData) {
      total += double.tryParse(item['spend'].toString()) ?? 0;
    }

    return total;
  }

  int get totalServiceCount {
    int total = 0;

    for (final item in analysisData) {
      total += int.tryParse(item['count'].toString()) ?? 0;
    }

    return total;
  }

  void changeAnalysisType(String value) {
    setState(() {
      selectedType = value;
      generateAnalysisPeriods();
      generateAnalysisData();
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = analysisData;

    final int maxCount = data.isEmpty
        ? 1
        : data
        .map((item) => item['count'] as int)
        .reduce((a, b) => a > b ? a : b);

    final name = currentCustomer?['name'] ??
        currentCustomer?['full_name'] ??
        'Customer';

    final periods = availablePeriods;
    final dropdownPeriods = periods.isEmpty ? [selectedPeriod] : periods;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Customer Home'),
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
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: loadDashboardData,
        child: SingleChildScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
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
                    Text(
                      'Welcome, $name 👋',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Manage your vehicles, bookings, quotations and service records.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 145,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          dashboardCard(
                            title: 'My\nVehicles',
                            value: '$vehicleCount',
                            icon: Icons.directions_car,
                            pageIndex: 1,
                          ),
                          dashboardCard(
                            title: 'Book\nService',
                            value: '$bookingCount',
                            icon: Icons.calendar_month,
                            pageIndex: 2,
                          ),
                          dashboardCard(
                            title: 'My\nQuotation',
                            value: '$quotationCount',
                            icon: Icons.receipt_long,
                            pageIndex: 3,
                          ),
                          dashboardCard(
                            title: 'Service\nRecords',
                            value: '$recordCount',
                            icon: Icons.history,
                            pageIndex: 4,
                          ),
                          dashboardCard(
                            title: 'Profile',
                            value: 'Me',
                            icon: Icons.person,
                            pageIndex: 5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [

                    workshopCard(),

                    workshopGallery(),

                    sectionTitle('Service Analysis'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedType,
                            decoration: inputDecoration('Analysis Type'),
                            items: const [
                              DropdownMenuItem(
                                value: 'Monthly',
                                child: Text('Monthly'),
                              ),
                              DropdownMenuItem(
                                value: 'Yearly',
                                child: Text('Yearly'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                changeAnalysisType(value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedPeriod,
                            decoration: inputDecoration(
                              selectedType == 'Monthly'
                                  ? 'Select Month'
                                  : 'Select Year',
                            ),
                            items: dropdownPeriods.map((period) {
                              return DropdownMenuItem(
                                value: period,
                                child: Text(
                                  period,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  selectedPeriod = value;
                                  generateAnalysisData();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        summaryBox(
                          title: 'Selected Period',
                          value: selectedPeriod,
                          icon: Icons.date_range,
                        ),
                        const SizedBox(width: 12),
                        summaryBox(
                          title: 'Total Spend',
                          value: 'RM ${totalSpend.toStringAsFixed(2)}',
                          icon: Icons.payments,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    chartCard(data, maxCount),
                    const SizedBox(height: 22),
                    sectionTitle('Analysis Data'),
                    const SizedBox(height: 12),
                    if (data.isEmpty)
                      emptyCard('No service analysis data for this period.')
                    else
                      ...data.map((car) {
                        return analysisCard(car);
                      }),
                    const SizedBox(height: 14),
                    sectionTitle('Total Spending'),
                    const SizedBox(height: 12),
                    totalSummaryCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton.small(
        heroTag: 'customerDashboardBackToTop',
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: scrollToTop,
        child: const Icon(Icons.keyboard_arrow_up),
      )
          : null,
    );
  }

  Widget dashboardCard({
    required String title,
    required String value,
    required IconData icon,
    required int pageIndex,
  }) {
    return Container(
      width: 135,
      margin: const EdgeInsets.only(right: 12),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          widget.onNavigate(pageIndex);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFD7E5FA),
              child: Icon(
                icon,
                color: const Color(0xFF339BFF),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  InputDecoration inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget summaryBox({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
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
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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

  Widget chartCard(List<Map<String, dynamic>> data, int maxCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$selectedPeriod Service Bar Chart',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: data.isEmpty
                  ? const Center(
                child: Text(
                  'No chart data available.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
                  : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: data.map((car) {
                    final int count = car['count'] as int;
                    final double spend =
                        double.tryParse(car['spend'].toString()) ?? 0;

                    final double barHeight =
                    maxCount == 0 ? 0 : (count / maxCount) * 180;

                    return Container(
                      width: 105,
                      margin: const EdgeInsets.only(right: 18),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '$count',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            height: barHeight,
                            width: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF339BFF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            car['plate'].toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'RM ${spend.toStringAsFixed(0)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
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
    );
  }

  Widget analysisCard(Map<String, dynamic> car) {
    final spend = double.tryParse(car['spend'].toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFD7E5FA),
            child: Icon(
              Icons.directions_car,
              color: Color(0xFF339BFF),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  car['plate'].toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${car['count']} service records',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'RM ${spend.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF339BFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget totalSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFD7E5FA),
            child: Icon(
              Icons.summarize,
              color: Color(0xFF339BFF),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalServiceCount service records',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'RM ${totalSpend.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF339BFF),
            ),
          ),
        ],
      ),
    );
  }

  void showWorkshopInfoSheet() {
    if (workshopProfile == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  CircleAvatar(
                    radius: 45,
                    backgroundColor: const Color(0xFFD7E5FA),
                    backgroundImage: workshopProfile!['logo_url'] != null &&
                        workshopProfile!['logo_url'].toString().isNotEmpty
                        ? NetworkImage(workshopProfile!['logo_url'])
                        : null,
                    child: workshopProfile!['logo_url'] == null
                        ? const Icon(
                      Icons.store,
                      size: 45,
                      color: Color(0xFF339BFF),
                    )
                        : null,
                  ),

                  const SizedBox(height: 16),

                  Center(
                    child: Text(
                      workshopProfile!['workshop_name'] ?? 'Workshop',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  infoRow(Icons.location_on, 'Address',
                      workshopProfile!['address'] ?? '-'),
                  infoRow(Icons.phone, 'Phone',
                      workshopProfile!['phone'] ?? '-'),
                  infoRow(Icons.access_time, 'Working Hours',
                      workshopProfile!['working_hours'] ?? '-'),

                  const SizedBox(height: 18),

                  workshopGallery(),
                  const SizedBox(height: 22),

                  Row(
                    children: [

                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: openGoogleMaps,
                          icon: const Icon(Icons.navigation),
                          label: const Text('Map'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF339BFF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: callWorkshop,
                          icon: const Icon(Icons.call),
                          label: const Text('Phone'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: whatsappWorkshop,
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp Workshop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> openGoogleMaps() async {
    if (workshopProfile == null) return;

    final lat = workshopProfile!['latitude'];
    final lng = workshopProfile!['longitude'];

    if (lat == null || lng == null) return;

    final Uri url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> callWorkshop() async {
    if (workshopProfile == null) return;

    final phone = workshopProfile!['phone'];

    if (phone == null || phone.toString().isEmpty) return;

    final Uri url = Uri.parse('tel:$phone');

    await launchUrl(url);
  }

  Future<void> whatsappWorkshop() async {
    if (workshopProfile == null) return;

    String phone =
        workshopProfile!['phone']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ??
            '';

    if (phone.isEmpty) return;

    if (phone.startsWith('0')) {
      phone = '6$phone';
    }

    final Uri url = Uri.parse(
      'https://wa.me/$phone?text=Hello%20I%20would%20like%20to%20ask%20about%20your%20car%20service.',
    );

    await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
  }

  Widget infoRow(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF339BFF)),
          const SizedBox(width: 12),
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
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget workshopCard() {
    if (workshopProfile == null) {
      return const SizedBox();
    }

    return GestureDetector(
        onTap: showWorkshopInfoSheet,
        child: Container(
          margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [

              CircleAvatar(
                radius: 34,
                backgroundColor: const Color(0xFFD7E5FA),
                backgroundImage:
                workshopProfile!['logo_url'] != null &&
                    workshopProfile!['logo_url'].toString().isNotEmpty
                    ? NetworkImage(workshopProfile!['logo_url'])
                    : null,
                child: workshopProfile!['logo_url'] == null
                    ? const Icon(
                  Icons.store,
                  size: 34,
                  color: Color(0xFF339BFF),
                )
                    : null,
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Text(
                      workshopProfile!['workshop_name'] ??
                          'Workshop',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      workshopProfile!['address'] ?? '',
                      style: const TextStyle(
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      '🕘 ${workshopProfile!['working_hours'] ?? '-'}',
                    ),

                    Text(
                      '📞 ${workshopProfile!['phone'] ?? '-'}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  void showWorkshopPhotoPreview(Map<String, dynamic> photo) {
    final imageUrl = photo['image_url'].toString();
    final title = (photo['title'] ?? photo['caption'] ?? 'Workshop Photo')
        .toString();

    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),

                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 28,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget workshopGallery() {
    if (workshopPhotos.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('Workshop Photos'),
        const SizedBox(height: 12),

        SizedBox(
          height: 165,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: workshopPhotos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final photo = workshopPhotos[index];

              return GestureDetector(
                onTap: () => showWorkshopPhotoPreview(photo),
                child: Container(
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          photo['image_url'],
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            color: Colors.black.withOpacity(0.45),
                            child: Text(
                              (photo['title'] ??
                                  photo['caption'] ??
                                  'Workshop Photo')
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
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
            },
          ),
        ),

        const SizedBox(height: 22),
      ],
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