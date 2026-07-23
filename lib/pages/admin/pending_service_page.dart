import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import 'admin_quotations_page.dart';
import '../../services/customer_notification_service.dart';
import '../common/app_result_message.dart';

class PendingServicePage extends StatefulWidget {
  const PendingServicePage({super.key});

  @override
  State<PendingServicePage> createState() => _PendingServicePageState();
}

class _PendingServicePageState extends State<PendingServicePage> {
  String searchText = '';
  bool isLoading = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  List<Map<String, dynamic>> pendingServices = [];
  RealtimeChannel? pendingServicesRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;
  final List<String> statusList = [
    'Waiting Arrived',
    'Waiting Fix',
    'In Progress',
    'Completed',
  ];

  final Set<String> allowedStatusUpdates = {
    'Waiting Fix',
    'In Progress',
    'Completed',
  };

  @override
  void initState() {
    super.initState();

    fetchPendingServices();
    setupRealtimeSubscription();

    scrollController.addListener(() {
      if (!mounted) return;

      final shouldShow =
          scrollController.hasClients &&
              scrollController.offset > 350;

      if (shouldShow != showBackToTop) {
        setState(() {
          showBackToTop = shouldShow;
        });
      }
    });
  }

  @override
  void dispose() {
    realtimeRefreshTimer?.cancel();

    final channel =
        pendingServicesRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (!scrollController.hasClients) return;

    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  Future<void> openCreateQuotation(
      Map<String, dynamic> service,
      ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminQuotationsPage(
          initialPendingService: service,
        ),
      ),
    );

    if (!mounted) return;

