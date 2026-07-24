import 'package:flutter/material.dart';

import '../admin/admin_main_page.dart';
import '../admin/admin_bookings_page.dart';
import '../admin/admin_quotations_page.dart';
import '../admin/pending_service_page.dart';
import '../admin/vehicle_management_page.dart';
import '../customer/navigation_control.dart';
import 'app_result_message.dart';

class NotificationNavigationService {
  NotificationNavigationService._();

  static String? resolveTargetPage({
    required Map<String, dynamic> notification,
    required bool isAdmin,
  }) {
    final storedTarget =
    notification['target_page']
        ?.toString()
        .trim()
        .toLowerCase();

    if (storedTarget != null &&
        storedTarget.isNotEmpty) {
      return _normalizeTarget(
        storedTarget,
        isAdmin: isAdmin,
      );
    }

    final type =
        notification['notification_type']
            ?.toString()
            .toLowerCase() ??
            '';

    final title =
        notification['title']
            ?.toString()
            .toLowerCase() ??
            '';

    final message =
        notification['message']
            ?.toString()
            .toLowerCase() ??
            '';

    final combinedText =
        '$type $title $message';

    if (combinedText.contains(
      'vehicle claim',
    ) ||
        combinedText.contains(
          'claim request',
        ) ||
        combinedText.contains(
          'claim approved',
        ) ||
        combinedText.contains(
          'claim rejected',
        )) {
      return isAdmin
          ? 'vehicle_management'
          : 'my_vehicles';
    }

    if (combinedText.contains(
      'service record',
    ) ||
        combinedText.contains(
          'record available',
        ) ||
        combinedText.contains(
          'record created',
        )) {
      return isAdmin
          ? 'admin_records'
          : 'service_records';
    }

    if (combinedText.contains(
      'quotation confirmed',
    )) {
      return isAdmin
          ? 'pending_service'
          : 'customer_quotations';
    }

    if (combinedText.contains(
      'quotation',
    ) ||
        combinedText.contains('quote')) {
      return isAdmin
          ? 'admin_quotations'
          : 'customer_quotations';
    }

    if (combinedText.contains(
      'pending service',
    ) ||
        combinedText.contains(
          'vehicle status',
        ) ||
        combinedText.contains(
          'service completed',
        ) ||
        combinedText.contains(
          'vehicle arrived',
        ) ||
        combinedText.contains(
          'waiting fix',
        ) ||
        combinedText.contains(
          'in progress',
        )) {
      return isAdmin
          ? 'pending_service'
          : 'my_bookings';
    }

    if (combinedText.contains(
      'booking',
    ) ||
        combinedText.contains(
          'appointment',
        )) {
      return isAdmin
          ? 'admin_bookings'
          : 'my_bookings';
    }

    if (combinedText.contains(
      'customer',
    )) {
      return isAdmin
          ? 'admin_customers'
          : null;
    }

    return null;
  }

  static String? _normalizeTarget(
      String target, {
        required bool isAdmin,
      }) {
    switch (target) {
      case 'my_vehicles':
      case 'customer_vehicles':
      case 'vehicle':
        return isAdmin
            ? 'vehicle_management'
            : 'my_vehicles';

      case 'my_bookings':
      case 'customer_bookings':
      case 'booking':
        return isAdmin
            ? 'admin_bookings'
            : 'my_bookings';

      case 'customer_quotations':
      case 'quotation':
        return isAdmin
            ? 'admin_quotations'
            : 'customer_quotations';

      case 'service_records':
      case 'service_record':
      case 'record':
        return isAdmin
            ? 'admin_records'
            : 'service_records';

      case 'admin_bookings':
      case 'bookings':
        return isAdmin
            ? 'admin_bookings'
            : 'my_bookings';

      case 'pending_service':
      case 'pending_services':
        return isAdmin
            ? 'pending_service'
            : 'my_bookings';

      case 'vehicle_management':
      case 'vehicles':
        return isAdmin
            ? 'vehicle_management'
            : 'my_vehicles';

      case 'admin_quotations':
      case 'quotations':
        return isAdmin
            ? 'admin_quotations'
            : 'customer_quotations';

      case 'admin_records':
      case 'records':
        return isAdmin
            ? 'admin_records'
            : 'service_records';

      case 'admin_customers':
      case 'customers':
        return isAdmin
            ? 'admin_customers'
            : null;

      default:
        return target;
    }
  }

