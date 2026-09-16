import 'dart:io';
import 'dart:convert';

void main() async {
  final path = r'C:\Users\timos\.gemini\antigravity-ide\brain\0df20676-9131-466a-8de7-eb489943750c\.system_generated\logs\transcript_full.jsonl';
  final file = File(path);
  final lines = await file.readAsLines();

  print('Searching in ${lines.length} lines...');

  final targetFiles = [
    'dashboard_view.dart',
    'inventory_detail_view.dart',
    'inventory_list_view.dart'
  ];

  Map<String, String> latestCode = {};

  for (final line in lines) {
    if (!line.contains('write_to_file')) continue;

    try {
      final data = jsonDecode(line);
      if (data['type'] == 'PLANNER_RESPONSE') {
        final toolCalls = data['tool_calls'] as List;
        for (final call in toolCalls) {
          if (call['name'] == 'write_to_file') {
            final args = call['args'];
            final targetFile = args['TargetFile'] as String;
            
            for (final target in targetFiles) {
              if (targetFile.endsWith(target)) {
                latestCode[target] = args['CodeContent'] as String;
              }
            }
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }

  for (final entry in latestCode.entries) {
    final out = File('old_${entry.key}');
    await out.writeAsString(entry.value);
    print('Recovered ${entry.key} to old_${entry.key}');
  }
}
