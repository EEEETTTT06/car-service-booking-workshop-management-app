import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../../services/pdf_service.dart';

class ServiceRecordsPage extends StatefulWidget {
  final String? initialPlate;

  const ServiceRecordsPage({
    super.key,
    this.initialPlate,
  });

  @override
  State<ServiceRecordsPage> createState() => _ServiceRecordsPageState();
}

class _ServiceRecordsPageState extends State<ServiceRecordsPage> {
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  bool showBackToTop = false;
  String searchText = '';
  String selectedQuickFilter = 'All';
  bool isLoading = false;

  Map<String, dynamic>? currentCustomer;
  List<Map<String, dynamic>> customerVehicles = [];
  List<Map<String, dynamic>> records = [];

  @override
  void initState() {
    super.initState();

    if (widget.initialPlate != null && widget.initialPlate!.isNotEmpty) {
      searchText = widget.initialPlate!;
      searchController.text = widget.initialPlate!;
    }

    loadData();

    scrollController.addListener(() {
      if (scrollController.offset > 180 && !showBackToTop) {
        setState(() {
          showBackToTop = true;
        });
      } else if (scrollController.offset <= 180 && showBackToTop) {
        setState(() {
          showBackToTop = false;
        });
      }
    });
  }

  @override
  void dispose() {
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

  Future<void> loadData() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await fetchCustomerVehicles();
      await fetchServiceRecords();
    } catch (error) {
      showMessage('Failed to load service records: $error');
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

  Future<void> fetchCustomerVehicles() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('vehicles')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .order('created_at', ascending: false);

    customerVehicles = List<Map<String, dynamic>>.from(response);
  }

  Future<void> fetchServiceRecords() async {
    if (customerVehicles.isEmpty) {
      records = [];
      return;
    }

    final vehicleIds = customerVehicles
        .map((vehicle) => vehicle['vehicle_id'])
        .where((id) => id != null)
        .toList();

    if (vehicleIds.isEmpty) {
      records = [];
      return;
    }

    final response = await supabase.from('service_records').select('''
      *,
      customers(name, phone, email),
      vehicles(plate_number, car_model),
      service_record_items(item_id, item_name, quantity, price)
    ''')
        .inFilter('vehicle_id', vehicleIds)
        .order('created_at', ascending: false);

    records = List<Map<String, dynamic>>.from(response);
  }

