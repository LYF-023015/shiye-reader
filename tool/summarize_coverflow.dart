import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final response =
      jsonDecode(
            await File('build/integration_response_data.json').readAsString(),
          )
          as Map<String, dynamic>;
  final timeline = Timeline.fromJson(
    (response['coverflow'] as Map).cast<String, dynamic>(),
  );
  final summary = TimelineSummary.summarize(timeline);
  await summary.writeTimelineToFile(
    'coverflow',
    destinationDirectory: 'build/performance',
    pretty: true,
  );
  final values = summary.summaryJson;
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'average_frame_build_time_millis':
          values['average_frame_build_time_millis'],
      '90th_percentile_frame_build_time_millis':
          values['90th_percentile_frame_build_time_millis'],
      '99th_percentile_frame_build_time_millis':
          values['99th_percentile_frame_build_time_millis'],
      'missed_frame_build_budget_count':
          values['missed_frame_build_budget_count'],
      'average_frame_rasterizer_time_millis':
          values['average_frame_rasterizer_time_millis'],
      '90th_percentile_frame_rasterizer_time_millis':
          values['90th_percentile_frame_rasterizer_time_millis'],
      '99th_percentile_frame_rasterizer_time_millis':
          values['99th_percentile_frame_rasterizer_time_millis'],
      'missed_frame_rasterizer_budget_count':
          values['missed_frame_rasterizer_budget_count'],
      'frame_count': values['frame_count'],
    }),
  );
}
