// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_eventbridge/otel_eventbridge.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_eventbridge-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('PutEvents records PRODUCER span', () async {
    await tracedEventbridgePutEvents<String>(
      eventBus: 'orders-bus',
      source: 'com.example.orders',
      detailType: 'OrderPlaced',
      region: 'us-east-1',
      entryCount: 1,
      invoke: () async => const EventbridgePutResult(
        value: 'ok',
        eventId: 'evt-1',
        failedEntryCount: 0,
      ),
    );
    final span = spans.findSpanByName('put-events orders-bus');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.producer);
    final a = attrsOf(span);
    expect(a['messaging.system'], 'aws_eventbridge');
    expect(a['messaging.destination.name'], 'orders-bus');
    expect(a['aws.eventbridge.event_bus.name'], 'orders-bus');
    expect(a['aws.eventbridge.source'], 'com.example.orders');
    expect(a['aws.eventbridge.detail_type'], 'OrderPlaced');
    expect(a['cloud.region'], 'us-east-1');
    expect(a['messaging.batch.message_count'], 1);
    expect(a['messaging.message.id'], 'evt-1');
    expect(a['aws.eventbridge.event_id'], 'evt-1');
    expect(a['aws.eventbridge.failed_entry_count'], 0);
  });

  test('failed entries mark span Error', () async {
    await tracedEventbridgePutEvents<String>(
      eventBus: 'b',
      source: 's',
      detailType: 'D',
      invoke: () async => const EventbridgePutResult(
        value: 'ok',
        failedEntryCount: 2,
      ),
    );
    expect(spans.findSpanByName('put-events b')!.status, SpanStatusCode.Error);
  });

  test('records exception', () async {
    await expectLater(
      tracedEventbridgePutEvents<String>(
        eventBus: 'b',
        source: 's',
        detailType: 'd',
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(spans.findSpanByName('put-events b')!.status, SpanStatusCode.Error);
  });

  test('suppression skips spans', () async {
    await runWithoutEventbridgeInstrumentationAsync(() async {
      await tracedEventbridgePutEvents<String>(
        eventBus: 'b',
        source: 's',
        detailType: 'd',
        invoke: () async => const EventbridgePutResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('put-events '), isEmpty);
  });
}