    await fetchPendingServices();
  }

  Future<void> fetchPendingServices({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final response = await supabase
          .from('pending_services')
          .select('''
          *,
          vehicles(plate_number, car_model),
          customers(name, phone, email),
          quotations(
            quotation_id,
            status,
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
          .order(
        'created_at',
        ascending: false,
      );

      if (!mounted) return;

      setState(() {
        pendingServices =
        List<Map<String, dynamic>>.from(
          response,
        );
      });
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load pending services: $error',
        );
      } else {
        debugPrint(
          'Realtime pending service refresh failed: $error',
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
    if (pendingServicesRealtimeChannel != null) {
      return;
    }

    pendingServicesRealtimeChannel = supabase
        .channel(
      'admin-pending-services-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'pending_services',
      callback: (payload) {
        debugPrint(
          'Pending service changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotations',
      callback: (payload) {
        debugPrint(
          'Linked quotation changed: '
              '${payload.eventType}',
        );

        scheduleRealtimeRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'quotation_items',
      callback: (payload) {
        debugPrint(
          'Quotation item changed: '
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
      refreshPendingServicesFromRealtime,
    );
  }

  Future<void> refreshPendingServicesFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await fetchPendingServices(
        showLoading: false,
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  List<Map<String, dynamic>> get filteredCars {
    return pendingServices.where((service) {
      final vehicle = service['vehicles'] ?? {};
      final plate = (vehicle['plate_number'] ?? '').toString().toLowerCase();
      final model = (vehicle['car_model'] ?? '').toString().toLowerCase();
      final customer =
      (service['customers']?['name'] ?? '').toString().toLowerCase();
      final search = searchText.toLowerCase();

      return plate.contains(search) ||
          model.contains(search) ||
          customer.contains(search);
    }).toList();
  }

  int getCompletedCount() {
    return pendingServices.where((service) {
      return service['status'] == 'Completed';
    }).length;
  }

  int getInProgressCount() {
    return pendingServices.where((service) {
      final status = service['status'];

      return status == 'Waiting Fix' ||
          status == 'In Progress';
    }).length;
  }

  Color getStatusColor(String status) {
    if (status == 'Completed') return Colors.green;
    if (status == 'In Progress') return Colors.blue;
    if (status == 'Waiting Fix') return Colors.orange;
    if (status == 'Waiting Arrived') return Colors.grey;
    return Colors.grey;
  }

  Color getStatusBackgroundColor(String status) {
    if (status == 'Completed') return Colors.green.shade50;
    if (status == 'In Progress') return Colors.blue.shade50;
    if (status == 'Waiting Fix') return Colors.orange.shade50;
    if (status == 'Waiting Arrived') return Colors.grey.shade100;
    return Colors.grey.shade100;
  }

  DateTime? parseDatabaseDateTime(dynamic value) {
    final rawValue = value?.toString().trim();

    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawValue)?.toLocal();
  }

  String formatDateTime(DateTime dateTime) {
    final localDateTime = dateTime.toLocal();

    final day = localDateTime.day.toString().padLeft(2, '0');
    final month = localDateTime.month.toString().padLeft(2, '0');
    final year = localDateTime.year.toString();

    final hourValue = localDateTime.hour % 12 == 0
        ? 12
        : localDateTime.hour % 12;

    final hour = hourValue.toString().padLeft(2, '0');
    final minute = localDateTime.minute.toString().padLeft(2, '0');
    final period = localDateTime.hour >= 12 ? 'PM' : 'AM';

    return '$day/$month/$year $hour:$minute $period';
  }

  String formatStoredDateTime(dynamic value) {
    final parsedDateTime = parseDatabaseDateTime(value);

    if (parsedDateTime == null) {
      return 'Not Set';
    }

    return formatDateTime(parsedDateTime);
  }

  String getNotificationMessage(
      String status,
      String plate, {
        DateTime? estimatedCompletionAt,
      }) {
    if (status == 'Waiting Fix') {
      return 'Your vehicle $plate is waiting for inspection and repair.';
    }

    if (status == 'In Progress') {
      if (estimatedCompletionAt != null) {
        return 'Your vehicle $plate is currently being serviced. '
            'Estimated completion: ${formatDateTime(estimatedCompletionAt)}.';
      }

      return 'Your vehicle $plate is currently being serviced.';
    }

    if (status == 'Completed') {
      return 'Your vehicle $plate service has been completed.';
    }

    return 'Your vehicle $plate service status has been updated.';
  }

  Future<DateTime?> showEstimatedCompletionDialog(
      Map<String, dynamic> service,
      ) async {
    final vehicle = service['vehicles'] ?? {};
    final plate = vehicle['plate_number']?.toString() ?? 'Vehicle';

    final existingEstimate = parseDatabaseDateTime(
      service['estimated_completion_at'],
    );

    DateTime? selectedDate;

    if (existingEstimate != null) {
      selectedDate = DateTime(
        existingEstimate.year,
        existingEstimate.month,
        existingEstimate.day,
      );
    }

    TimeOfDay? selectedTime;

    if (existingEstimate != null) {
      selectedTime = TimeOfDay.fromDateTime(
        existingEstimate,
      );
    }

    String? validationMessage;

    return showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              dialogContext,
              setDialogState,
              ) {
            Future<void> chooseDate() async {
              final now = DateTime.now();
              final today = DateTime(
                now.year,
                now.month,
                now.day,
              );

              final lastDate = DateTime(
                now.year + 1,
                now.month,
                now.day,
              );

              DateTime initialDate = selectedDate ?? today;

              if (initialDate.isBefore(today)) {
                initialDate = today;
              }

              if (initialDate.isAfter(lastDate)) {
                initialDate = lastDate;
              }

              final pickedDate = await showDatePicker(
                context: dialogContext,
                initialDate: initialDate,
                firstDate: today,
                lastDate: lastDate,
              );

              if (pickedDate == null) {
                return;
              }

              setDialogState(() {
                selectedDate = pickedDate;
                validationMessage = null;
              });
            }

            Future<void> chooseTime() async {
              final initialTime = selectedTime ??
                  TimeOfDay.fromDateTime(
                    DateTime.now().add(
                      const Duration(hours: 2),
                    ),
                  );

              final pickedTime = await showTimePicker(
                context: dialogContext,
                initialTime: initialTime,
              );

              if (pickedTime == null) {
                return;
              }

              setDialogState(() {
                selectedTime = pickedTime;
                validationMessage = null;
              });
            }

            final selectedDateText = selectedDate == null
                ? 'Select completion date'
                : '${selectedDate!.day.toString().padLeft(2, '0')}/'
                '${selectedDate!.month.toString().padLeft(2, '0')}/'
                '${selectedDate!.year}';

            final selectedTimeText = selectedTime == null
                ? 'Select completion time'
                : selectedTime!.format(dialogContext);

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 30,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Text(
                'Start Service',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.circular(16),
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
                                '$plate will be changed to In Progress.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Estimated Completion Time',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Select the expected date and time that the vehicle service will be completed.',
                        style: TextStyle(
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: chooseDate,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 15,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selectedDate == null
                                  ? Colors.grey.shade300
                                  : const Color(0xFF339BFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month,
                                color: Color(0xFF339BFF),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedDateText,
                                  style: TextStyle(
                                    color: selectedDate == null
                                        ? Colors.black54
                                        : const Color(0xFF1F2937),
                                    fontWeight: FontWeight.w600,
                                  ),
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
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: chooseTime,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 15,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selectedTime == null
                                  ? Colors.grey.shade300
                                  : const Color(0xFF339BFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                color: Color(0xFF339BFF),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedTimeText,
                                  style: TextStyle(
                                    color: selectedTime == null
                                        ? Colors.black54
                                        : const Color(0xFF1F2937),
                                    fontWeight: FontWeight.w600,
                                  ),
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
                      if (validationMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  validationMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF339BFF),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (selectedDate == null ||
                        selectedTime == null) {
                      setDialogState(() {
                        validationMessage =
                        'Please select both the estimated completion date and time.';
                      });

                      return;
                    }

                    final estimatedCompletionAt = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedTime!.hour,
                      selectedTime!.minute,
                    );

                    if (!estimatedCompletionAt.isAfter(
                      DateTime.now(),
                    )) {
                      setDialogState(() {
                        validationMessage =
                        'Estimated completion time must be later than the current time.';
                      });

                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      estimatedCompletionAt,
                    );
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    'Confirm Start Service',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
  double calculateItemsTotal(List items) {
    double total = 0;

    for (final item in items) {
      final quantity = int.tryParse(item['quantity'].toString()) ?? 1;
      final price = double.tryParse(item['price'].toString()) ?? 0;

      total += quantity * price;
    }

    return total;
  }
  Future<bool> showStatusChangeConfirmation({
    required Map<String, dynamic> service,
    required String newStatus,
    DateTime? estimatedCompletionAt,
  }) async {
    final vehicle = service['vehicles'] ?? <String, dynamic>{};
    final plate = vehicle['plate_number']?.toString().trim() ?? '';
    final model = vehicle['car_model']?.toString().trim() ?? '';
    final currentStatus =
        service['status']?.toString().trim() ?? 'Not Provided';
    final displayPlate = plate.isEmpty ? 'Not Provided' : plate;
    final displayModel = model.isEmpty ? 'Not Provided' : model;
    final hasQuotation =
        service['quotation_id']?.toString().trim().isNotEmpty == true;

    final String extraMessage;

    if (newStatus == 'Completed' && hasQuotation) {
      extraMessage =
      'A Service Record will be generated automatically using the '
          'confirmed quotation items and prices.';
    } else if (newStatus == 'Completed') {
      extraMessage =
      'This service has no linked quotation. Complete it now and then '
          'create the Service Record manually.';
    } else if (newStatus == 'In Progress' &&
        estimatedCompletionAt != null) {
      extraMessage =
      'Estimated completion: '
          '${formatDateTime(estimatedCompletionAt)}.';
    } else {
      extraMessage =
      'Please confirm that this is the correct vehicle before updating.';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFFF3E0),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Confirm Status Change',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Please check the vehicle carefully.\n\n'
                'Plate Number: $displayPlate\n'
                'Car Model: $displayModel\n'
                'Current Status: $currentStatus\n'
                'New Status: $newStatus\n\n'
                '$extraMessage',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: newStatus == 'Completed'
                    ? Colors.green
                    : const Color(0xFF339BFF),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.check),
              label: Text(
                'Confirm $displayPlate',
              ),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> updatePendingStatus(
      Map<String, dynamic> service,
      String newStatus, {
        DateTime? estimatedCompletionAt,
      }) async {
    final pendingId =
    service['pending_id']
        ?.toString()
        .trim();

    if (pendingId == null ||
        pendingId.isEmpty) {
      showMessage(
        'Pending service information is missing.',
      );
      return;
    }

    if (!allowedStatusUpdates.contains(
      newStatus,
    )) {
      showMessage(
        'The selected service status is invalid.',
      );
      return;
    }

    if (newStatus == 'In Progress' &&
        estimatedCompletionAt == null) {
      showMessage(
        'Please select the estimated completion time before starting the service.',
      );
      return;
    }

    if (estimatedCompletionAt != null &&
        !estimatedCompletionAt.isAfter(
          DateTime.now(),
        )) {
      showMessage(
        'Estimated completion time must be later than the current time.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'update_pending_service_status',
        params: {
          'p_pending_id': pendingId,
          'p_new_status': newStatus,
          'p_estimated_completion_at':
          estimatedCompletionAt
              ?.toUtc()
              .toIso8601String(),
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid pending service information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final automaticRecordCreated =
          result['automatic_record_created'] ==
              true;

      final recordId =
      result['record_id']
          ?.toString();

      final returnedPendingId =
      result['pending_id']
          ?.toString();

      final customerId =
      result['customer_id']
          ?.toString();

      final vehicleId =
      result['vehicle_id']
          ?.toString();

      final bookingId =
      result['booking_id']
          ?.toString();

      final quotationId =
      result['quotation_id']
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

      final returnedEstimate =
          parseDatabaseDateTime(
            result['estimated_completion_at'],
          ) ??
              estimatedCompletionAt;

      /*
       * Notification runs after the transaction.
       * Notification failure will not undo the
       * completed service operation.
       */
      if (customerId != null &&
          customerId.isNotEmpty) {
        try {
          final String title;
          final String message;
          final String targetPage;

          if (automaticRecordCreated) {
            title =
            'Service Record Available';
            message =
            'The service for vehicle $plate has been completed. Your service record is now available.';
            targetPage = 'service_records';
          } else if (newStatus ==
              'Completed') {
            title =
            'Vehicle Service Completed';
            message =
            'Your vehicle $plate service has been completed.';
            targetPage = 'my_bookings';
          } else {
            title =
            'Vehicle Status Updated';
            message =
                getNotificationMessage(
                  newStatus,
                  plate,
                  estimatedCompletionAt:
                  returnedEstimate,
                );
            targetPage = 'my_bookings';
          }

          await supabase
              .from('notifications')
              .insert({
            'customer_id': customerId,
            'vehicle_id': vehicleId,
            'booking_id': bookingId,
            'quotation_id': quotationId,
            'title': title,
            'message': message,
            'notification_type':
            'service',
            'target_page': targetPage,
            'is_read': false,
          });

          await sendFcmPushNotification(
            customerId: customerId,
            title: title,
            message: message,
            data: {
              'notification_type':
              'service',
              'target_page': targetPage,
              if (recordId != null)
                'record_id': recordId,
              if (returnedPendingId !=
                  null)
                'pending_id':
                returnedPendingId,
              if (vehicleId != null)
                'vehicle_id': vehicleId,
              if (bookingId != null)
                'booking_id': bookingId,
              if (quotationId != null)
                'quotation_id':
                quotationId,
              if (returnedEstimate != null)
                'estimated_completion_at':
                returnedEstimate
                    .toUtc()
                    .toIso8601String(),
            },
          );
        } catch (
        notificationError,
        stackTrace
        ) {
          debugPrint(
            'Pending service notification failed: '
                '$notificationError',
          );

          debugPrint(
            stackTrace.toString(),
          );
        }
      }

      await fetchPendingServices();

      if (automaticRecordCreated) {
        showMessage(
          'Service completed and service record created automatically.',
        );
      } else if (newStatus ==
          'Completed') {
        showMessage(
          'Walk-in service completed. Create the service record manually from Service Records.',
        );
      } else if (newStatus ==
          'In Progress' &&
          returnedEstimate != null) {
        showMessage(
          'Service started. Estimated completion: '
              '${formatDateTime(returnedEstimate)}.',
        );
      } else {
        showMessage(
          'Service status updated to $newStatus.',
        );
      }
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await fetchPendingServices();
    } catch (error, stackTrace) {
      debugPrint(
        'Pending service status update failed: '
            '$error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to update status: $error',
      );
    }
  }

  Future<void> deletePendingService(
      Map<String, dynamic> service,
      ) async {
    final pendingId =
    service['pending_id']
        ?.toString()
        .trim();

    if (pendingId == null ||
        pendingId.isEmpty) {
      showMessage(
        'Pending service information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'delete_pending_service',
        params: {
          'p_pending_id': pendingId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid deletion result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['deleted'] != true) {
        throw Exception(
          'The pending service was not deleted.',
        );
      }

      await fetchPendingServices(
        showLoading: false,
      );

      showMessage(
        'Pending service deleted successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(
        error.message,
      );

      await fetchPendingServices(
        showLoading: false,
      );
    } catch (error) {
      showMessage(
        'Failed to delete pending service: $error',
      );
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
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
      ),
    );
  }

  Widget buildPendingDetailRow(
      String title,
      String value,
      ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Not Provided' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showPendingServiceDetailDialog(
      Map<String, dynamic> service,
      ) {
    final vehicle = service['vehicles'] ?? {};
    final customer = service['customers'] ?? {};
    final quotation = service['quotations'];

    final items =
        quotation?['quotation_items'] as List? ?? [];

    final total = quotation == null
        ? 0.0
        : double.tryParse(
      quotation['total']?.toString() ?? '',
    ) ??
        calculateItemsTotal(items);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 30,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Pending Service Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildPendingDetailRow(
                    'Plate Number',
                    vehicle['plate_number']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Car Model',
                    vehicle['car_model']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Customer',
                    customer['name']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Phone',
                    customer['phone']?.toString() ?? '',
                  ),
                  buildPendingDetailRow(
                    'Service Type',
                    service['service_type']?.toString() ??
                        'Walk-in',
                  ),
                  buildPendingDetailRow(
                    'Service Status',
                    service['status']?.toString() ??
                        'Waiting Fix',
                  ),
                  if (service['estimated_completion_at'] != null)
                    buildPendingDetailRow(
                      'Estimated Completion',
                      formatStoredDateTime(
                        service['estimated_completion_at'],
                      ),
                    ),
                  buildPendingDetailRow(
                    'Problem',
                    quotation?['problem_description']
                        ?.toString() ??
                        service['note']?.toString() ??
                        'No description',
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Quotation Information',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (quotation == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'No quotation is linked to this service.',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else ...[
                    buildPendingDetailRow(
                      'Quotation Status',
                      quotation['status']?.toString() ?? '',
                    ),
                    buildPendingDetailRow(
                      'Quotation Total',
                      'RM ${total.toStringAsFixed(2)}',
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Quotation Items',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (items.isEmpty)
                      const Text('No quotation items found.')
                    else
                      ...items.map((item) {
                        final quantity = int.tryParse(
                          item['quantity'].toString(),
                        ) ??
                            1;

                        final price = double.tryParse(
                          item['price'].toString(),
                        ) ??
                            0;

                        final subtotal = quantity * price;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item['item_name'] ?? 'Item'}\n'
                                      'Qty: $quantity × RM ${price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                'RM ${subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFF339BFF),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
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
  }

  Widget buildPendingServiceCard(Map<String, dynamic> service) {
    final vehicle = service['vehicles'] ?? {};
    final customer = service['customers'] ?? {};
    final quotation = service['quotations'];

    final status =
        service['status']?.toString() ??
            'Waiting Fix';

    final estimatedCompletionText =
    formatStoredDateTime(
      service['estimated_completion_at'],
    );

    final plate = vehicle['plate_number'] ?? '';
    final model = vehicle['car_model'] ?? '';
    final customerName = customer['name'] ?? 'Not Provided';
    final type = service['service_type'] ?? 'Walk-in';

    final quotationId = service['quotation_id'];
    final hasQuotation = quotationId != null;
    final isCompleted = status == 'Completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          showPendingServiceDetailDialog(service);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Color(0xFFD7E5FA),
                    child: Icon(
                      Icons.car_repair,
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
                          '$plate - $model',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Customer: $customerName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Type: $type',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasQuotation
                              ? 'Quotation: ${quotation?['status'] ?? 'Linked'}'
                              : 'Quotation: Not Created',
                          style: TextStyle(
                            color: hasQuotation
                                ? Colors.purple
                                : Colors.orange,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete Pending Service',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      if (hasQuotation) {
                        showMessage(
                          'Cancel or unlink the quotation before deleting this pending service.',
                        );
                        return;
                      }

                      if (status == 'In Progress') {
                        showMessage(
                          'An in-progress service cannot be deleted.',
                        );
                        return;
                      }

                      if (status == 'Completed') {
                        showMessage(
                          'Create the service record before removing this completed service.',
                        );
                        return;
                      }

                      showDeletePendingServiceDialog(
                        service,
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                value: statusList.contains(status)
                    ? status
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Service Status',
                  floatingLabelBehavior:
                  FloatingLabelBehavior.always,
                  prefixIcon:
                  const Icon(Icons.update),
                  filled: true,
                  fillColor:
                  Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(16),
                    borderSide:
                    BorderSide.none,
                  ),
                ),
                items: statusList.map(
                      (itemStatus) {
                    final isWaitingArrival =
                        itemStatus ==
                            'Waiting Arrived';

                    return DropdownMenuItem<
                        String>(
                      value: itemStatus,
                      enabled:
                      !isWaitingArrival,
                      child: Text(
                        itemStatus,
                        style: TextStyle(
                          color: isWaitingArrival
                              ? Colors.black38
                              : null,
                        ),
                      ),
                    );
                  },
                ).toList(),
                onChanged: isCompleted
                    ? null
                    : (value) async {
                  if (value == null || value == status) {
                    return;
                  }

                  DateTime? estimatedTime;

                  if (value == 'In Progress') {
                    estimatedTime =
                    await showEstimatedCompletionDialog(
                      service,
                    );

                    if (estimatedTime == null) {
                      return;
                    }
                  }

                  final confirmed =
                  await showStatusChangeConfirmation(
                    service: service,
                    newStatus: value,
                    estimatedCompletionAt: estimatedTime,
                  );

                  if (!confirmed) {
                    return;
                  }

                  await updatePendingStatus(
                    service,
                    value,
                    estimatedCompletionAt: estimatedTime,
                  );
                },
              ),

              if (estimatedCompletionText !=
                  'Not Set') ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color:
                    Colors.blue.shade50,
                    borderRadius:
                    BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.blue
                          .withOpacity(0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        color: Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Estimated Completion',
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight:
                            FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          estimatedCompletionText,
                          textAlign:
                          TextAlign.right,
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight:
                            FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: getStatusBackgroundColor(status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!hasQuotation && !isCompleted)
                    ElevatedButton.icon(
                      onPressed: () {
                        openCreateQuotation(service);
                      },
                      icon: const Icon(
                        Icons.receipt_long,
                        size: 17,
                      ),
                      label: const Text('Create Quotation'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(0xFF339BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  else if (hasQuotation)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            color: Colors.purple,
                            size: 17,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Quotation Linked',
                            style: TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
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

  void showDeletePendingServiceDialog(
      Map<String, dynamic> service,
      ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Delete Pending Service',
          ),
          content: const Text(
            'Are you sure you want to delete this pending service record?',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);

                await deletePendingService(
                  service,
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayCars = filteredCars;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Pending Services'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const NotificationBell(
            isAdmin: true,
          ),
          IconButton(
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
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () => fetchPendingServices(),
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
                      'Pending Service Queue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Track vehicle service progress and notify customers',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.car_repair,
                          title: 'In Progress',
                          value: '${getInProgressCount()}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.check_circle,
                          title: 'Completed',
                          value: '${getCompletedCount()}',
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
                        hintText: 'Search by plate, model or customer',
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
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (displayCars.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No pending service found.',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildPendingServiceCard(displayCars[index]);
                    },
                    childCount: displayCars.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        onPressed: scrollToTop,
        child: const Icon(Icons.keyboard_arrow_up),
      )
          : null,
    );
  }
}