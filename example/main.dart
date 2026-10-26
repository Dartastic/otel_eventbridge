// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_eventbridge/otel_eventbridge.dart';

/// Traces Eventbridge calls with OpenTelemetry.
///
/// `otel_eventbridge` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Eventbridge call in
/// [tracedEventbridgePutEvents]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'eventbridge-example');

  // Wraps an EventBridge PutEvents (single-event flavor) in a PRODUCER span using OTel messaging semconv.
  final eventbridgePutEventsId = await tracedEventbridgePutEvents<String>(
    eventBus: 'order.created',
    source: 'example',
    detailType: 'standard',
    region: 'us-east-1',
    entryCount: 3,
    invoke: () async {
      // Make the Eventbridge call here, then report what it returned.
      const id = 'eventbridge_8f3a2c';
      return const EventbridgePutResult(
          value: id, eventId: 'event_8f3a2c', failedEntryCount: 3);
    },
  );
  OTelLog.info('tracedEventbridgePutEvents returned $eventbridgePutEventsId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutEventbridgeInstrumentationAsync.
  await runWithoutEventbridgeInstrumentationAsync(
    () => tracedEventbridgePutEvents<String>(
      eventBus: 'order.created',
      source: 'example',
      detailType: 'standard',
      region: 'us-east-1',
      entryCount: 3,
      invoke: () async {
        const id = 'eventbridge_8f3a2c';
        return const EventbridgePutResult(
            value: id, eventId: 'event_8f3a2c', failedEntryCount: 3);
      },
    ),
  );

  await OTel.shutdown();
}
