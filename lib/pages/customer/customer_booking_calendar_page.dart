import 'package:flutter/material.dart';
import 'choose_service_type_page.dart';
import '../../services/supabase_service.dart';

class CustomerBookingCalendarPage extends StatefulWidget {
  final Function(Map<String, dynamic>) onBookingConfirmed;

  const CustomerBookingCalendarPage({
    super.key,
    required this.onBookingConfirmed,
  });

  @override
  State<CustomerBookingCalendarPage> createState() =>
      _CustomerBookingCalendarPageState();
}

class _CustomerBookingCalendarPageState
    extends State<CustomerBookingCalendarPage> {
  DateTime currentMonth = DateTime.now();
  DateTime? selectedDate;

  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  int dailyLimit = 10;
  Map<String, int> bookedCount = {};
  Map<String, Map<String, dynamic>> dateSettings = {};

  @override
  void initState() {
    super.initState();

    loadCalendarData();

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

  Future<void> loadCalendarData() async {
    setState(() => isLoading = true);

    try {
      await fetchDefaultDailyLimit();
      await fetchDateSettings();
      await fetchBookingCounts();
    } catch (error) {
      showMessage('Failed to load calendar: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> fetchDefaultDailyLimit() async {
    final response = await supabase
        .from('appointment_settings')
        .select()
        .eq('id', 1)
        .maybeSingle();

    if (response != null) {
      dailyLimit = response['default_daily_limit'] ?? 10;
    }
  }

  Future<void> fetchDateSettings() async {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);

    final response = await supabase
        .from('appointment_date_settings')
        .select()
        .gte('appointment_date', formatDateKey(firstDay))
        .lte('appointment_date', formatDateKey(lastDay));

    final Map<String, Map<String, dynamic>> temp = {};

    for (final item in response) {
      temp[item['appointment_date'].toString()] =
      Map<String, dynamic>.from(item);
    }

    dateSettings = temp;
  }

  Future<void> fetchBookingCounts() async {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);

    final response = await supabase
        .from('bookings')
        .select('appointment_date, status')
        .gte('appointment_date', formatDateKey(firstDay))
        .lte('appointment_date', formatDateKey(lastDay))
        .neq('status', 'Cancelled');

    final Map<String, int> temp = {};

    for (final item in response) {
      final date = item['appointment_date'].toString();
      temp[date] = (temp[date] ?? 0) + 1;
    }

    bookedCount = temp;
  }

  String formatDateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String formatDisplayDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String getMonthName(int month) {
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

    return months[month - 1];
  }

  int getLimitForDate(DateTime date) {
    final key = formatDateKey(date);
    final setting = dateSettings[key];

    if (setting != null && setting['daily_limit'] != null) {
      return setting['daily_limit'];
    }

    return dailyLimit;
  }

  bool isClosed(DateTime date) {
    final key = formatDateKey(date);
    final setting = dateSettings[key];

    return setting != null && setting['is_closed'] == true;
  }

  String getClosedReason(DateTime date) {
    final key = formatDateKey(date);
    final setting = dateSettings[key];

    return setting?['closed_reason'] ?? 'Workshop is closed on this date.';
  }

  bool isFull(DateTime date) {
    final key = formatDateKey(date);
    final limit = getLimitForDate(date);

    return (bookedCount[key] ?? 0) >= limit;
  }

  bool isPastDate(DateTime date) {
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final checkDate = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return checkDate.isBefore(today);
  }

  bool isTodayDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final checkDate = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return checkDate == today;
  }

  bool isUnavailableDate(DateTime date) {
    return isPastDate(date) || isTodayDate(date);
  }
  bool isSelected(DateTime date) {
    if (selectedDate == null) return false;

    return selectedDate!.year == date.year &&
        selectedDate!.month == date.month &&
        selectedDate!.day == date.day;
  }

  int getBookedCount(DateTime date) {
    return bookedCount[formatDateKey(date)] ?? 0;
  }

  int getClosedDaysCount() {
    return dateSettings.values.where((item) => item['is_closed'] == true).length;
  }

  void selectDate(DateTime date) {
    if (isPastDate(date)) {
      showMessage('Past dates cannot be selected.');
      return;
    }

    if (isTodayDate(date)) {
      showMessage(
        'Same-day booking is not available. Please select tomorrow or a later date.',
      );
      return;
    }

    if (isClosed(date)) {
      showMessage(getClosedReason(date));
      return;
    }

    if (isFull(date)) {
      showMessage('This date is fully booked.');
      return;
    }

    setState(() {
      selectedDate = date;
    });
  }

  void goToChooseServicePage() {
    if (selectedDate == null) {
      showMessage('Please select an available date.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChooseServiceTypePage(
          selectedDate: formatDisplayDate(selectedDate!),
          onBookingConfirmed: widget.onBookingConfirmed,
        ),
      ),
    );
  }

  Future<void> goPreviousMonth() async {
    setState(() {
      currentMonth = DateTime(
        currentMonth.year,
        currentMonth.month - 1,
      );
      selectedDate = null;
    });

    await loadCalendarData();
  }

  Future<void> goNextMonth() async {
    setState(() {
      currentMonth = DateTime(
        currentMonth.year,
        currentMonth.month + 1,
      );
      selectedDate = null;
    });

    await loadCalendarData();
  }

  List<DateTime?> buildCalendarDays() {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);

    final List<DateTime?> days = [];

    final startEmptyBox = firstDay.weekday % 7;

    for (int i = 0; i < startEmptyBox; i++) {
      days.add(null);
    }

    for (int day = 1; day <= lastDay.day; day++) {
      days.add(DateTime(currentMonth.year, currentMonth.month, day));
    }

    return days;
  }

  Color getDayColor(DateTime date) {
    if (isSelected(date)) return const Color(0xFF339BFF);
    if (isClosed(date)) return Colors.red.shade400;
    if (isFull(date)) return Colors.grey.shade400;
    if (isUnavailableDate(date)) {
      return Colors.grey.shade200;
    }
    return Colors.white;
  }

  Color getTextColor(DateTime date) {
    if (isSelected(date) || isClosed(date)) return Colors.white;
    if (isUnavailableDate(date)) {
      return Colors.black38;
    }
    return Colors.black87;
  }

  String getStatusText(DateTime date) {
    if (isPastDate(date)) return 'Past';
    if (isTodayDate(date)) return 'Today';
    if (isClosed(date)) return 'Closed';
    if (isFull(date)) return 'Full';

    final limit = getLimitForDate(date);
    return '${getBookedCount(date)}/$limit';
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget buildLegend({
    required Color color,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 12),
        ),
      ],
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

  Widget buildCircleButton({
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
    final calendarDays = buildCalendarDays();

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Select Appointment Date'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: loadCalendarData,
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
                      'Choose Appointment Date',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select an available date before choosing service type',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.event_available,
                          title: 'Daily Limit',
                          value: '$dailyLimit',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.block,
                          title: 'Closed Days',
                          value: '${getClosedDaysCount()}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                100,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    Container(
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
                      child: Column(
                        children: [
                          Row(
                            children: [
                              buildCircleButton(
                                icon: Icons.arrow_back_ios_new,
                                onTap: goPreviousMonth,
                              ),
                              Expanded(
                                child: Text(
                                  '${getMonthName(currentMonth.month)} '
                                      '${currentMonth.year}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              buildCircleButton(
                                icon: Icons.arrow_forward_ios,
                                onTap: goNextMonth,
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          const Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                            children: [
                              Text(
                                'Sun',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Mon',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Tue',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Wed',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Thu',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Fri',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Sat',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          GridView.builder(
                            shrinkWrap: true,
                            physics:
                            const NeverScrollableScrollPhysics(),
                            itemCount: calendarDays.length,
                            gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.72,
                            ),
                            itemBuilder: (context, index) {
                              final date = calendarDays[index];

                              if (date == null) {
                                return const SizedBox();
                              }

                              return InkWell(
                                borderRadius:
                                BorderRadius.circular(12),
                                onTap: () {
                                  selectDate(date);
                                },
                                child: AnimatedContainer(
                                  duration:
                                  const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: getDayColor(date),
                                    borderRadius:
                                    BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected(date)
                                          ? const Color(0xFF339BFF)
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${date.day}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: getTextColor(date),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        getStatusText(date),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: getTextColor(date),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 16),

                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              buildLegend(
                                color: Colors.white,
                                text: 'Available',
                              ),
                              buildLegend(
                                color: const Color(0xFF339BFF),
                                text: 'Selected',
                              ),
                              buildLegend(
                                color: Colors.grey.shade400,
                                text: 'Full',
                              ),
                              buildLegend(
                                color: Colors.red.shade400,
                                text: 'Shop Closed',
                              ),
                              buildLegend(
                                color: Colors.grey.shade200,
                                text: 'Past / Today',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (selectedDate != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
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
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFD7E5FA),
                            child: Icon(
                              Icons.check_circle,
                              color: Color(0xFF339BFF),
                            ),
                          ),
                          title: const Text(
                            'Selected Date',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            formatDisplayDate(selectedDate!),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF4FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Color(0xFF339BFF),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Select an available date, then continue to choose your service type.',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                const Color(0xFF339BFF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: goToChooseServicePage,
                              icon: const Icon(
                                Icons.arrow_forward,
                              ),
                              label: const Text(
                                'Next: Choose Service Type',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
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
          ],
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton.small(
        heroTag: 'bookingCalendarBackToTop',
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