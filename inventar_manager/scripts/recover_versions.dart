import 'dart:io';
import 'dart:convert';

void main() async {
  final path = r'C:\Users\timos\.gemini\antigravity-ide\brain\0df20676-9131-466a-8de7-eb489943750c\.system_generated\logs\transcript_full.jsonl';
  final file = File(path);
  final lines = await file.readAsLines();

  final versions = <String, List<String>>{
    'dashboard_view.dart': [],
    'inventory_detail_view.dart': [],
    'inventory_list_view.dart': [],
  };

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
            
            for (final target in versions.keys) {
              if (targetFile.endsWith(target)) {
                versions[target]!.add(args['CodeContent'] as String);
              }
            }
          }
        }
      }
    } catch (e) {}
  }

  for (final entry in versions.entries) {
    for (int i = 0; i < entry.value.length; i++) {
      final out = File('old_${entry.key}_v$i.dart');
      await out.writeAsString(entry.value[i]);
      print('Recovered ${entry.key} v$i');
    }
  }
}