  static bool canOpen({
    required Map<String, dynamic> notification,
    required bool isAdmin,
  }) {
    final target = resolveTargetPage(
      notification: notification,
      isAdmin: isAdmin,
    );

    const supportedTargets = {
      'my_vehicles',
      'my_bookings',
      'customer_quotations',
      'service_records',
      'admin_bookings',
      'pending_service',
      'vehicle_management',
      'admin_quotations',
      'admin_records',
      'admin_customers',
    };

    return target != null &&
        supportedTargets.contains(target);
  }

  static Future<bool> openRelatedPage(
      BuildContext context, {
        required Map<String, dynamic> notification,
        required bool isAdmin,
      }) async {
    final target = resolveTargetPage(
      notification: notification,
      isAdmin: isAdmin,
    );

    if (target == null) {
      AppResultMessage.info(
        context,
        message:
        'This notification does not have a related page.',
      );
      return false;
    }

    if (isAdmin) {
      return _openAdminRelatedPage(
        context,
        target: target,
        notification: notification,
      );
    }

    return _openCustomerRelatedPage(
      context,
      target: target,
    );
  }

  static Future<bool>
  _openCustomerRelatedPage(
      BuildContext context, {
        required String target,
      }) async {
    final customerIndex =
    _customerBottomBarIndex(target);

    if (customerIndex == null) {
      AppResultMessage.info(
        context,
        message:
        'The related customer page is unavailable.',
      );
      return false;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NavigationControl(
          initialIndex: customerIndex,
        ),
      ),
    );

    return true;
  }

  static Future<bool> _openAdminRelatedPage(
      BuildContext context, {
        required String target,
        required Map<String, dynamic>
        notification,
      }) async {
    final bookingId = _cleanValue(
      notification['booking_id'],
    );

    final vehicleId = _cleanValue(
      notification['vehicle_id'],
    );

    final plateNumber = _cleanValue(
      notification['plate_number'],
    );

    int selectedIndex = 0;
    Widget? relatedPage;

    switch (target) {
      case 'admin_bookings':
        selectedIndex = 1;
        relatedPage = AdminBookingsPage(
          initialBookingId: bookingId,
        );
        break;

      case 'admin_customers':
        selectedIndex = 2;
        break;

      case 'admin_records':
        selectedIndex = 4;
        break;

      case 'pending_service':
        selectedIndex = 1;
        relatedPage =
        const PendingServicePage();
        break;

      case 'admin_quotations':
        selectedIndex = 1;
        relatedPage =
        const AdminQuotationsPage();
        break;

      case 'vehicle_management':
        selectedIndex = 2;
        relatedPage =
            VehicleManagementPage(
              initialVehicleId: vehicleId,
              initialPlateNumber: plateNumber,
            );
        break;

      default:
        AppResultMessage.info(
          context,
          message:
          'The related admin page is unavailable.',
        );
        return false;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminMainPage(
          initialIndex: selectedIndex,
          initialRelatedPage: relatedPage,
        ),
      ),
    );

    return true;
  }

  static int? _customerBottomBarIndex(
      String target,
      ) {
    switch (target) {
      case 'my_vehicles':
        return 1;

      case 'my_bookings':
        return 2;

      case 'customer_quotations':
        return 3;

      case 'service_records':
        return 4;

      default:
        return null;
    }
  }

  static String? _cleanValue(
      dynamic value,
      ) {
    final text =
    value?.toString().trim();

    if (text == null ||
        text.isEmpty ||
        text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }
}
