import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'vehicle_management_page.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../common/app_result_message.dart';

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
  RealtimeChannel? customersRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    fetchCustomers();
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

    final channel =
        customersRealtimeChannel;

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

  Future<void> fetchCustomers({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final response = await supabase
          .from('customers')
          .select()
          .order(
        'created_at',
        ascending: false,
      );

      if (!mounted) return;

      setState(() {
        customers =
        List<Map<String, dynamic>>.from(
          response,
        );
      });
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load customers: $error',
        );
      } else {
        debugPrint(
          'Realtime customer refresh failed: $error',
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
    if (customersRealtimeChannel != null) {
      return;
    }

    customersRealtimeChannel = supabase
        .channel(
      'admin-customers-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'customers',
      callback: (payload) {
        debugPrint(
          'Admin customer changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vehicles',
      callback: (payload) {
        debugPrint(
          'Customer vehicle relationship changed: '
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
      refreshCustomersFromRealtime,
    );
  }

  Future<void> refreshCustomersFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await fetchCustomers(
        showLoading: false,
      );
    } finally {
      isRealtimeRefreshing = false;
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
    final normalizedName = name.trim();
    final normalizedEmail =
    email.trim().toLowerCase();
    final normalizedPhone = phone.trim();

    if (normalizedName.isEmpty ||
        normalizedEmail.isEmpty ||
        normalizedPhone.isEmpty) {
      showMessage(
        'Please fill in customer name, email and phone number.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_create_customer',
        params: {
          'p_name': normalizedName,
          'p_email': normalizedEmail,
          'p_phone': normalizedPhone,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid customer information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['created'] != true ||
          result['customer_id'] == null) {
        throw Exception(
          'The customer was not created correctly.',
        );
      }

      await fetchCustomers();

      showMessage(
        'Customer added successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchCustomers();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin add customer failed: $error',
      );
      debugPrint(stackTrace.toString());

      showMessage(
        'Failed to add customer: $error',
      );
    }
  }

  Future<void> updateCustomer({
    required String customerId,
    required String name,
    required String email,
    required String phone,
  }) async {
    final normalizedCustomerId =
    customerId.trim();

    final normalizedName = name.trim();
    final normalizedEmail =
    email.trim().toLowerCase();
    final normalizedPhone = phone.trim();

    if (normalizedCustomerId.isEmpty) {
      showMessage(
        'Customer information is missing.',
      );
      return;
    }

    if (normalizedName.isEmpty ||
        normalizedEmail.isEmpty ||
        normalizedPhone.isEmpty) {
      showMessage(
        'Please fill in customer name, email and phone number.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_update_customer',
        params: {
          'p_customer_id':
          normalizedCustomerId,
          'p_name': normalizedName,
          'p_email': normalizedEmail,
          'p_phone': normalizedPhone,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid customer information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['updated'] != true ||
          result['customer_id'] == null) {
        throw Exception(
          'The customer was not updated correctly.',
        );
      }

      await fetchCustomers();

      showMessage(
        'Customer information updated successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchCustomers();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin update customer failed: $error',
      );
      debugPrint(stackTrace.toString());

      showMessage(
        'Failed to update customer: $error',
      );
    }
  }

  Future<void> deleteCustomer(
      String customerId,
      ) async {
    final normalizedCustomerId =
    customerId.trim();

    if (normalizedCustomerId.isEmpty) {
      showMessage(
        'Customer information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_delete_customer',
        params: {
          'p_customer_id':
          normalizedCustomerId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid customer deletion result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['deleted'] != true) {
        throw Exception(
          'The customer was not deleted.',
        );
      }

      final unclaimedCount =
          int.tryParse(
            result['unclaimed_vehicle_count']
                ?.toString() ??
                '0',
          ) ??
              0;

      await fetchCustomers();

      showMessage(
        unclaimedCount > 0
            ? 'Customer deleted. $unclaimedCount vehicle(s) changed to Pending Claim.'
            : 'Customer deleted successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchCustomers();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin delete customer failed: $error',
      );
      debugPrint(stackTrace.toString());

      showMessage(
        'Failed to delete customer: $error',
      );
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

  Future<List<Map<String, dynamic>>> fetchCustomerVehicles(
      String customerId,
      ) async {
    final normalizedCustomerId =
    customerId.trim();

    if (normalizedCustomerId.isEmpty) {
      return [];
    }

    final response = await supabase
        .from('vehicles')
        .select()
        .eq(
      'customer_id',
      normalizedCustomerId,
    )
        .order(
      'created_at',
      ascending: false,
    );

    return List<Map<String, dynamic>>.from(
      response,
    );
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
    final customerId =
    customer['customer_id']
        ?.toString()
        .trim();

    final vehicleId =
    vehicle['vehicle_id']
        ?.toString()
        .trim();

    if (customerId == null ||
        customerId.isEmpty ||
        vehicleId == null ||
        vehicleId.isEmpty) {
      showMessage(
        'Customer or vehicle information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_assign_pending_vehicle',
        params: {
          'p_customer_id': customerId,
          'p_vehicle_id': vehicleId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle assignment result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['assigned'] != true) {
        throw Exception(
          'The vehicle was not assigned.',
        );
      }

      await fetchCustomers();

      if (!mounted) return;

      Navigator.pop(context);
      Navigator.pop(context);

      await fetchCustomers();

      final updatedCustomer =
      customers.firstWhere(
            (item) =>
        item['customer_id'] ==
            customerId,
        orElse: () => customer,
      );

      showCustomerDetails(
        updatedCustomer,
      );

      showMessage(
        'Vehicle assigned to customer successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchCustomers();
    } catch (error, stackTrace) {
      debugPrint(
        'Assign vehicle failed: $error',
      );
      debugPrint(stackTrace.toString());

      showMessage(
        'Failed to assign vehicle: $error',
      );
    }
  }

  void openCustomerVehicle({
    required BuildContext dialogContext,
    required Map<String, dynamic> vehicle,
  }) {
    final vehicleId =
    vehicle['vehicle_id']
        ?.toString()
        .trim();

    final plateNumber =
    vehicle['plate_number']
        ?.toString()
        .trim();

    if (vehicleId == null ||
        vehicleId.isEmpty) {
      showMessage(
        'Vehicle information is missing.',
      );
      return;
    }

    /*
   * Close Customer Details first.
   */
    Navigator.pop(dialogContext);

    /*
   * Open Vehicle Management after the
   * Customer Details dialog is closed.
   */
    WidgetsBinding.instance.addPostFrameCallback(
          (_) {
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                VehicleManagementPage(
                  initialVehicleId: vehicleId,
                  initialPlateNumber:
                  plateNumber,
                ),
          ),
        );
      },
    );
  }

  void showCustomerDetails(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: fetchCustomerVehicles(
            customer['customer_id'].toString(),
          ),
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
                        'Customer Vehicles',
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
                            'No vehicles assigned to this customer.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        Column(
                          children: vehicles.map((vehicle) {
                            return buildVehicleSmallCard(
                              vehicle,
                              onTap: () {
                                openCustomerVehicle(
                                  dialogContext: context,
                                  vehicle: vehicle,
                                );
                              },
                            );
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

                            if (name.isEmpty ||
                                email.isEmpty ||
                                phone.isEmpty) {
                              showMessage(
                                'Please fill in customer name, email and phone number.',
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

                if (name.isEmpty ||
                    email.isEmpty ||
                    phone.isEmpty) {
                  showMessage(  'Please fill in customer name, email and phone number.');
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
                  'Deletion is only allowed when the customer has no booking, quotation, pending service or service record. Linked vehicles will be changed to Pending Claim.',
                  style: TextStyle(
                    color: Colors.black54,
                  ),
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

  Widget buildVehicleSmallCard(
      Map<String, dynamic> vehicle, {
        required VoidCallback onTap,
      }) {
    final status =
        vehicle['verification_status']
            ?.toString() ??
            'Pending Claim';

    Color statusColor;
    IconData statusIcon;

    if (status == 'Verified' ||
        status == 'Link Record') {
      statusColor = Colors.green;
      statusIcon = Icons.verified;
    } else if (status == 'Rejected') {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.pending_actions;
    }

    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor:
                Color(0xFFD7E5FA),
                child: Icon(
                  Icons.directions_car,
                  color: Color(0xFF339BFF),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle['plate_number']
                          ?.toString() ??
                          '',
                      style: const TextStyle(
                        fontWeight:
                        FontWeight.bold,
                        fontSize: 15,
                        color:
                        Color(0xFF1F2937),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      vehicle['car_model']
                          ?.toString() ??
                          '',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Container(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor
                            .withOpacity(0.12),
                        borderRadius:
                        BorderRadius.circular(
                          20,
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: [
                          Icon(
                            statusIcon,
                            color: statusColor,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight:
                              FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              const Column(
                children: [
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Color(0xFF339BFF),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'View',
                    style: TextStyle(
                      color: Color(0xFF339BFF),
                      fontSize: 10,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
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

    AppResultMessage.show(
      context,
      message: message,
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
        onRefresh: () => fetchCustomers(),
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