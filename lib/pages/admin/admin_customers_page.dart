import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';

class AdminCustomersPage extends StatefulWidget {
  const AdminCustomersPage({super.key});

  @override
  State<AdminCustomersPage> createState() => _AdminCustomersPageState();
}

class _AdminCustomersPageState extends State<AdminCustomersPage> {
  String searchText = '';
  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  List<Map<String, dynamic>> customers = [];

  @override
  void initState() {
    super.initState();
    fetchCustomers();

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

  Future<void> fetchCustomers() async {
    setState(() => isLoading = true);

    try {
      final response = await supabase
          .from('customers')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          customers = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (error) {
      showMessage('Failed to load customers: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get filteredCustomers {
    return customers.where((customer) {
      final name = (customer['name'] ?? '').toString().toLowerCase();
      final email = (customer['email'] ?? '').toString().toLowerCase();
      final phone = (customer['phone'] ?? '').toString().toLowerCase();
      final search = searchText.toLowerCase();

      return name.contains(search) ||
          email.contains(search) ||
          phone.contains(search);
    }).toList();
  }

  Future<void> addCustomer({
    required String name,
    required String email,
    required String phone,
  }) async {
    try {
      await supabase.from('customers').insert({
        'name': name,
        'email': email,
        'phone': phone,
      });

      await fetchCustomers();
      showMessage('Customer added successfully.');
    } catch (error) {
      showMessage('Failed to add customer: $error');
    }
  }

  Future<void> updateCustomer({
    required String customerId,
    required String name,
    required String email,
    required String phone,
  }) async {
    try {
      await supabase.from('customers').update({
        'name': name,
        'email': email,
        'phone': phone,
      }).eq('customer_id', customerId);

      await supabase.from('vehicles').update({
        'customer_name': name.toUpperCase(),
      }).eq('customer_id', customerId);

      await fetchCustomers();
      showMessage('Customer information updated successfully.');
    } catch (error) {
      showMessage('Failed to update customer: $error');
    }
  }

  Future<void> deleteCustomer(String customerId) async {
    try {
      await supabase.from('vehicles').update({
        'customer_id': null,
        'customer_name': null,
        'verification_status': 'Pending Claim',
      }).eq('customer_id', customerId);

      await supabase.from('customers').delete().eq('customer_id', customerId);

      await fetchCustomers();
      showMessage('Customer deleted. Claimed vehicles changed to Pending Claim.');
    } catch (error) {
      showMessage('Failed to delete customer: $error');
    }
  }

  Future<List<Map<String, dynamic>>> fetchVerifiedVehicles(
      String customerId,
      ) async {
    final response = await supabase
        .from('vehicles')
        .select()
        .eq('customer_id', customerId)
        .eq('verification_status', 'Verified')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> searchPendingVehicles(
      String plateKeyword,
      ) async {
    final response = await supabase
        .from('vehicles')
        .select()
        .eq('verification_status', 'Pending Claim')
        .ilike('plate_number', '%$plateKeyword%')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> assignVehicleToCustomer({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> vehicle,
  }) async {
    try {
      await supabase.from('vehicles').update({
        'customer_id': customer['customer_id'],
        'customer_name': customer['name'].toString().toUpperCase(),
        'verification_status': 'Verified',
      }).eq('vehicle_id', vehicle['vehicle_id']);

      await fetchCustomers();

      if (!mounted) return;
      Navigator.pop(context); // close add vehicle dialog
      Navigator.pop(context); // close old customer detail dialog

      await fetchCustomers();

      final updatedCustomer = customers.firstWhere(
            (item) => item['customer_id'] == customer['customer_id'],
        orElse: () => customer,
      );

      showCustomerDetails(updatedCustomer);

      showMessage('Vehicle assigned to customer successfully.');
    } catch (error) {
      showMessage('Failed to assign vehicle: $error');
    }
  }

  void showCustomerDetails(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: fetchVerifiedVehicles(customer['customer_id'].toString()),
          builder: (context, snapshot) {
            final vehicles = snapshot.data ?? [];

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 35,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Customer Details',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      showEditCustomerDialog(customer);
                    },
                    icon: const Icon(
                      Icons.edit,
                      color: Color(0xFF339BFF),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildDetailBox('Name', customer['name'] ?? ''),
                      buildDetailBox('Email', customer['email'] ?? ''),
                      buildDetailBox('Phone', customer['phone'] ?? ''),
                      const SizedBox(height: 18),
                      const Text(
                        'Verified Vehicles',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(child: CircularProgressIndicator())
                      else if (vehicles.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'No verified vehicles found.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        Column(
                          children: vehicles.map((vehicle) {
                            return buildVehicleSmallCard(vehicle);
                          }).toList(),
                        ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF339BFF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            showAddVehicleToCustomerDialog(customer);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Vehicle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  void showAddVehicleToCustomerDialog(Map<String, dynamic> customer) {
    final plateSearchController = TextEditingController();
    List<Map<String, dynamic>> vehicleResults = [];
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> searchVehicle(String value) async {
              setDialogState(() => isSearching = true);

              try {
                final result = await searchPendingVehicles(value.trim());
                setDialogState(() => vehicleResults = result);
              } catch (error) {
                showMessage('Failed to search vehicle: $error');
              } finally {
                setDialogState(() => isSearching = false);
              }
            }

            return AlertDialog(
              title: const Text('Add Vehicle To Customer'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: plateSearchController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          return newValue.copyWith(
                            text: newValue.text.toUpperCase(),
                            selection: newValue.selection,
                          );
                        }),
                      ],
                      decoration: InputDecoration(
                        hintText: 'Search unclaimed vehicle plate',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: searchVehicle,
                    ),
                    const SizedBox(height: 14),
                    if (isSearching)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      )
                    else if (vehicleResults.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Type vehicle plate number to search pending vehicles.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    else
                      SizedBox(
                        height: 280,
                        child: ListView.builder(
                          itemCount: vehicleResults.length,
                          itemBuilder: (context, index) {
                            final vehicle = vehicleResults[index];

                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFD7E5FA),
                                  child: Icon(
                                    Icons.directions_car,
                                    color: Color(0xFF339BFF),
                                  ),
                                ),
                                title: Text(
                                  '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: const Text('Pending Claim'),
                                onTap: () async {
                                  await assignVehicleToCustomer(
                                    customer: customer,
                                    vehicle: vehicle,
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  void showAddCustomerDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();

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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Color(0xFF339BFF),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Add New Customer',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a customer profile for booking and vehicle management.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  buildInputBox(
                    controller: nameController,
                    label: 'Customer Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 14),
                  buildInputBox(
                    controller: emailController,
                    label: 'Email Address',
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  buildInputBox(
                    controller: phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                    isNumberOnly: true,
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
                            'Customer information can be edited later if needed.',
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
                            final name = nameController.text.trim();
                            final email = emailController.text.trim();
                            final phone = phoneController.text.trim();

                            if (name.isEmpty || phone.isEmpty) {
                              showMessage(
                                'Please fill in customer name and phone number.',
                              );
                              return;
                            }

                            Navigator.pop(context);

                            await addCustomer(
                              name: name,
                              email: email,
                              phone: phone,
                            );
                          },
                          child: const Text('Save'),
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

  void showEditCustomerDialog(Map<String, dynamic> customer) {
    final nameController =
    TextEditingController(text: customer['name']?.toString() ?? '');
    final emailController =
    TextEditingController(text: customer['email']?.toString() ?? '');
    final phoneController =
    TextEditingController(text: customer['phone']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'Edit Customer',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                buildInputBox(
                  controller: nameController,
                  label: 'Customer Name',
                  icon: Icons.person,
                ),
                const SizedBox(height: 14),
                buildInputBox(
                  controller: emailController,
                  label: 'Email Address',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                buildInputBox(
                  controller: phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  isNumberOnly: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF339BFF),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                final email = emailController.text.trim();
                final phone = phoneController.text.trim();

                if (name.isEmpty || phone.isEmpty) {
                  showMessage('Please fill in customer name and phone number.');
                  return;
                }

                Navigator.pop(context);
                Navigator.pop(context);

                await updateCustomer(
                  customerId: customer['customer_id'].toString(),
                  name: name,
                  email: email,
                  phone: phone,
                );

                final updatedCustomer = customers.firstWhere(
                      (item) => item['customer_id'] == customer['customer_id'],
                  orElse: () => {
                    ...customer,
                    'name': name,
                    'email': email,
                    'phone': phone,
                  },
                );

                showCustomerDetails(updatedCustomer);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void showDeleteCustomerDialog(Map<String, dynamic> customer) async {
    final vehicles =
    await fetchVerifiedVehicles(customer['customer_id'].toString());

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'Delete Customer',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to delete ${customer['name'] ?? 'this customer'}?',
                ),
                const SizedBox(height: 14),
                if (vehicles.isNotEmpty) ...[
                  const Text(
                    'Claimed vehicles will be changed to Pending Claim:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ...vehicles.map((vehicle) {
                    return Text(
                      '• ${vehicle['plate_number'] ?? ''} - ${vehicle['car_model'] ?? ''}',
                    );
                  }),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Service records will not be affected.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
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
                Navigator.pop(context);
                await deleteCustomer(customer['customer_id'].toString());
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isNumberOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters:
      isNumberOnly ? [FilteringTextInputFormatter.digitsOnly] : [],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
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
              value.toString().isEmpty ? 'Not Provided' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildVehicleSmallCard(Map<String, dynamic> vehicle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_car,
            color: Color(0xFF339BFF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Icon(
            Icons.verified,
            color: Colors.green,
            size: 18,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFD7E5FA),
            child: Icon(
              icon,
              size: 22,
              color: const Color(0xFF339BFF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF339BFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCustomerCard(Map<String, dynamic> customer) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        showCustomerDetails(customer);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFFD7E5FA),
              child: Icon(
                Icons.person,
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
                    customer['name'] ?? '',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  buildInfoLine(
                    icon: Icons.phone,
                    text: customer['phone'] ?? '',
                  ),
                  const SizedBox(height: 5),
                  buildInfoLine(
                    icon: Icons.email,
                    text: customer['email'] ?? '',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Registered',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          showDeleteCustomerDialog(customer);
                        },
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildInfoLine({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: Colors.black45,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text.toString().isEmpty ? 'Not Provided' : text,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ),
      ],
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
    final displayCustomers = filteredCustomers;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Customer Management'),
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
        onRefresh: fetchCustomers,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customer Records',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Manage customer information and vehicle ownership.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildSummaryCard(
                      icon: Icons.people,
                      title: 'Total Customers',
                      value: '${customers.length}',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search customer name, email or phone',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
            if (displayCustomers.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No customers found.',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final customer = displayCustomers[index];
                      return buildCustomerCard(customer);
                    },
                    childCount: displayCustomers.length,
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
              heroTag: 'customerBackToTop',
              backgroundColor: const Color(0xFF339BFF),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up),
            ),
          if (showBackToTop) const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addCustomer',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: showAddCustomerDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Customer'),
          ),
        ],
      ),
    );
  }
}