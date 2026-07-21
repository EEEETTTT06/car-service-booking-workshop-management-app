import { createClient } from 'npm:@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get(
  'SUPABASE_SERVICE_ROLE_KEY',
);

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error(
    'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.',
  );
}

const supabase = createClient(
  supabaseUrl,
  serviceRoleKey,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  },
);

function getMalaysiaDate(daysAhead: number): string {
  const targetDate = new Date(
    Date.now() +
      daysAhead * 24 * 60 * 60 * 1000,
  );

  const parts = new Intl.DateTimeFormat(
    'en-CA',
    {
      timeZone: 'Asia/Kuala_Lumpur',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    },
  ).formatToParts(targetDate);

  const year =
    parts.find((part) => part.type === 'year')
      ?.value ?? '';

  const month =
    parts.find((part) => part.type === 'month')
      ?.value ?? '';

  const day =
    parts.find((part) => part.type === 'day')
      ?.value ?? '';

  return `${year}-${month}-${day}`;
}

function formatDisplayDate(
  sqlDate: string,
): string {
  const parts = sqlDate.split('-');

  if (parts.length != 3) {
    return sqlDate;
  }

  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json(
      {
        error: 'Method not allowed.',
      },
      {
        status: 405,
      },
    );
  }

  const authorization =
    request.headers.get('authorization');

  const apiKey =
    request.headers.get('apikey');

  const isAuthorized =
    authorization ===
      `Bearer ${serviceRoleKey}` ||
    apiKey === serviceRoleKey;

  if (!isAuthorized) {
    return Response.json(
      {
        error: 'Unauthorized.',
      },
      {
        status: 401,
      },
    );
  }

  try {
    const tomorrowDate =
      getMalaysiaDate(1);

    console.log(
      `Checking bookings for ${tomorrowDate}`,
    );

    const {
      data: bookings,
      error: bookingsError,
    } = await supabase
      .from('bookings')
      .select(`
        booking_id,
        customer_id,
        vehicle_id,
        appointment_date,
        status,
        reminder_sent_at
      `)
      .eq(
        'appointment_date',
        tomorrowDate,
      )
      .eq('status', 'Booked')
      .is('reminder_sent_at', null);

    if (bookingsError) {
      throw bookingsError;
    }

    if (!bookings || bookings.length === 0) {
      return Response.json({
        success: true,
        appointment_date: tomorrowDate,
        bookings_found: 0,
        reminders_created: 0,
      });
    }

    let remindersCreated = 0;
    let pushNotificationsSent = 0;
    const errors: string[] = [];

    for (const booking of bookings) {
      try {
        const {
          data: customer,
          error: customerError,
        } = await supabase
          .from('customers')
          .select(`
            customer_id,
            name,
            notification_enabled,
            fcm_token
          `)
          .eq(
            'customer_id',
            booking.customer_id,
          )
          .maybeSingle();

        if (customerError) {
          throw customerError;
        }

        if (!customer) {
          errors.push(
            `Customer not found for booking ${booking.booking_id}`,
          );
          continue;
        }

        const {
          data: vehicle,
          error: vehicleError,
        } = await supabase
          .from('vehicles')
          .select(`
            vehicle_id,
            plate_number,
            car_model
          `)
          .eq(
            'vehicle_id',
            booking.vehicle_id,
          )
          .maybeSingle();

        if (vehicleError) {
          throw vehicleError;
        }

        const plateNumber =
          vehicle?.plate_number?.toString() ??
          'your vehicle';

        const displayDate =
          formatDisplayDate(
            booking.appointment_date,
          );

        const title =
          'Appointment Reminder';

        const message =
          'Reminder: Your appointment for '
          `${plateNumber} is tomorrow, `
          `${displayDate}.`;

        const {
          error: notificationError,
        } = await supabase
          .from('notifications')
          .insert({
            customer_id:
              booking.customer_id,
            title: title,
            message: message,
            is_read: false,
            notification_type:
              'booking_reminder',
            target_page: 'my_bookings',
          });

        if (notificationError) {
          throw notificationError;
        }

        remindersCreated++;

        if (
          customer.notification_enabled !==
          false
        ) {
          const {
            data: tokenRows,
            error: tokenError,
          } = await supabase
            .from('customer_fcm_tokens')
            .select('fcm_token')
            .eq(
              'customer_id',
              booking.customer_id,
            );

          if (tokenError) {
            throw tokenError;
          }

          const tokens = new Set<string>();

          for (const row of tokenRows ?? []) {
            const token =
              row.fcm_token
                ?.toString()
                .trim();

            if (token) {
              tokens.add(token);
            }
          }

          const legacyToken =
            customer.fcm_token
              ?.toString()
              .trim();

          if (legacyToken) {
            tokens.add(legacyToken);
          }

          if (tokens.size > 0) {
            const {
              error: fcmError,
            } = await supabase
              .functions
              .invoke('send-fcm', {
                body: {
                  tokens:
                    Array.from(tokens),
                  title: title,
                  body: message,
                  data: {
                    target_page:
                      'my_bookings',
                    notification_type:
                      'booking_reminder',
                    booking_id:
                      booking.booking_id
                        .toString(),
                  },
                },
              });

            if (fcmError) {
              errors.push(
                `FCM failed for booking ${booking.booking_id}: ${fcmError.message}`,
              );
            } else {
              pushNotificationsSent +=
                tokens.size;
            }
          }
        }

        const {
          error: updateError,
        } = await supabase
          .from('bookings')
          .update({
            reminder_sent_at:
              new Date().toISOString(),
          })
          .eq(
            'booking_id',
            booking.booking_id,
          );

        if (updateError) {
          throw updateError;
        }
      } catch (bookingError) {
        const message =
          bookingError instanceof Error
            ? bookingError.message
            : bookingError.toString();

        errors.push(
          `Booking ${booking.booking_id}: ${message}`,
        );
      }
    }

    return Response.json({
      success: true,
      appointment_date: tomorrowDate,
      bookings_found: bookings.length,
      reminders_created:
        remindersCreated,
      push_notifications_sent:
        pushNotificationsSent,
      errors: errors,
    });
  } catch (error) {
    console.error(
      'Booking reminder error:',
      error,
    );

    return Response.json(
      {
        success: false,
        error:
          error instanceof Error
            ? error.message
            : error.toString(),
      },
      {
        status: 500,
      },
    );
  }
});