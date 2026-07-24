import 'package:flutter/material.dart';

import 'admin_bookings_page.dart';
import 'admin_customers_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_records_page.dart';
import 'admin_services_page.dart';

class AdminMainPage extends StatefulWidget {
  final int initialIndex;
  final Widget? initialRelatedPage;

  const AdminMainPage({
    super.key,
    this.initialIndex = 0,
    this.initialRelatedPage,
  });

  @override
  State<AdminMainPage> createState() =>
      _AdminMainPageState();
}

class _AdminMainPageState
    extends State<AdminMainPage> {
  late int currentIndex;
  late final List<Widget> pages;

  Widget? relatedPage;

  @override
  void initState() {
    super.initState();

    currentIndex = widget.initialIndex.clamp(0, 4).toInt();
    relatedPage = widget.initialRelatedPage;

    pages = [
      AdminDashboardPage(
        onNavigate: (index) {
          setState(() {
            relatedPage = null;
            currentIndex = index.clamp(0, 4).toInt();
          });
        },
      ),
      const AdminBookingsPage(),
      const AdminCustomersPage(),
      const AdminServicesPage(),
      const AdminRecordsPage(),
    ];
  }

  void changePage(int index) {
    setState(() {
      relatedPage = null;
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      const Color(0xFFD7E5FA),
      body: relatedPage ?? pages[currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color:
              Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          elevation: 0,
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor:
          const Color(0xFF339BFF),
          unselectedItemColor: Colors.grey,
          selectedLabelStyle:
          const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle:
          const TextStyle(
            fontSize: 11,
          ),
          onTap: changePage,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon:
              Icon(Icons.calendar_month),
              label: 'Bookings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: 'Customers',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.build),
              label: 'Services',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment),
              label: 'Records',
            ),
          ],
        ),
      ),
    );
  }
}