  String formatDate(String? dateText) {
    if (dateText == null || dateText.isEmpty) return 'Not Provided';

    final date = DateTime.parse(dateText).toLocal();

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  DateTime parseDate(String? dateText) {
    if (dateText == null || dateText.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.parse(dateText).toLocal();
  }

  double calculateTotal(List items) {
    double total = 0;

    for (final item in items) {
      final qty = int.tryParse(item['quantity'].toString()) ?? 1;
      final price = double.tryParse(item['price'].toString()) ?? 0;
      total += qty * price;
    }

    return total;
  }

  List<Map<String, dynamic>> get filteredRecords {
    final filtered = records.where((record) {
      final vehicle = record['vehicles'] ?? {};
      final plate = (vehicle['plate_number'] ?? '').toString().toLowerCase();
      final model = (vehicle['car_model'] ?? '').toString().toLowerCase();
      final search = searchText.toLowerCase();

      return plate.contains(search) || model.contains(search);
    }).toList();

    if (selectedQuickFilter == 'Nearest Date') {
      filtered.sort(
            (a, b) => parseDate(b['created_at']).compareTo(
          parseDate(a['created_at']),
        ),
      );
    } else if (selectedQuickFilter == 'Highest Amount') {
      filtered.sort(
            (a, b) {
          final aTotal =
              double.tryParse(a['total_price'].toString()) ?? calculateTotal(a['service_record_items'] as List? ?? []);
          final bTotal =
              double.tryParse(b['total_price'].toString()) ?? calculateTotal(b['service_record_items'] as List? ?? []);
          return bTotal.compareTo(aTotal);
        },
      );
    } else if (selectedQuickFilter == 'Lowest Amount') {
      filtered.sort(
            (a, b) {
          final aTotal =
              double.tryParse(a['total_price'].toString()) ?? calculateTotal(a['service_record_items'] as List? ?? []);
          final bTotal =
              double.tryParse(b['total_price'].toString()) ?? calculateTotal(b['service_record_items'] as List? ?? []);
          return aTotal.compareTo(bTotal);
        },
      );
    }

    return filtered;
  }

  int get totalRecords {
    return records.length;
  }

  double get totalSpend {
    double total = 0;

    for (final record in records) {
      total += double.tryParse(record['total_price'].toString()) ??
          calculateTotal(record['service_record_items'] as List? ?? []);
    }

    return total;
  }

  void showRecordDetailDialog(Map<String, dynamic> record) {
    final vehicle = record['vehicles'] ?? {};
    final items = record['service_record_items'] as List? ?? [];
    final total =
        double.tryParse(record['total_price'].toString()) ?? calculateTotal(items);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  'Service Bill Details',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildDetailRow(
                    'Plate Number',
                    vehicle['plate_number'] ?? '',
                  ),
                  buildDetailRow(
                    'Car Model',
                    vehicle['car_model'] ?? '',
                  ),
                  buildDetailRow(
                    'Date',
                    formatDate(record['created_at']),
                  ),
                  buildDetailRow(
                    'Problem',
                    record['problem_description'] ?? 'No description',
                  ),
                  buildDetailRow(
                    'Action',
                    record['service_action'] ?? 'No action notes',
                  ),
                  buildDetailRow(
                    'Status',
                    record['status'] ?? 'Completed',
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text(
                    'Service / Spare Parts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    const Text('No items found.')
                  else
                    ...items.map((item) {
                      final qty =
                          int.tryParse(item['quantity'].toString()) ?? 1;
                      final price =
                          double.tryParse(item['price'].toString()) ?? 0;
                      final subtotal = qty * price;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(item['item_name'] ?? ''),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text('x$qty'),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'RM ${price.toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'RM ${subtotal.toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF339BFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            await PdfService.viewServiceReport(record);
                          },
                          icon: const Icon(Icons.visibility),
                          label: const Text('View PDF'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await PdfService.shareServiceReport(record);
                          },
                          icon: const Icon(Icons.share),
                          label: const Text('Share PDF'),
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
          Expanded(
            child: Text(value.toString().isEmpty ? 'Not Provided' : value.toString()),
          ),
        ],
      ),
    );
  }

  Widget buildQuickFilterChip(String title) {
    final isSelected = selectedQuickFilter == title;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(title),
        selected: isSelected,
        selectedColor: const Color(0xFF339BFF),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF339BFF),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        side: BorderSide.none,
        onSelected: (_) {
          setState(() {
            selectedQuickFilter = title;
          });
        },
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
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

  Widget buildRecordCard(Map<String, dynamic> record) {
    final vehicle = record['vehicles'] ?? {};
    final items = record['service_record_items'] as List? ?? [];
    final total =
        double.tryParse(record['total_price'].toString()) ?? calculateTotal(items);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          showRecordDetailDialog(record);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: Color(0xFFD7E5FA),
                child: Icon(
                  Icons.history,
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
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.event,
                          size: 15,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          formatDate(record['created_at']),
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Problem: ${record['problem_description'] ?? 'No description'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF339BFF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
    final displayRecords = filteredRecords;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Service Records'),
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
                      'Service History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'View your vehicle service records and bills',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.history,
                          title: 'Records',
                          value: '$totalRecords',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.payments,
                          title: 'Total Spend',
                          value:
                          'RM ${totalSpend.toStringAsFixed(0)}',
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: searchController,
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText:
                        'Search by plate number or car model',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchText.isEmpty
                            ? null
                            : IconButton(
                          tooltip: 'Clear Search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            searchController.clear();

                            setState(() {
                              searchText = '';
                            });
                          },
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

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  14,
                  0,
                  0,
                ),
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    children: [
                      buildQuickFilterChip('All'),
                      buildQuickFilterChip('Nearest Date'),
                      buildQuickFilterChip('Highest Amount'),
                      buildQuickFilterChip('Lowest Amount'),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${displayRecords.length} record(s) found',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      selectedQuickFilter,
                      style: const TextStyle(
                        color: Color(0xFF339BFF),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (displayRecords.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No service records found.',
                    style: TextStyle(
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
                      return buildRecordCard(
                        displayRecords[index],
                      );
                    },
                    childCount: displayRecords.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton.small(
        heroTag: 'serviceRecordsBackToTop',
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