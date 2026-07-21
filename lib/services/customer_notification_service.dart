import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class CustomerNotificationService {
  const CustomerNotificationService._();

  static Future<void> sendToAllDevices({
    required String customerId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      final customer = await supabase
          .from('customers')
          .select(
        'notification_enabled, fcm_token',
      )
          .eq(
        'customer_id',
        customerId,
      )
          .maybeSingle();

      if (customer == null) {
        debugPrint(
          'Customer $customerId was not found.',
        );
        return;
      }

      if (customer['notification_enabled'] == false) {
        debugPrint(
          'Customer $customerId disabled notifications.',
        );
        return;
      }

      final tokenResponse = await supabase
          .from('customer_fcm_tokens')
          .select('fcm_token')
          .eq(
        'customer_id',
        customerId,
      );

      final tokenRows =
      List<Map<String, dynamic>>.from(
        tokenResponse,
      );

      final tokens = <String>{};

      for (final row in tokenRows) {
        final token =
        row['fcm_token']?.toString().trim();

        if (token != null && token.isNotEmpty) {
          tokens.add(token);
        }
      }

      // Temporary fallback for old devices.
      final oldToken =
      customer['fcm_token']?.toString().trim();

      if (oldToken != null && oldToken.isNotEmpty) {
        tokens.add(oldToken);
      }

      if (tokens.isEmpty) {
        debugPrint(
          'No FCM device token found for customer $customerId.',
        );
        return;
      }

      final response = await supabase.functions.invoke(
        'send-fcm',
        body: {
          'tokens': tokens.toList(),
          'title': title,
          'body': message,
          'data': data ?? <String, dynamic>{},
        },
      );

      debugPrint(
        'Customer multi-device FCM response: ${response.data}',
      );
    } catch (error) {
      debugPrint(
        'Failed to send customer multi-device notification: $error',
      );
    }
  }
}