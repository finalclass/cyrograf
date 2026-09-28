// One endpoint of the cross-language optional-field exchange for Dart.
//
//   produce CASES_JSON OUT_JSON : encode each canonical optional case through
//       the public `toDrut`.
//   consume PEER_JSON           : decode a peer's encodings through the public
//       `OptionalBox.fromDrut`, check the typed field states and re-encode the
//       same Drut.

import 'dart:convert';
import 'dart:io';

import 'api.dart';

Never fail(String message) {
  stderr.writeln('FAIL: $message');
  exit(1);
}

List<Map<String, dynamic>> readEntries(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  return (decoded as List).cast<Map<String, dynamic>>();
}

final List<Map<String, dynamic>> cases = [
  {'id': 'absent', 'value': const OptionalBox(ownerId: 'o1')},
  {'id': 'empty_string', 'value': const OptionalBox(ownerId: 'o1', text: '')},
  {'id': 'zero', 'value': const OptionalBox(ownerId: 'o1', count: 0)},
  {'id': 'false', 'value': const OptionalBox(ownerId: 'o1', flag: false)},
  {'id': 'empty_list', 'value': const OptionalBox(ownerId: 'o1', items: <String>[])},
  {
    'id': 'variant_text',
    'value': const OptionalBox(ownerId: 'o1', choice: ChoiceText('x')),
  },
  {
    'id': 'variant_void',
    'value': const OptionalBox(ownerId: 'o1', choice: ChoiceEmpty()),
  },
  {
    'id': 'all_present',
    'value': const OptionalBox(
      ownerId: 'o1',
      text: '',
      count: 0,
      flag: false,
      items: <String>[],
      choice: ChoiceEmpty(),
    ),
  },
];

void checkSemantics(String id, OptionalBox value) {
  bool expected;
  switch (id) {
    case 'absent':
      expected = value.text == null &&
          value.count == null &&
          value.flag == null &&
          value.items == null &&
          value.choice == null;
    case 'empty_string':
      expected = value.text == '' &&
          value.count == null &&
          value.flag == null &&
          value.items == null &&
          value.choice == null;
    case 'zero':
      expected = value.text == null &&
          value.count == 0 &&
          value.flag == null &&
          value.items == null &&
          value.choice == null;
    case 'false':
      expected = value.text == null &&
          value.count == null &&
          value.flag == false &&
          value.items == null &&
          value.choice == null;
    case 'empty_list':
      expected = value.text == null &&
          value.count == null &&
          value.flag == null &&
          value.items != null &&
          value.items!.isEmpty &&
          value.choice == null;
    case 'variant_text':
      expected = value.text == null &&
          value.count == null &&
          value.flag == null &&
          value.items == null &&
          value.choice is ChoiceText &&
          (value.choice! as ChoiceText).value == 'x';
    case 'variant_void':
      expected = value.text == null &&
          value.count == null &&
          value.flag == null &&
          value.items == null &&
          value.choice is ChoiceEmpty;
    case 'all_present':
      expected = value.text == '' &&
          value.count == 0 &&
          value.flag == false &&
          value.items != null &&
          value.items!.isEmpty &&
          value.choice is ChoiceEmpty;
    default:
      fail('unknown case $id');
  }
  if (!expected) fail('case $id decoded to the wrong typed value');
}

void produce(List<String> args) {
  final canonical = <String, String>{
    for (final entry in readEntries(args[0])) entry['id'] as String: entry['wire'] as String,
  };
  final results = <Map<String, dynamic>>[];
  for (final item in cases) {
    final id = item['id'] as String;
    final wire = (item['value']! as OptionalBox).toDrut();
    final want = canonical[id];
    if (want == null) fail('no canonical wire for case $id');
    if (want != wire) fail('$id: encoded $wire, expected $want');
    results.add({'id': id, 'wire': wire});
  }
  File(args[1]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('dart produced ${results.length} optional case(s)');
}

void consume(List<String> args) {
  final entries = readEntries(args[0]);
  for (final item in entries) {
    final id = item['id'] as String;
    final wire = item['wire'] as String;
    final value = OptionalBox.fromDrut(wire);
    checkSemantics(id, value);
    final reencoded = value.toDrut();
    if (reencoded != wire) {
      fail('$id: re-encoded $reencoded, received $wire');
    }
  }
  stdout.writeln('dart consumed ${entries.length} optional case(s)');
}

void main(List<String> argv) {
  if (argv.length < 2) {
    fail('usage: optional_matrix <produce|consume> INPUT [OUT]');
  }
  switch (argv[0]) {
    case 'produce':
      if (argv.length != 3) fail('usage: optional_matrix produce CASES_JSON OUT_JSON');
      produce(argv.sublist(1));
    case 'consume':
      if (argv.length != 2) fail('usage: optional_matrix consume PEER_JSON');
      consume(argv.sublist(1));
    default:
      fail('unknown mode ${argv[0]}');
  }
}