import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../../services/customer_notification_service.dart';

class VehicleManagementPage extends StatefulWidget {
  const VehicleManagementPage({super.key});

  @override
  State<VehicleManagementPage> createState() => _VehicleManagementPageState();
}

class _VehicleManagementPageState extends State<VehicleManagementPage> {
  String searchText = '';
  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  List<Map<String, dynamic>> vehicles = [];
  RealtimeChannel? vehiclesRealtimeChannel;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    fetchVehicles();
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
    final channel = vehiclesRealtimeChannel;

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

  Future<void> fetchVehicles({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final response = await supabase
          .from('vehicles')
          .select()
          .order(
        'created_at',
        ascending: false,
      );

      if (!mounted) return;

      setState(() {
        vehicles = List<Map<String, dynamic>>.from(
          response,
        );
      });
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load vehicles: $error',
        );
      } else {
        debugPrint(
          'Realtime vehicle refresh failed: $error',
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
    if (vehiclesRealtimeChannel != null) {
      return;
    }

    vehiclesRealtimeChannel = supabase
        .channel(
      'admin-vehicles-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vehicles',
      callback: (payload) {
        debugPrint(
          'Admin vehicle changed: '
              '${payload.eventType}',
        );

        refreshVehiclesFromRealtime();
      },
    )
        .subscribe();
  }

  Future<void> refreshVehiclesFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await fetchVehicles(
        showLoading: false,
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String keyword) async {
    final response = await supabase
        .from('customers')
        .select()
        .ilike('name', '%$keyword%')
        .order('name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  List<Map<String, dynamic>> get filteredVehicles {
    return vehicles.where((vehicle) {
      final plate = (vehicle['plate_number'] ?? '').toString().toLowerCase();
      final model = (vehicle['car_model'] ?? '').toString().toLowerCase();
      final owner = (vehicle['customer_name'] ?? '').toString().toLowerCase();
      final search = searchText.toLowerCase();

      return plate.contains(search) ||
          model.contains(search) ||
          owner.contains(search);
    }).toList();
  }

  Color getStatusColor(String status) {
    if (status == 'Verified') return Colors.green;
    if (status == 'Pending Claim') return Colors.orange;
    if (status == 'Rejected') return Colors.red;
    return Colors.red;
  }

  IconData getStatusIcon(String status) {
    if (status == 'Verified') return Icons.verified;
    if (status == 'Pending Claim') return Icons.pending_actions;
    if (status == 'Rejected') return Icons.cancel;
    return Icons.cancel;
  }

  Future<void> sendFcmPushNotification({
    required String customerId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) {
    return CustomerNotificationService.sendToAllDevices(
      customerId: customerId,
      title: title,
      message: message,
      data: data,
    );
  }

  Future<void> createVehicleClaimNotification({
    required Map<String, dynamic> vehicle,
    required String title,
    required String message,
  }) async {
    final customerId = vehicle['customer_id'];

    if (customerId == null) return;

    await supabase.from('notifications').insert({
      'customer_id': customerId,
      'vehicle_id': vehicle['vehicle_id'],
      'title': title,
      'message': message,
      'notification_type': 'vehicle_claim',
      'target_page': 'my_vehicles',
      'is_read': false,
    });

    await sendFcmPushNotification(
      customerId: customerId.toString(),
      title: title,
      message: message,
      data: {
        'notification_type': 'vehicle_claim',
        'target_page': 'my_vehicles',
        'vehicle_id': vehicle['vehicle_id'],
      },
    );
  }

  Future<void> addVehicle({
    required String plate,
    required String model,
    Map<String, dynamic>? customer,
  }) async {
    try {
      final hasCustomer = customer != null;

      await supabase.from('vehicles').insert({
        'plate_number': plate.toUpperCase(),
        'car_model': model.toUpperCase(),
        'customer_id': hasCustomer ? customer['customer_id'] : null,
        'customer_name':
        hasCustomer ? customer['name'].toString().toUpperCase() : '',
        'verification_status': hasCustomer ? 'Verified' : 'Pending Claim',
      });

      await fetchVehicles();
      showMessage('Vehicle added successfully.');
    } catch (error) {
      showMessage('Failed to add vehicle: $error');
    }
  }

  Future<void> updateVehicle({
    required String vehicleId,
    required String plate,
    required String model,
    Map<String, dynamic>? customer,
  }) async {
    try {
      final hasCustomer = customer != null;

      await supabase.from('vehicles').update({
        'plate_number': plate.toUpperCase(),
        'car_model': model.toUpperCase(),
        'customer_id': hasCustomer ? customer['customer_id'] : null,
        'customer_name':
        hasCustomer ? customer['name'].toString().toUpperCase() : '',
        'verification_status': hasCustomer ? 'Verified' : 'Pending Claim',
      }).eq('vehicle_id', vehicleId);

      await fetchVehicles();
      showMessage('Vehicle updated successfully.');
    } catch (error) {
      showMessage('Failed to update vehicle: $error');
    }
  }

  Future<void> approveVehicleClaim(Map<String, dynamic> vehicle) async {
    try {
      final plate = vehicle['plate_number'] ?? 'your vehicle';

      await supabase.from('vehicles').update({
        'verification_status': 'Verified',
      }).eq('vehicle_id', vehicle['vehicle_id']);

      await createVehicleClaimNotification(
        vehicle: vehicle,
        title: 'Vehicle Claim Approved',
        message: 'Your vehicle claim for $plate has been approved.',
      );

      await fetchVehicles();
      showMessage('Vehicle claim approved.');
    } catch (error) {
      showMessage('Failed to approve claim: $error');
    }
  }

  Future<void> rejectVehicleClaim(Map<String, dynamic> vehicle) async {
    try {
      final plate = vehicle['plate_number'] ?? 'your vehicle';

      await supabase.from('vehicles').update({
        'verification_status': 'Rejected',
      }).eq('vehicle_id', vehicle['vehicle_id']);

      await createVehicleClaimNotification(
        vehicle: vehicle,
        title: 'Vehicle Claim Rejected',
        message: 'Your vehicle claim for $plate has been rejected.',
      );

      await fetchVehicles();
      showMessage('Vehicle claim rejected.');
    } catch (error) {
      showMessage('Failed to reject claim: $error');
    }
  }

  Future<void> setVehicleUnclaim(Map<String, dynamic> vehicle) async {
    try {
      await supabase.from('vehicles').update({
        'customer_id': null,
        'customer_name': '',
        'verification_status': 'Pending Claim',
      }).eq('vehicle_id', vehicle['vehicle_id']);

      await fetchVehicles();
      showMessage('Vehicle set as unclaimed.');
    } catch (error) {
      showMessage('Failed to set vehicle as unclaimed: $error');
    }
  }

  Future<void> deleteVehicle(String vehicleId) async {
    try {
      await supabase.from('vehicles').delete().eq('vehicle_id', vehicleId);

      await fetchVehicles();
      showMessage('Vehicle deleted successfully.');
    } catch (error) {
      showMessage('Failed to delete vehicle: $error');
    }
  }

  void showAddVehicleDialog() {
    final plateController = TextEditingController();
    final modelController = TextEditingController();
    final ownerController = TextEditingController();
    Map<String, dynamic>? selectedCustomer;

    showVehicleFormDialog(
      title: 'Add Vehicle',
      plateController: plateController,
      modelController: modelController,
      ownerController: ownerController,
      selectedCustomer: selectedCustomer,
      onCustomerSelected: (customer) {
        selectedCustomer = customer;
        ownerController.text = customer['name'].toString().toUpperCase();
      },
      onCustomerCleared: () {
        selectedCustomer = null;
        ownerController.clear();
      },
      onSave: () async {
        if (plateController.text.trim().isEmpty ||
            modelController.text.trim().isEmpty) {
          showMessage('Please enter plate number and car model.');
          return;
        }

        Navigator.pop(context);

        await addVehicle(
          plate: plateController.text.trim(),
          model: modelController.text.trim(),
          customer: selectedCustomer,
        );
      },
    );
  }

  void showEditVehicleDialog(Map<String, dynamic> vehicle) {
    final plateController =
    TextEditingController(text: vehicle['plate_number'] ?? '');
    final modelController =
    TextEditingController(text: vehicle['car_model'] ?? '');
    final ownerController =
    TextEditingController(text: vehicle['customer_name'] ?? '');

    Map<String, dynamic>? selectedCustomer;

    if (vehicle['customer_id'] != null &&
        (vehicle['customer_name'] ?? '').toString().isNotEmpty) {
      selectedCustomer = {
        'customer_id': vehicle['customer_id'],
        'name': vehicle['customer_name'],
      };
    }

    showVehicleFormDialog(
      title: 'Edit Vehicle',
      plateController: plateController,
      modelController: modelController,
      ownerController: ownerController,
      selectedCustomer: selectedCustomer,
      onCustomerSelected: (customer) {
        selectedCustomer = customer;
        ownerController.text = customer['name'].toString().toUpperCase();
      },
      onCustomerCleared: () {
        selectedCustomer = null;
        ownerController.clear();
      },
      onSave: () async {
        if (plateController.text.trim().isEmpty ||
            modelController.text.trim().isEmpty) {
          showMessage('Please enter plate number and car model.');
          return;
        }

        Navigator.pop(context);

        await updateVehicle(
          vehicleId: vehicle['vehicle_id'].toString(),
          plate: plateController.text.trim(),
          model: modelController.text.trim(),
          customer: selectedCustomer,
        );
      },
    );
  }

  void showVehicleFormDialog({
    required String title,
    required TextEditingController plateController,
    required TextEditingController modelController,
    required TextEditingController ownerController,
    required Map<String, dynamic>? selectedCustomer,
    required Function(Map<String, dynamic>) onCustomerSelected,
    required VoidCallback onCustomerCleared,
    required VoidCallback onSave,
  }) {
    Map<String, dynamic>? currentCustomer = selectedCustomer;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF339BFF), Color(0xFF63B3FF)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.directions_car,
                              color: Colors.white,
                              size: 44,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Register vehicle information and assign owner if available.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      buildInputBox(
                        controller: plateController,
                        label: 'Plate Number',
                        icon: Icons.confirmation_number,
                      ),
                      const SizedBox(height: 16),

                      buildInputBox(
                        controller: modelController,
                        label: 'Car Model',
                        icon: Icons.directions_car,
                      ),
                      const SizedBox(height: 16),

                      buildOwnerBox(
                        controller: ownerController,
                        onSearch: () async {
                          final customer = await showCustomerSearchDialog();

                          if (customer != null) {
                            setDialogState(() {
                              currentCustomer = customer;
                              ownerController.text =
                                  customer['name'].toString().toUpperCase();
                            });

                            onCustomerSelected(customer);
                          }
                        },
                        onClear: () {
                          setDialogState(() {
                            currentCustomer = null;
                            ownerController.clear();
                          });

                          onCustomerCleared();
                        },
                      ),

                      const SizedBox(height: 12),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: currentCustomer == null
                              ? Colors.orange.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              currentCustomer == null
                                  ? Icons.info_outline
                                  : Icons.verified_user,
                              color: currentCustomer == null
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                currentCustomer == null
                                    ? 'No customer selected. Vehicle will be saved as Pending Claim.'
                                    : 'Selected customer: ${currentCustomer!['name']}',
                                style: TextStyle(
                                  color: currentCustomer == null
                                      ? Colors.orange
                                      : Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF339BFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: onSave,
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
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

  Future<Map<String, dynamic>?> showCustomerSearchDialog() async {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> customerResults = [];
    bool isSearching = false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> doSearch(String value) async {
              setDialogState(() {
                isSearching = true;
              });

              try {
                final result = await searchCustomers(value.trim());

                setDialogState(() {
                  customerResults = result;
                });
              } catch (error) {
                showMessage('Failed to search customers: $error');
              } finally {
                setDialogState(() {
                  isSearching = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Search Customer'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Type customer name',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: doSearch,
                    ),
                    const SizedBox(height: 14),
                    if (isSearching)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      )
                    else if (customerResults.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Type customer name to search.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    else
                      SizedBox(
                        height: 260,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: customerResults.length,
                          itemBuilder: (context, index) {
                            final customer = customerResults[index];

                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFD7E5FA),
                                  child: Icon(
                                    Icons.person,
                                    color: Color(0xFF339BFF),
                                  ),
                                ),
                                title: Text(
                                  customer['name'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${customer['email'] ?? ''}\n${customer['phone'] ?? ''}',
                                ),
                                isThreeLine: true,
                                onTap: () {
                                  Navigator.pop(context, customer);
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

  Widget buildOwnerBox({
    required TextEditingController controller,
    required VoidCallback onSearch,
    required VoidCallback onClear,
  }) {
    return SizedBox(
      height: 75,
      child: TextField(
        controller: controller,
        readOnly: true,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: 'Owner Name (Optional)',
          prefixIcon: const Icon(Icons.person, size: 26),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: onSearch,
              ),
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: onClear,
              ),
            ],
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  void showVehicleDetailDialog(Map<String, dynamic> vehicle) {
    final status = vehicle['verification_status'] ?? 'Verified';
    final vehicleId = vehicle['vehicle_id'].toString();
    final plate = vehicle['plate_number'] ?? '';
    final model = vehicle['car_model'] ?? '';
    final owner = (vehicle['customer_name'] ?? '').toString().isEmpty
        ? 'No Customer Assigned'
        : vehicle['customer_name'];

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF339BFF), Color(0xFF63B3FF)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.directions_car, color: Colors.white, size: 44),
                        const SizedBox(height: 10),
                        Text(
                          plate,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          model,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  buildDetailRow('Plate Number', plate),
                  buildDetailRow('Car Model', model),
                  buildDetailRow('Customer Name', owner),
                  buildDetailRow('Status', status),

                  const SizedBox(height: 18),

                  if (status == 'Pending Claim') ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              showApproveClaimDialog(vehicle);
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              showRejectClaimDialog(vehicle);
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Reject'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (status == 'Verified') ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          showUnclaimDialog(vehicle);
                        },
                        icon: const Icon(Icons.link_off),
                        label: const Text('Set as Unclaim'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (status != 'Pending Claim') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF339BFF),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          showEditVehicleDialog(vehicle);
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Vehicle'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            showDeleteVehicleDialog(vehicleId);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
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

  void showApproveClaimDialog(Map<String, dynamic> vehicle) {
    final plate = vehicle['plate_number'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Approve Claim'),
          content: Text('Approve vehicle claim for $plate?'),
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
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await approveVehicleClaim(vehicle);
              },
              child: const Text('Yes, Approve'),
            ),
          ],
        );
      },
    );
  }

  void showRejectClaimDialog(Map<String, dynamic> vehicle) {
    final plate = vehicle['plate_number'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject Claim'),
          content: Text('Reject vehicle claim for $plate?'),
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
                await rejectVehicleClaim(vehicle);
              },
              child: const Text('Yes, Reject'),
            ),
          ],
        );
      },
    );
  }

  void showUnclaimDialog(Map<String, dynamic> vehicle) {
    final plate = vehicle['plate_number'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set as Unclaim'),
          content: Text(
            'Set $plate as unclaimed? The customer link will be removed.',
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
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await setVehicleUnclaim(vehicle);
              },
              child: const Text('Yes, Unclaim'),
            ),
          ],
        );
      },
    );
  }

  void showDeleteVehicleDialog(String vehicleId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Vehicle'),
          content: const Text('Are you sure you want to delete this vehicle?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
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
                await deleteVehicle(vehicleId);
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
  }) {
    return SizedBox(
      height: 75,
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          TextInputFormatter.withFunction((oldValue, newValue) {
            return newValue.copyWith(
              text: newValue.text.toUpperCase(),
              selection: newValue.selection,
            );
          }),
        ],
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 26),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildDetailRow(String title, String value) {
    return Container(
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
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget buildVehicleCard(Map<String, dynamic> vehicle) {
    final status = vehicle['verification_status'] ?? 'Verified';
    final owner = vehicle['customer_name'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          showVehicleDetailDialog(vehicle);
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: Color(0xFFD7E5FA),
                child: Icon(
                  Icons.directions_car,
                  color: Color(0xFF339BFF),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${vehicle['plate_number'] ?? ''} • ${vehicle['car_model'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 17,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            owner.toString().isEmpty
                                ? 'No Customer Assigned'
                                : owner.toString(),
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: getStatusColor(status).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    Icon(
                      getStatusIcon(status),
                      size: 15,
                      color: getStatusColor(status),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status,
                      style: TextStyle(
                        color: getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSummaryBox({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFD7E5FA),
            child: Icon(icon, color: const Color(0xFF339BFF)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final displayVehicles = filteredVehicles;
    final pendingClaims = vehicles
        .where((vehicle) => vehicle['verification_status'] == 'Pending Claim')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Vehicle Management'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const NotificationBell(isAdmin: true),
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
          : RefreshIndicator(
        onRefresh: () => fetchVehicles(),
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
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
                      'Manage Customer Vehicles',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Search, add, edit and verify vehicle records.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: buildSummaryBox(
                            title: 'Total Vehicles',
                            value: '${vehicles.length}',
                            icon: Icons.directions_car,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildSummaryBox(
                            title: 'Pending Claims',
                            value: '$pendingClaims',
                            icon: Icons.pending_actions,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by plate, model, or customer name',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
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
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (displayVehicles.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No vehicles found.',
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
                      return buildVehicleCard(displayVehicles[index]);
                    },
                    childCount: displayVehicles.length,
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
              heroTag: 'vehicleBackToTop',
              backgroundColor: const Color(0xFF339BFF),
              foregroundColor: Colors.white,
              onPressed: scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up),
            ),
          if (showBackToTop) const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addVehicle',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: showAddVehicleDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Vehicle'),
          ),
        ],
      ),
    );
  }
}