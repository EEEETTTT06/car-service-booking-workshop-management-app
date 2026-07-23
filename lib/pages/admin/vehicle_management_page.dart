import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../../services/customer_notification_service.dart';
import '../common/app_result_message.dart';

class VehicleManagementPage extends StatefulWidget {
  final String? initialVehicleId;
  final String? initialPlateNumber;

  const VehicleManagementPage({
    super.key,
    this.initialVehicleId,
    this.initialPlateNumber,
  });

  @override
  State<VehicleManagementPage> createState() =>
      _VehicleManagementPageState();
}

class _VehicleManagementPageState
    extends State<VehicleManagementPage> {
  String searchText = '';
  String selectedVehicleColumn = 'Verified';
  bool isLoading = false;

  final List<String> vehicleColumns = const [
    'Verified',
    'Pending Claim',
    'Rejected',
  ];

  final TextEditingController
  searchController =
  TextEditingController();

  bool hasHandledInitialVehicle = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  List<Map<String, dynamic>> vehicles = [];
  RealtimeChannel? vehiclesRealtimeChannel;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    final initialPlate =
        widget.initialPlateNumber
            ?.trim() ??
            '';

    if (initialPlate.isNotEmpty) {
      searchController.text =
          initialPlate;

      searchText = initialPlate;
    }

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
          .select('''
            *,
            customers(
              customer_id,
              name,
              email,
              phone
            )
          ''')
          .order(
        'created_at',
        ascending: false,
      );

      if (!mounted) return;

      final rows =
      List<Map<String, dynamic>>.from(
        response,
      );

      /*
       * Always display the latest customer name
       * from the customers relation. This avoids
       * showing an old copied customer_name value
       * after the customer edits their profile.
       */
      for (final row in rows) {
        final linkedCustomer =
        row['customers'];

        if (linkedCustomer is Map) {
          final latestName =
          linkedCustomer['name']
              ?.toString()
              .trim();

          if (latestName != null &&
              latestName.isNotEmpty) {
            row['customer_name'] =
                latestName;
          }
        }
      }

      setState(() {
        vehicles = rows;
      });

      tryOpenInitialVehicle();
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

  void tryOpenInitialVehicle() {
    if (hasHandledInitialVehicle) {
      return;
    }

    final initialVehicleId =
        widget.initialVehicleId
            ?.trim() ??
            '';

    final initialPlateNumber =
        widget.initialPlateNumber
            ?.trim()
            .toUpperCase() ??
            '';

    if (initialVehicleId.isEmpty &&
        initialPlateNumber.isEmpty) {
      hasHandledInitialVehicle = true;
      return;
    }

    Map<String, dynamic>? targetVehicle;

    /*
   * First use vehicle_id because it is unique
   * and will not be affected if the plate is
   * changed later.
   */
    if (initialVehicleId.isNotEmpty) {
      for (final vehicle in vehicles) {
        final vehicleId =
        vehicle['vehicle_id']
            ?.toString()
            .trim();

        if (vehicleId ==
            initialVehicleId) {
          targetVehicle = vehicle;
          break;
        }
      }
    }

    /*
   * Use the plate number only as a backup.
   */
    if (targetVehicle == null &&
        initialPlateNumber.isNotEmpty) {
      for (final vehicle in vehicles) {
        final plateNumber =
        vehicle['plate_number']
            ?.toString()
            .trim()
            .toUpperCase();

        if (plateNumber ==
            initialPlateNumber) {
          targetVehicle = vehicle;
          break;
        }
      }
    }

    hasHandledInitialVehicle = true;

    if (targetVehicle == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        if (!mounted) return;

        showMessage(
          'The selected vehicle could not be found.',
        );
      });

      return;
    }

    final vehicleToOpen =
    Map<String, dynamic>.from(
      targetVehicle,
    );

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      showVehicleDetailDialog(
        vehicleToOpen,
      );
    });
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
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'customers',
      callback: (payload) {
        debugPrint(
          'Customer profile changed: '
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

  bool matchesVehicleColumn(
      Map<String, dynamic> vehicle,
      String column,
      ) {
    final status =
        vehicle['verification_status']
            ?.toString()
            .trim() ??
            'Verified';

    return status == column;
  }

  List<Map<String, dynamic>> get filteredVehicles {
    final search = searchText.trim().toLowerCase();

    return vehicles.where((vehicle) {
      if (!matchesVehicleColumn(
        vehicle,
        selectedVehicleColumn,
      )) {
        return false;
      }

      final plate =
      (vehicle['plate_number'] ?? '')
          .toString()
          .toLowerCase();

      final model =
      (vehicle['car_model'] ?? '')
          .toString()
          .toLowerCase();

      final owner =
      (vehicle['customer_name'] ?? '')
          .toString()
          .toLowerCase();

      if (search.isEmpty) {
        return true;
      }

      return plate.contains(search) ||
          model.contains(search) ||
          owner.contains(search);
    }).toList();
  }

  int getVehicleColumnCount(String column) {
    return vehicles.where((vehicle) {
      return matchesVehicleColumn(
        vehicle,
        column,
      );
    }).length;
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
    required String customerId,
    required String vehicleId,
    required String title,
    required String message,
  }) async {
    await supabase
        .from('notifications')
        .insert({
      'customer_id': customerId,
      'vehicle_id': vehicleId,
      'title': title,
      'message': message,
      'notification_type':
      'vehicle_claim',
      'target_page': 'my_vehicles',
      'is_read': false,
    });

    await sendFcmPushNotification(
      customerId: customerId,
      title: title,
      message: message,
      data: {
        'notification_type':
        'vehicle_claim',
        'target_page': 'my_vehicles',
        'vehicle_id': vehicleId,
      },
    );
  }

  Future<void> addVehicle({
    required String plate,
    required String model,
    Map<String, dynamic>? customer,
  }) async {
    final normalizedPlate =
    plate.trim().toUpperCase();

    final normalizedModel =
    model.trim().toUpperCase();

    if (normalizedPlate.isEmpty ||
        normalizedModel.isEmpty) {
      showMessage(
        'Please enter plate number and car model.',
      );
      return;
    }

    final customerId =
    customer?['customer_id']
        ?.toString()
        .trim();

    try {
      final rpcResult = await supabase.rpc(
        'admin_create_vehicle',
        params: {
          'p_plate_number':
          normalizedPlate,
          'p_car_model':
          normalizedModel,
          'p_customer_id':
          customerId == null ||
              customerId.isEmpty
              ? null
              : customerId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final vehicleId =
      result['vehicle_id']
          ?.toString();

      if (vehicleId == null ||
          vehicleId.isEmpty ||
          result['created'] != true) {
        throw Exception(
          'The vehicle was not created correctly.',
        );
      }

      await fetchVehicles();

      showMessage(
        'Vehicle added successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await fetchVehicles();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin add vehicle failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to add vehicle: $error',
      );
    }
  }

  Future<void> updateVehicle({
    required String vehicleId,
    required String plate,
    required String model,
    Map<String, dynamic>? customer,
  }) async {
    final normalizedVehicleId =
    vehicleId.trim();

    final normalizedPlate =
    plate.trim().toUpperCase();

    final normalizedModel =
    model.trim().toUpperCase();

    if (normalizedVehicleId.isEmpty) {
      showMessage(
        'Vehicle information is missing.',
      );
      return;
    }

    if (normalizedPlate.isEmpty ||
        normalizedModel.isEmpty) {
      showMessage(
        'Please enter plate number and car model.',
      );
      return;
    }

    final customerId =
    customer?['customer_id']
        ?.toString()
        .trim();

    try {
      final rpcResult = await supabase.rpc(
        'admin_update_vehicle',
        params: {
          'p_vehicle_id':
          normalizedVehicleId,
          'p_plate_number':
          normalizedPlate,
          'p_car_model':
          normalizedModel,
          'p_customer_id':
          customerId == null ||
              customerId.isEmpty
              ? null
              : customerId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedVehicleId =
      result['vehicle_id']
          ?.toString();

      if (returnedVehicleId == null ||
          returnedVehicleId.isEmpty ||
          result['updated'] != true) {
        throw Exception(
          'The vehicle was not updated correctly.',
        );
      }

      await fetchVehicles();

      showMessage(
        'Vehicle updated successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await fetchVehicles();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin update vehicle failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to update vehicle: $error',
      );
    }
  }

  Future<void> processVehicleClaim({
    required Map<String, dynamic> vehicle,
    required String action,
  }) async {
    final vehicleId =
    vehicle['vehicle_id']?.toString().trim();

    if (vehicleId == null || vehicleId.isEmpty) {
      showMessage(
        'Vehicle information is missing.',
      );
      return;
    }

    if (action != 'approve' &&
        action != 'reject' &&
        action != 'unclaim') {
      showMessage(
        'The vehicle claim action is invalid.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_process_vehicle_claim',
        params: {
          'p_vehicle_id': vehicleId,
          'p_action': action,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle claim information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedVehicleId =
      result['vehicle_id']?.toString();

      final originalCustomerId =
      result['original_customer_id']
          ?.toString();

      final plateValue =
      result['plate_number']
          ?.toString()
          .trim();

      final plate =
      plateValue == null ||
          plateValue.isEmpty
          ? 'your vehicle'
          : plateValue;

      final verificationStatus =
      result['verification_status']
          ?.toString();

      if (returnedVehicleId == null ||
          returnedVehicleId.isEmpty) {
        throw Exception(
          'Vehicle ID was not returned.',
        );
      }

      if ((action == 'approve' ||
          action == 'reject') &&
          originalCustomerId != null &&
          originalCustomerId.isNotEmpty) {
        try {
          final approved =
              action == 'approve';

          final title = approved
              ? 'Vehicle Claim Approved'
              : 'Vehicle Claim Rejected';

          final message = approved
              ? 'Your vehicle claim for $plate has been approved.'
              : 'Your vehicle claim for $plate has been rejected.';

          await createVehicleClaimNotification(
            customerId:
            originalCustomerId,
            vehicleId:
            returnedVehicleId,
            title: title,
            message: message,
          );
        } catch (
        notificationError,
        stackTrace
        ) {
          debugPrint(
            'Vehicle claim notification failed: '
                '$notificationError',
          );

          debugPrint(
            stackTrace.toString(),
          );
        }
      }

      await fetchVehicles();

      if (!mounted) return;

      if (action == 'approve') {
        if (verificationStatus !=
            'Verified') {
          throw Exception(
            'The vehicle claim was not approved correctly.',
          );
        }

        showMessage(
          'Vehicle claim approved.',
        );
      } else if (action == 'reject') {
        if (verificationStatus !=
            'Rejected') {
          throw Exception(
            'The vehicle claim was not rejected correctly.',
          );
        }

        showMessage(
          'Vehicle claim rejected.',
        );
      } else {
        if (verificationStatus !=
            'Pending Claim') {
          throw Exception(
            'The vehicle ownership link was not removed correctly.',
          );
        }

        showMessage(
          'Vehicle set as unclaimed.',
        );
      }
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await fetchVehicles();
    } catch (error, stackTrace) {
      debugPrint(
        'Vehicle claim action failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to update vehicle claim: $error',
      );
    }
  }

  Future<void> approveVehicleClaim(
      Map<String, dynamic> vehicle,
      ) {
    return processVehicleClaim(
      vehicle: vehicle,
      action: 'approve',
    );
  }

  Future<void> rejectVehicleClaim(
      Map<String, dynamic> vehicle,
      ) {
    return processVehicleClaim(
      vehicle: vehicle,
      action: 'reject',
    );
  }

  Future<void> setVehicleUnclaim(
      Map<String, dynamic> vehicle,
      ) {
    return processVehicleClaim(
      vehicle: vehicle,
      action: 'unclaim',
    );
  }


  List<String> getStoragePathsFromDeletionResult(
      Map<String, dynamic> result,
      ) {
    final rawPaths = result['storage_paths'];

    if (rawPaths is! List) {
      return <String>[];
    }

    final uniquePaths = <String>{};

    for (final rawPath in rawPaths) {
      final path = rawPath?.toString().trim() ?? '';

      if (path.isNotEmpty) {
        uniquePaths.add(path);
      }
    }

    return uniquePaths.toList();
  }

  Future<Map<String, int>> removeVehicleStorageFiles(
      List<String> storagePaths,
      ) async {
    if (storagePaths.isEmpty) {
      return {
        'deleted': 0,
        'failed': 0,
      };
    }

    int deletedCount = 0;
    int failedCount = 0;
    const chunkSize = 100;

    for (
    int start = 0;
    start < storagePaths.length;
    start += chunkSize
    ) {
      final end = (start + chunkSize) > storagePaths.length
          ? storagePaths.length
          : start + chunkSize;

      final chunk = storagePaths.sublist(
        start,
        end,
      );

      try {
        await supabase.storage
            .from('vehicle-photos')
            .remove(chunk);

        deletedCount += chunk.length;
      } catch (error, stackTrace) {
        failedCount += chunk.length;

        debugPrint(
          'Vehicle Storage cleanup failed: $error',
        );

        debugPrint(
          stackTrace.toString(),
        );
      }
    }

    return {
      'deleted': deletedCount,
      'failed': failedCount,
    };
  }

  Future<void> deleteVehicle(
      String vehicleId,
      ) async {
    final normalizedVehicleId =
    vehicleId.trim();

    if (normalizedVehicleId.isEmpty) {
      AppResultMessage.warning(
        context,
        message:
        'Vehicle information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_delete_vehicle',
        params: {
          'p_vehicle_id':
          normalizedVehicleId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle deletion result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['deleted'] != true) {
        throw Exception(
          'The vehicle was not deleted.',
        );
      }

      final storagePaths =
      getStoragePathsFromDeletionResult(
        result,
      );

      final cleanupResult =
      await removeVehicleStorageFiles(
        storagePaths,
      );

      try {
        await fetchVehicles();
      } catch (refreshError) {
        debugPrint(
          'Refresh admin vehicles after deletion failed: '
              '$refreshError',
        );
      }

      if (!mounted) return;

      final deletedPhotoCount =
          cleanupResult['deleted'] ?? 0;

      final failedPhotoCount =
          cleanupResult['failed'] ?? 0;

      if (failedPhotoCount > 0) {
        AppResultMessage.warning(
          context,
          message:
          'Vehicle deleted, but '
              '$failedPhotoCount photo(s) could not '
              'be removed from Storage. '
              '$deletedPhotoCount photo(s) were removed.',
          duration:
          const Duration(seconds: 5),
        );
      } else if (deletedPhotoCount > 0) {
        AppResultMessage.success(
          context,
          message:
          'Vehicle and $deletedPhotoCount '
              'photo(s) deleted successfully.',
        );
      } else {
        AppResultMessage.success(
          context,
          message:
          'Vehicle deleted successfully.',
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        AppResultMessage.error(
          context,
          message: error.message,
        );
      }

      try {
        await fetchVehicles();
      } catch (refreshError) {
        debugPrint(
          'Refresh admin vehicles after failed deletion: '
              '$refreshError',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Admin delete vehicle failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      AppResultMessage.error(
        context,
        message:
        'Failed to delete vehicle: $error',
      );
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

  Future<Map<String, dynamic>?>
  showCustomerSearchDialog() {
    return showModalBottomSheet<
        Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _CustomerSearchSheet(
          onSearch: searchCustomers,
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

  Future<List<Map<String, dynamic>>> fetchVehicleImages(
      String vehicleId,
      ) async {
    final response = await supabase
        .from('vehicle_images')
        .select(
      'image_id, vehicle_id, image_type, storage_path, created_at',
    )
        .eq('vehicle_id', vehicleId)
        .order('created_at', ascending: true);

    final rows =
    List<Map<String, dynamic>>.from(response);

    final result =
    <Map<String, dynamic>>[];

    for (final row in rows) {
      final image =
      Map<String, dynamic>.from(row);

      final storagePath = image['storage_path']
          ?.toString()
          .trim();

      if (storagePath == null ||
          storagePath.isEmpty) {
        image['signed_url'] = null;
        result.add(image);
        continue;
      }

      try {
        /*
       * The bucket is private, so Admin receives
       * a temporary URL valid for one hour.
       */
        final signedUrl = await supabase.storage
            .from('vehicle-photos')
            .createSignedUrl(
          storagePath,
          3600,
        );

        image['signed_url'] = signedUrl;
      } catch (error) {
        debugPrint(
          'Failed to create vehicle photo URL: '
              '$error',
        );

        image['signed_url'] = null;
        image['load_error'] = error.toString();
      }

      result.add(image);
    }

    return result;
  }

  void showVehicleImagePreview({
    required String imageUrl,
    required String title,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 28,
          ),
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            width: double.infinity,
            height:
            MediaQuery.of(dialogContext)
                .size
                .height *
                0.75,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    10,
                    8,
                    10,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1F2937),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (
                            context,
                            child,
                            loadingProgress,
                            ) {
                          if (loadingProgress ==
                              null) {
                            return child;
                          }

                          return const Center(
                            child:
                            CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (
                            context,
                            error,
                            stackTrace,
                            ) {
                          return const Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                color: Colors.white54,
                                size: 56,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Unable to display this photo.',
                                style: TextStyle(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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

  Widget buildVehiclePhotoSection({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> images,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF339BFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                  const Color(0xFFD7E5FA),
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: Text(
                  '${images.length}',
                  style: const TextStyle(
                    color: Color(0xFF339BFF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (images.isEmpty)
            const Row(
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.black38,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No photos uploaded.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (
                    context,
                    index,
                    ) {
                  return const SizedBox(width: 10);
                },
                itemBuilder: (context, index) {
                  final image = images[index];

                  final signedUrl =
                  image['signed_url']
                      ?.toString()
                      .trim();

                  final canOpen =
                      signedUrl != null &&
                          signedUrl.isNotEmpty;

                  return InkWell(
                    borderRadius:
                    BorderRadius.circular(12),
                    onTap: canOpen
                        ? () {
                      showVehicleImagePreview(
                        imageUrl: signedUrl,
                        title:
                        '$title ${index + 1}',
                      );
                    }
                        : null,
                    child: Container(
                      width: 105,
                      height: 95,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius:
                        BorderRadius.circular(12),
                        border: Border.all(
                          color:
                          Colors.grey.shade300,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius:
                        BorderRadius.circular(11),
                        child: canOpen
                            ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              signedUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (
                                  context,
                                  child,
                                  loadingProgress,
                                  ) {
                                if (loadingProgress ==
                                    null) {
                                  return child;
                                }

                                return const Center(
                                  child:
                                  CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              },
                              errorBuilder: (
                                  context,
                                  error,
                                  stackTrace,
                                  ) {
                                return const Icon(
                                  Icons
                                      .broken_image_outlined,
                                  color:
                                  Colors.black38,
                                  size: 34,
                                );
                              },
                            ),
                            Positioned(
                              right: 5,
                              bottom: 5,
                              child: Container(
                                padding:
                                const EdgeInsets
                                    .all(4),
                                decoration:
                                BoxDecoration(
                                  color: Colors.black
                                      .withOpacity(
                                    0.55,
                                  ),
                                  shape:
                                  BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.zoom_in,
                                  color:
                                  Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        )
                            : const Center(
                          child: Icon(
                            Icons
                                .broken_image_outlined,
                            color:
                            Colors.black38,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void showVehicleDetailDialog(
      Map<String, dynamic> vehicle,
      ) {
    final status =
        vehicle['verification_status'] ??
            'Verified';

    final vehicleId =
    vehicle['vehicle_id'].toString();

    final plate =
        vehicle['plate_number'] ?? '';

    final model =
        vehicle['car_model'] ?? '';

    final owner =
    (vehicle['customer_name'] ?? '')
        .toString()
        .isEmpty
        ? 'No Customer Assigned'
        : vehicle['customer_name']
        .toString();

    /*
   * Every time Admin opens the Vehicle Details,
   * the latest Customer photos will be loaded.
   */
    final imagesFuture =
    fetchVehicleImages(vehicleId);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding:
          const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 30,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(28),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding:
                    const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient:
                      const LinearGradient(
                        colors: [
                          Color(0xFF339BFF),
                          Color(0xFF63B3FF),
                        ],
                      ),
                      borderRadius:
                      BorderRadius.circular(24),
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
                          plate.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          model.toString(),
                          style: const TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  buildDetailRow(
                    'Plate Number',
                    plate.toString(),
                  ),

                  buildDetailRow(
                    'Car Model',
                    model.toString(),
                  ),

                  buildDetailRow(
                    'Customer Name',
                    owner,
                  ),

                  buildDetailRow(
                    'Status',
                    status.toString(),
                  ),

                  const SizedBox(height: 8),

                  const Divider(),

                  const SizedBox(height: 8),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Customer Uploaded Photos',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),

                  const SizedBox(height: 5),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Review the VOC and vehicle photos before processing the claim.',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  FutureBuilder<
                      List<Map<String, dynamic>>>(
                    future: imagesFuture,
                    builder: (
                        context,
                        snapshot,
                        ) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding:
                          EdgeInsets.symmetric(
                            vertical: 25,
                          ),
                          child:
                          CircularProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        return Container(
                          width: double.infinity,
                          padding:
                          const EdgeInsets.all(
                            14,
                          ),
                          decoration: BoxDecoration(
                            color:
                            Colors.red.shade50,
                            borderRadius:
                            BorderRadius.circular(
                              14,
                            ),
                            border: Border.all(
                              color: Colors.red
                                  .withOpacity(0.35),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Unable to load vehicle photos: '
                                      '${snapshot.error}',
                                  style:
                                  const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final allImages =
                          snapshot.data ?? [];

                      final vocImages = allImages
                          .where(
                            (image) =>
                        image['image_type']
                            ?.toString() ==
                            'voc',
                      )
                          .toList();

                      final vehiclePhotos =
                      allImages
                          .where(
                            (image) =>
                        image['image_type']
                            ?.toString() ==
                            'vehicle',
                      )
                          .toList();

                      return Column(
                        children: [
                          buildVehiclePhotoSection(
                            title: 'VOC Photos',
                            icon:
                            Icons.description,
                            images: vocImages,
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          buildVehiclePhotoSection(
                            title:
                            'Vehicle Photos',
                            icon:
                            Icons.directions_car,
                            images:
                            vehiclePhotos,
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 18),

                  if (status ==
                      'Pending Claim') ...[
                    Row(
                      children: [
                        Expanded(
                          child:
                          ElevatedButton.icon(
                            style:
                            ElevatedButton
                                .styleFrom(
                              backgroundColor:
                              Colors.green,
                              foregroundColor:
                              Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(
                                dialogContext,
                              );

                              showApproveClaimDialog(
                                vehicle,
                              );
                            },
                            icon: const Icon(
                              Icons.check,
                            ),
                            label: const Text(
                              'Approve',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child:
                          ElevatedButton.icon(
                            style:
                            ElevatedButton
                                .styleFrom(
                              backgroundColor:
                              Colors.red,
                              foregroundColor:
                              Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(
                                dialogContext,
                              );

                              showRejectClaimDialog(
                                vehicle,
                              );
                            },
                            icon: const Icon(
                              Icons.close,
                            ),
                            label: const Text(
                              'Reject',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (status ==
                      'Verified') ...[
                    SizedBox(
                      width: double.infinity,
                      child:
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );

                          showUnclaimDialog(
                            vehicle,
                          );
                        },
                        icon: const Icon(
                          Icons.link_off,
                        ),
                        label: const Text(
                          'Set as Unclaim',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (status !=
                      'Pending Claim') ...[
                    SizedBox(
                      width: double.infinity,
                      child:
                      ElevatedButton.icon(
                        style:
                        ElevatedButton.styleFrom(
                          backgroundColor:
                          const Color(
                            0xFF339BFF,
                          ),
                          foregroundColor:
                          Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );

                          showEditVehicleDialog(
                            vehicle,
                          );
                        },
                        icon: const Icon(
                          Icons.edit,
                        ),
                        label: const Text(
                          'Edit Vehicle',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                            );
                          },
                          child:
                          const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child:
                        OutlinedButton.icon(
                          style: OutlinedButton
                              .styleFrom(
                            foregroundColor:
                            Colors.red,
                            side:
                            const BorderSide(
                              color: Colors.red,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                            );

                            showDeleteVehicleDialog(
                              vehicleId,
                            );
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                          ),
                          label:
                          const Text('Delete'),
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
          content: Text(
            'Please check the plate number carefully before continuing.\n\n'
                'Vehicle: $plate\n\n'
                'Approve this vehicle claim?',
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
          content: Text(
            'Please check the plate number carefully before continuing.\n\n'
                'Vehicle: $plate\n\n'
                'Reject this vehicle claim?',
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
            'Please check the plate number carefully before continuing.\n\n'
                'Vehicle: $plate\n\n'
                'Set this vehicle as unclaimed? The customer link will be removed.',
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

  Color getVehicleStatusBackgroundColor(String status) {
    if (status == 'Verified') return Colors.green.shade50;
    if (status == 'Pending Claim') return Colors.orange.shade50;
    if (status == 'Rejected') return Colors.red.shade50;
    return Colors.grey.shade100;
  }

  String getVehicleStatusDescription(String status) {
    if (status == 'Verified') return 'Ownership verified';
    if (status == 'Pending Claim') {
      return 'Customer claim requires Admin review';
    }
    if (status == 'Rejected') return 'Vehicle claim was rejected';
    return 'Ownership not verified';
  }

  Widget buildVehicleInformationLine({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final displayValue = value.trim().isEmpty
        ? 'Not Provided'
        : value.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
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
          flex: 2,
          child: Text(
            displayValue,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

  Widget buildVehicleCard(Map<String, dynamic> vehicle) {
    final status = vehicle['verification_status']
        ?.toString()
        .trim() ??
        'Verified';

    final plate = vehicle['plate_number']
        ?.toString()
        .trim() ??
        '';

    final model = vehicle['car_model']
        ?.toString()
        .trim() ??
        '';

    final owner = vehicle['customer_name']
        ?.toString()
        .trim() ??
        '';

    final customer = vehicle['customers'];

    final email = customer is Map
        ? customer['email']?.toString().trim() ?? ''
        : '';

    final phone = customer is Map
        ? customer['phone']?.toString().trim() ?? ''
        : '';

    final statusColor = getStatusColor(status);
    final isPendingClaim = status == 'Pending Claim';
    final isVerified = status == 'Verified';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: statusColor.withOpacity(
            isPendingClaim ? 0.35 : 0.14,
          ),
          width: isPendingClaim ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.08),
            blurRadius: 13,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
            ),
            onTap: () {
              showVehicleDetailDialog(vehicle);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD7E5FA),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Icon(
                          Icons.directions_car,
                          color: Color(0xFF339BFF),
                          size: 29,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plate.isEmpty
                                  ? 'NO PLATE NUMBER'
                                  : plate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              model.isEmpty
                                  ? 'Car model not provided'
                                  : model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: getVehicleStatusBackgroundColor(
                            status,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              getStatusIcon(status),
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (isPendingClaim) ...[
                    const SizedBox(height: 13),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.25),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.fact_check_outlined,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Customer claim requires Admin review.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        buildVehicleInformationLine(
                          icon: Icons.person_outline,
                          title: 'Owner',
                          value: owner.isEmpty
                              ? 'No Customer Assigned'
                              : owner,
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 11),
                          const Divider(height: 1),
                          const SizedBox(height: 11),
                          buildVehicleInformationLine(
                            icon: Icons.phone_outlined,
                            title: 'Phone',
                            value: phone,
                          ),
                        ],
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 11),
                          const Divider(height: 1),
                          const SizedBox(height: 11),
                          buildVehicleInformationLine(
                            icon: Icons.email_outlined,
                            title: 'Email',
                            value: email,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Icon(
                        isVerified
                            ? Icons.verified_user
                            : isPendingClaim
                            ? Icons.pending_actions
                            : Icons.info_outline,
                        color: statusColor,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          getVehicleStatusDescription(status),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.black38,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              11,
              12,
              12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF339BFF),
                      side: const BorderSide(
                        color: Color(0xFF339BFF),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      showVehicleDetailDialog(vehicle);
                    },
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: const Text('View Details'),
                  ),
                ),
                const SizedBox(width: 9),
                if (isPendingClaim)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        showVehicleDetailDialog(vehicle);
                      },
                      icon: const Icon(
                        Icons.fact_check_outlined,
                        size: 18,
                      ),
                      label: const Text('Review Claim'),
                    ),
                  )
                else
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF339BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        showEditVehicleDialog(vehicle);
                      },
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                      ),
                      label: const Text('Edit Vehicle'),
                    ),
                  ),
                const SizedBox(width: 7),
                IconButton(
                  tooltip: 'Delete Vehicle',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                  ),
                  onPressed: () {
                    final vehicleId = vehicle['vehicle_id']
                        ?.toString()
                        .trim() ??
                        '';

                    showDeleteVehicleDialog(vehicleId);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildVehicleColumnButton(
      String column,
      ) {
    final isSelected =
        selectedVehicleColumn == column;

    final color = getStatusColor(column);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (selectedVehicleColumn == column) {
            return;
          }

          setState(() {
            selectedVehicleColumn = column;
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
          duration: const Duration(
            milliseconds: 220,
          ),
          height: 76,
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? color
                  : color.withOpacity(0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(
                  isSelected ? 0.18 : 0.06,
                ),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  Icon(
                    getStatusIcon(column),
                    color: isSelected
                        ? Colors.white
                        : color,
                    size: 17,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${getVehicleColumnCount(column)}',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                column,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF1F2937),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
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

    AppResultMessage.show(
      context,
      message: message,
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
                      controller: searchController,
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
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Row(
                  children: vehicleColumns
                      .asMap()
                      .entries
                      .expand((entry) {
                    final widgets = <Widget>[
                      buildVehicleColumnButton(
                        entry.value,
                      ),
                    ];

                    if (entry.key <
                        vehicleColumns.length - 1) {
                      widgets.add(
                        const SizedBox(width: 8),
                      );
                    }

                    return widgets;
                  }).toList(),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$selectedVehicleColumn Vehicles',
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${displayVehicles.length} vehicle(s)',
                        style: const TextStyle(
                          color: Color(0xFF339BFF),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (displayVehicles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No $selectedVehicleColumn vehicle found.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _CustomerSearchSheet extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function(
      String keyword,
      ) onSearch;

  const _CustomerSearchSheet({
    required this.onSearch,
  });

  @override
  State<_CustomerSearchSheet> createState() =>
      _CustomerSearchSheetState();
}

class _CustomerSearchSheetState
    extends State<_CustomerSearchSheet> {
  final TextEditingController searchController =
  TextEditingController();

  Timer? searchDebounce;

  List<Map<String, dynamic>> customerResults = [];

  bool isSearching = false;
  bool hasSearched = false;
  int searchRequestId = 0;

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void scheduleSearch(String value) {
    searchDebounce?.cancel();

    searchDebounce = Timer(
      const Duration(milliseconds: 300),
          () {
        runSearch(value);
      },
    );
  }

  Future<void> runSearch(String value) async {
    final keyword = value.trim();
    final currentRequestId = ++searchRequestId;

    if (keyword.isEmpty) {
      if (!mounted) return;

      setState(() {
        customerResults = [];
        isSearching = false;
        hasSearched = false;
      });

      return;
    }

    if (!mounted) return;

    setState(() {
      isSearching = true;
      hasSearched = true;
    });

    try {
      final result = await widget.onSearch(
        keyword,
      );

      if (!mounted ||
          currentRequestId != searchRequestId) {
        return;
      }

      setState(() {
        customerResults = result;
        isSearching = false;
      });
    } catch (error) {
      if (!mounted ||
          currentRequestId != searchRequestId) {
        return;
      }

      setState(() {
        isSearching = false;
      });

      AppResultMessage.show(
        context,
        message:
        'Failed to search customers: $error',
      );
    }
  }

  void clearSearch() {
    searchDebounce?.cancel();
    ++searchRequestId;

    searchController.clear();

    setState(() {
      customerResults = [];
      isSearching = false;
      hasSearched = false;
    });
  }

  void selectCustomer(
      Map<String, dynamic> customer,
      ) {
    FocusManager.instance.primaryFocus?.unfocus();

    /*
     * Wait for the keyboard focus update before
     * closing the route. The sheet State owns and
     * disposes its controller only after the route
     * is fully removed, avoiding framework
     * dependency assertions during owner changes.
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pop(
        customer,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight =
        mediaQuery.viewInsets.bottom;

    final availableHeight =
        mediaQuery.size.height -
            keyboardHeight -
            20;

    final sheetHeight =
    availableHeight > 580
        ? 580.0
        : availableHeight > 0
        ? availableHeight
        : 1.0;

    return AnimatedPadding(
      duration: const Duration(
        milliseconds: 180,
      ),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: keyboardHeight,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.white,
          elevation: 12,
          borderRadius:
          const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: double.infinity,
            height: sheetHeight,
            child: Column(
              children: [
                Padding(
                  padding:
                  const EdgeInsets.fromLTRB(
                    20,
                    12,
                    12,
                    0,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius:
                          BorderRadius.circular(
                            20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Search Customer',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () {
                              FocusManager.instance
                                  .primaryFocus
                                  ?.unfocus();

                              Navigator.of(context)
                                  .pop();
                            },
                            icon: const Icon(
                              Icons.close,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                  const EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    12,
                  ),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    textInputAction:
                    TextInputAction.search,
                    decoration: InputDecoration(
                      hintText:
                      'Type customer name',
                      prefixIcon: const Icon(
                        Icons.search,
                      ),
                      suffixIcon:
                      searchController.text.isEmpty
                          ? null
                          : IconButton(
                        tooltip: 'Clear',
                        onPressed:
                        clearSearch,
                        icon: const Icon(
                          Icons.clear,
                        ),
                      ),
                      filled: true,
                      fillColor:
                      Colors.grey.shade100,
                      border:
                      OutlineInputBorder(
                        borderRadius:
                        BorderRadius.circular(
                          16,
                        ),
                        borderSide:
                        BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      scheduleSearch(value);
                    },
                    onSubmitted: runSearch,
                  ),
                ),
                Expanded(
                  child: isSearching
                      ? const Center(
                    child:
                    CircularProgressIndicator(),
                  )
                      : !hasSearched
                      ? const Center(
                    child: Padding(
                      padding:
                      EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      child: Text(
                        'Type a customer name to search.',
                        textAlign:
                        TextAlign.center,
                        style: TextStyle(
                          color:
                          Colors.black54,
                        ),
                      ),
                    ),
                  )
                      : customerResults.isEmpty
                      ? const Center(
                    child: Padding(
                      padding:
                      EdgeInsets
                          .symmetric(
                        horizontal: 24,
                      ),
                      child: Text(
                        'No matching customer found.',
                        textAlign:
                        TextAlign
                            .center,
                        style:
                        TextStyle(
                          color: Colors
                              .black54,
                        ),
                      ),
                    ),
                  )
                      : ListView.builder(
                    padding:
                    const EdgeInsets
                        .fromLTRB(
                      16,
                      0,
                      16,
                      18,
                    ),
                    keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior
                        .onDrag,
                    itemCount:
                    customerResults
                        .length,
                    itemBuilder: (
                        context,
                        index,
                        ) {
                      final customer =
                      customerResults[
                      index];

                      final name =
                          customer['name']
                              ?.toString() ??
                              '';

                      final email =
                          customer['email']
                              ?.toString() ??
                              '';

                      final phone =
                          customer['phone']
                              ?.toString() ??
                              '';

                      return Card(
                        margin:
                        const EdgeInsets
                            .only(
                          bottom: 10,
                        ),
                        child: ListTile(
                          contentPadding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          leading:
                          const CircleAvatar(
                            backgroundColor:
                            Color(
                              0xFFD7E5FA,
                            ),
                            child: Icon(
                              Icons.person,
                              color: Color(
                                0xFF339BFF,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style:
                            const TextStyle(
                              fontWeight:
                              FontWeight
                                  .bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              const SizedBox(
                                height: 3,
                              ),
                              if (email
                                  .isNotEmpty)
                                Text(
                                  email,
                                  maxLines:
                                  1,
                                  overflow:
                                  TextOverflow
                                      .ellipsis,
                                ),
                              if (phone
                                  .isNotEmpty)
                                Text(
                                  phone,
                                  maxLines:
                                  1,
                                  overflow:
                                  TextOverflow
                                      .ellipsis,
                                ),
                            ],
                          ),
                          trailing:
                          const Icon(
                            Icons
                                .chevron_right,
                          ),
                          onTap: () {
                            selectCustomer(
                              customer,
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
        ),
      ),
    );
  }
}

