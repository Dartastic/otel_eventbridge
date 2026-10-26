// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'otel_eventbridge_suppression.dart';

const _tracerName = 'dartastic_otel_libs_eventbridge';
const _systemValue = 'aws_eventbridge';

APITracer _tracer() => OTelAPI.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedEventbridgePutEvents` callback.
class EventbridgePutResult<T> {
  /// Creates a result.
  const EventbridgePutResult({
    required this.value,
    this.eventId,
    this.failedEntryCount,
  });

  /// The value returned to the caller.
  final T value;
  final String? eventId;
  final int? failedEntryCount;
}

/// Wraps an EventBridge `PutEvents` (single-event flavor) in a
/// PRODUCER span using OTel messaging semconv.
Future<T> tracedEventbridgePutEvents<T>({
  required String eventBus,
  required String source,
  required String detailType,
  required Future<EventbridgePutResult<T>> Function() invoke,
  String? region,
  int? entryCount,
}) async {
  if (eventbridgeInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'messaging.system': _systemValue,
    'messaging.operation': 'publish',
    'messaging.destination.name': eventBus,
    'aws.eventbridge.event_bus.name': eventBus,
    'aws.eventbridge.source': source,
    'aws.eventbridge.detail_type': detailType,
  };
  if (region != null) m['cloud.region'] = region;
  if (entryCount != null) m['messaging.batch.message_count'] = entryCount;

  final span = _tracer().startSpan(
    'put-events $eventBus',
    kind: SpanKind.producer,
    attributes: OTelAPI.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.eventId != null) {
      extras.add(OTelAPI.attributeString('messaging.message.id', r.eventId!));
      extras
          .add(OTelAPI.attributeString('aws.eventbridge.event_id', r.eventId!));
    }
    if (r.failedEntryCount != null) {
      extras.add(OTelAPI.attributeInt(
        'aws.eventbridge.failed_entry_count',
        r.failedEntryCount!,
      ));
      if (r.failedEntryCount! > 0) {
        span.setStatus(
          SpanStatusCode.Error,
          'EventBridge reported ${r.failedEntryCount} failed entries',
        );
      }
    }
    if (extras.isNotEmpty) span.addAttributes(OTelAPI.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTelAPI.attributes([
      OTelAPI.attributeString(
        ErrorAttributes.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
