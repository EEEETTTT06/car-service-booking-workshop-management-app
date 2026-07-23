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
  String selectedStatusColumn = 'Waiting Fix';
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

  bool matchesStatusColumn(
      Map<String, dynamic> service,
      String column,
      ) {
    final status =
        service['status']?.toString().trim() ?? '';

    if (column == 'Waiting Fix') {
      return status == 'Waiting Fix' ||
          status == 'Waiting Arrived';
    }

    return status == column;
  }

  List<Map<String, dynamic>> get filteredCars {
    final search = searchText.trim().toLowerCase();

    return pendingServices.where((service) {
      if (!matchesStatusColumn(
        service,
        selectedStatusColumn,
      )) {
        return false;
      }

      final vehicle =
          service['vehicles'] ?? <String, dynamic>{};

      final customer =
          service['customers'] ?? <String, dynamic>{};

      final plate =
      (vehicle['plate_number'] ?? '')
          .toString()
          .toLowerCase();

      final model =
      (vehicle['car_model'] ?? '')
          .toString()
          .toLowerCase();

      final customerName =
      (customer['name'] ?? '')
          .toString()
          .toLowerCase();

      if (search.isEmpty) {
        return true;
      }

      return plate.contains(search) ||
          model.contains(search) ||
          customerName.contains(search);
    }).toList();
  }

  int getStatusColumnCount(String column) {
    return pendingServices.where((service) {
      return matchesStatusColumn(
        service,
        column,
      );
    }).length;
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

  IconData getStatusColumnIcon(String column) {
    if (column == 'Waiting Fix') {
      return Icons.pending_actions;
    }

    if (column == 'In Progress') {
      return Icons.build_circle_outlined;
    }

    return Icons.check_circle_outline;
  }

  Widget buildStatusColumnButton(String column) {
    final isSelected =
        selectedStatusColumn == column;

    final color = getStatusColor(column);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (selectedStatusColumn == column) {
            return;
          }

          setState(() {
            selectedStatusColumn = column;
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
                    getStatusColumnIcon(column),
                    color: isSelected
                        ? Colors.white
                        : color,
                    size: 17,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${getStatusColumnCount(column)}',
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

  Widget buildDialogSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: const Color(0xFF339BFF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget buildDialogInformationRow({
    required IconData icon,
    required String title,
    required String value,
    bool showDivider = true,
  }) {
    final displayValue =
    value.trim().isEmpty ? 'Not Provided' : value.trim();

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: Colors.black45,
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 6,
              child: Text(
                displayValue,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: 11),
          Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 11),
        ],
      ],
    );
  }

  Widget buildQuotationItemCard(
      Map<dynamic, dynamic> item,
      ) {
    final quantity =
        int.tryParse(
          item['quantity']?.toString() ?? '',
        ) ??
            1;

    final price =
        double.tryParse(
          item['price']?.toString() ?? '',
        ) ??
            0;

    final subtotal = quantity * price;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.build_outlined,
              color: Color(0xFF339BFF),
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['item_name']?.toString() ??
                      'Service Item',
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Qty $quantity  ×  RM ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'RM ${subtotal.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Color(0xFF339BFF),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void showPendingServiceDetailDialog(
      Map<String, dynamic> service,
      ) {
    final vehicle =
        service['vehicles'] ?? <String, dynamic>{};

    final customer =
        service['customers'] ?? <String, dynamic>{};

    final quotation = service['quotations'];

    final items =
        quotation?['quotation_items'] as List? ??
            [];

    final itemTotal = calculateItemsTotal(items);

    final storedTotal =
    double.tryParse(
      quotation?['total']?.toString() ?? '',
    );

    final total =
    storedTotal == null ||
        (storedTotal <= 0 && itemTotal > 0)
        ? itemTotal
        : storedTotal;

    final plate =
        vehicle['plate_number']
            ?.toString()
            .trim() ??
            '';

    final model =
        vehicle['car_model']
            ?.toString()
            .trim() ??
            '';

    final status =
        service['status']
            ?.toString()
            .trim() ??
            'Waiting Fix';

    final serviceType =
        service['service_type']
            ?.toString()
            .trim() ??
            'Walk-in';

    final problem =
    quotation?['problem_description']
        ?.toString()
        .trim()
        .isNotEmpty ==
        true
        ? quotation!['problem_description'].toString()
        : service['note']?.toString() ??
        'No description';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 470,
              maxHeight:
              MediaQuery.of(dialogContext).size.height *
                  0.88,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    18,
                    16,
                    10,
                    16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF248CF2),
                        Color(0xFF63B3FF),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.car_repair,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              plate.isEmpty
                                  ? 'Pending Service Details'
                                  : plate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              model.isEmpty
                                  ? 'Pending Service Details'
                                  : model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () {
                          Navigator.pop(dialogContext);
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        buildDialogSection(
                          icon: Icons.person_outline,
                          title: 'Customer Information',
                          children: [
                            buildDialogInformationRow(
                              icon: Icons.person,
                              title: 'Customer Name',
                              value:
                              customer['name']?.toString() ??
                                  '',
                            ),
                            buildDialogInformationRow(
                              icon: Icons.phone_outlined,
                              title: 'Phone Number',
                              value:
                              customer['phone']?.toString() ??
                                  '',
                            ),
                            buildDialogInformationRow(
                              icon: Icons.email_outlined,
                              title: 'Email Address',
                              value:
                              customer['email']?.toString() ??
                                  '',
                              showDivider: false,
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        buildDialogSection(
                          icon: Icons.settings_suggest_outlined,
                          title: 'Service Information',
                          children: [
                            buildDialogInformationRow(
                              icon: Icons.category_outlined,
                              title: 'Service Type',
                              value: serviceType,
                            ),
                            buildDialogInformationRow(
                              icon: Icons.timeline,
                              title: 'Current Status',
                              value: status,
                            ),
                            buildDialogInformationRow(
                              icon: Icons.access_time,
                              title: 'Queue Created',
                              value: formatStoredDateTime(
                                service['created_at'],
                              ),
                            ),
                            buildDialogInformationRow(
                              icon: Icons.schedule,
                              title: 'Estimated Completion',
                              value: formatStoredDateTime(
                                service[
                                'estimated_completion_at'],
                              ),
                            ),
                            buildDialogInformationRow(
                              icon: Icons.notes_outlined,
                              title: 'Problem / Notes',
                              value: problem,
                              showDivider: false,
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        buildDialogSection(
                          icon: Icons.receipt_long_outlined,
                          title: 'Quotation Information',
                          children: [
                            if (quotation == null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius:
                                  BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.orange
                                        .withOpacity(0.25),
                                  ),
                                ),
                                child: const Row(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        'No quotation is currently linked to this service.',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              buildDialogInformationRow(
                                icon: Icons.verified_outlined,
                                title: 'Quotation Status',
                                value:
                                quotation['status']
                                    ?.toString() ??
                                    '',
                              ),
                              if (items.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding:
                                  const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color:
                                    Colors.grey.shade100,
                                    borderRadius:
                                    BorderRadius.circular(14),
                                  ),
                                  child: const Text(
                                    'No quotation items found.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                )
                              else
                                ...items.map(
                                      (item) =>
                                      buildQuotationItemCard(
                                        item as Map<dynamic, dynamic>,
                                      ),
                                ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF4FF),
                                  borderRadius:
                                  BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Quotation Total',
                                        style: TextStyle(
                                          color: Color(0xFF1F2937),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'RM ${total.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Color(0xFF339BFF),
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(0xFF339BFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text(
                        'Done',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
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

  Widget buildServiceBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildServiceInformationRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
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
          child: Text(
            value.trim().isEmpty ? 'Not Provided' : value,
            textAlign: TextAlign.right,
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

  void handleDeletePendingService(
      Map<String, dynamic> service,
      ) {
    final status =
        service['status']?.toString() ??
            'Waiting Fix';

    final hasQuotation =
        service['quotation_id'] != null;

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
  }

  Widget buildPendingServiceCard(
      Map<String, dynamic> service,
      ) {
    final vehicle =
        service['vehicles'] ?? <String, dynamic>{};

    final customer =
        service['customers'] ?? <String, dynamic>{};

    final quotation = service['quotations'];

    final status =
        service['status']?.toString() ??
            'Waiting Fix';

    final plate =
        vehicle['plate_number']
            ?.toString()
            .trim() ??
            '';

    final model =
        vehicle['car_model']
            ?.toString()
            .trim() ??
            '';

    final customerName =
        customer['name']
            ?.toString()
            .trim() ??
            '';

    final customerPhone =
        customer['phone']
            ?.toString()
            .trim() ??
            '';

    final type =
        service['service_type']
            ?.toString()
            .trim() ??
            'Walk-in';

    final estimatedCompletionText =
    formatStoredDateTime(
      service['estimated_completion_at'],
    );

    final createdAtText =
    formatStoredDateTime(
      service['created_at'],
    );

    final hasQuotation =
        service['quotation_id'] != null;

    final isCompleted =
        status == 'Completed';

    final quotationStatus =
        quotation?['status']
            ?.toString()
            .trim() ??
            'Not Created';

    final quotationItems =
        quotation?['quotation_items'] as List? ??
            [];

    final itemsTotal =
    calculateItemsTotal(
      quotationItems,
    );

    final storedTotal =
    double.tryParse(
      quotation?['total']?.toString() ?? '',
    );

    final quotationTotal =
    storedTotal == null ||
        (storedTotal <= 0 &&
            itemsTotal > 0)
        ? itemsTotal
        : storedTotal;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: getStatusColor(status)
              .withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color:
                    const Color(0xFFD7E5FA),
                    borderRadius:
                    BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.car_repair,
                    color: Color(0xFF339BFF),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        plate.isEmpty
                            ? 'NO PLATE NUMBER'
                            : plate,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        model.isEmpty
                            ? 'Car model not provided'
                            : model,
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
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
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color:
                    getStatusBackgroundColor(
                      status,
                    ),
                    borderRadius:
                    BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color:
                      getStatusColor(status),
                      fontWeight: FontWeight.bold,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                buildServiceBadge(
                  label: type,
                  icon: type.toLowerCase() ==
                      'walk-in'
                      ? Icons.directions_walk
                      : Icons.calendar_month,
                  color:
                  const Color(0xFF339BFF),
                ),
                buildServiceBadge(
                  label: hasQuotation
                      ? 'Quotation $quotationStatus'
                      : 'Quotation Not Created',
                  icon: Icons.receipt_long,
                  color: hasQuotation
                      ? Colors.purple
                      : Colors.orange,
                ),
              ],
            ),

            const SizedBox(height: 14),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color:
                const Color(0xFFF7F9FC),
                borderRadius:
                BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  buildServiceInformationRow(
                    icon: Icons.person_outline,
                    title: 'Customer',
                    value: customerName,
                  ),
                  const SizedBox(height: 11),
                  const Divider(height: 1),
                  const SizedBox(height: 11),
                  buildServiceInformationRow(
                    icon: Icons.phone_outlined,
                    title: 'Phone',
                    value: customerPhone,
                  ),
                  const SizedBox(height: 11),
                  const Divider(height: 1),
                  const SizedBox(height: 11),
                  buildServiceInformationRow(
                    icon: Icons.access_time,
                    title: 'Queue Created',
                    value: createdAtText,
                  ),
                  if (hasQuotation) ...[
                    const SizedBox(height: 11),
                    const Divider(height: 1),
                    const SizedBox(height: 11),
                    buildServiceInformationRow(
                      icon:
                      Icons.payments_outlined,
                      title: 'Quotation Total',
                      value:
                      'RM ${quotationTotal.toStringAsFixed(2)}',
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            const Row(
              children: [
                Icon(
                  Icons.timeline,
                  color: Color(0xFF339BFF),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Service Progress',
                  style: TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: statusList.contains(status)
                  ? status
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Update Status',
                floatingLabelBehavior:
                FloatingLabelBehavior.always,
                prefixIcon: Icon(
                  Icons.sync,
                  color:
                  getStatusColor(status),
                ),
                filled: true,
                fillColor:
                getStatusBackgroundColor(
                  status,
                ),
                border: OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              items: statusList.map(
                    (itemStatus) {
                  final isWaitingArrival =
                      itemStatus ==
                          'Waiting Arrived';

                  return DropdownMenuItem<String>(
                    value: itemStatus,
                    enabled: !isWaitingArrival,
                    child: Text(
                      itemStatus,
                      style: TextStyle(
                        color: isWaitingArrival
                            ? Colors.black38
                            : const Color(
                          0xFF1F2937,
                        ),
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                  );
                },
              ).toList(),
              onChanged: isCompleted
                  ? null
                  : (value) async {
                if (value == null ||
                    value == status) {
                  return;
                }

                DateTime? estimatedTime;

                if (value ==
                    'In Progress') {
                  estimatedTime =
                  await showEstimatedCompletionDialog(
                    service,
                  );

                  if (estimatedTime ==
                      null) {
                    return;
                  }
                }

                final confirmed =
                await showStatusChangeConfirmation(
                  service: service,
                  newStatus: value,
                  estimatedCompletionAt:
                  estimatedTime,
                );

                if (!confirmed) {
                  return;
                }

                await updatePendingStatus(
                  service,
                  value,
                  estimatedCompletionAt:
                  estimatedTime,
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
                  color: Colors.blue.shade50,
                  borderRadius:
                  BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.blue
                        .withOpacity(0.22),
                  ),
                ),
                child:
                buildServiceInformationRow(
                  icon: Icons.schedule,
                  title:
                  'Estimated Completion',
                  value:
                  estimatedCompletionText,
                ),
              ),
            ],

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style:
                    OutlinedButton.styleFrom(
                      foregroundColor:
                      const Color(
                        0xFF339BFF,
                      ),
                      side: const BorderSide(
                        color:
                        Color(0xFF339BFF),
                      ),
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(
                          14,
                        ),
                      ),
                    ),
                    onPressed: () {
                      showPendingServiceDetailDialog(
                        service,
                      );
                    },
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                    ),
                    label:
                    const Text('View Details'),
                  ),
                ),
                if (!hasQuotation &&
                    !isCompleted) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style:
                      ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(
                          0xFF339BFF,
                        ),
                        foregroundColor:
                        Colors.white,
                        shape:
                        RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(
                            14,
                          ),
                        ),
                      ),
                      onPressed: () {
                        openCreateQuotation(
                          service,
                        );
                      },
                      icon: const Icon(
                        Icons.receipt_long,
                        size: 18,
                      ),
                      label: const Text(
                        'Quotation',
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  tooltip:
                  'Delete Pending Service',
                  style: IconButton.styleFrom(
                    backgroundColor:
                    Colors.red.shade50,
                    foregroundColor:
                    Colors.red,
                  ),
                  onPressed: () {
                    handleDeletePendingService(
                      service,
                    );
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                ),
              ],
            ),
          ],
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
                          title: 'Active Queue',
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
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    buildStatusColumnButton(
                      'Waiting Fix',
                    ),
                    const SizedBox(width: 8),
                    buildStatusColumnButton(
                      'In Progress',
                    ),
                    const SizedBox(width: 8),
                    buildStatusColumnButton(
                      'Completed',
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
                        '$selectedStatusColumn Services',
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
                        '${displayCars.length} vehicle(s)',
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
            if (displayCars.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No $selectedStatusColumn service found.',
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