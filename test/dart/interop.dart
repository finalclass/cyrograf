// Cross-language Wire interop runner for generated Dart.
//
//   dart interop.dart check   MESSAGES_JSON OUT_JSON
//   dart interop.dart verify  IN_JSON
//   dart interop.dart invalid INVALID_JSON

import 'dart:convert';
import 'dart:io';

import 'common.dart' as common;
import 'orders.dart' as orders;
import 'wire.dart' as w;

typedef Roundtrip = String Function(String);
typedef ByteRoundtrip = String Function(List<int>);

final Map<String, Roundtrip> registry = {
  'Orders.ReserveRequest': (text) =>
      orders.ReserveRequest.fromDrut(text).toDrut(),
  'Orders.Reservation': (text) =>
      orders.Reservation.fromDrut(text).toDrut(),
  'Orders.Problem': (text) => orders.Problem.fromDrut(text).toDrut(),
  'Orders.ReserveResponse': (text) =>
      orders.ReserveResponse.fromDrut(text).toDrut(),
  'Orders.ReservationBatch': (text) =>
      orders.ReservationBatch.fromDrut(text).toDrut(),
  'Orders.Guard': (text) => orders.Guard.fromDrut(text).toDrut(),
  'Orders.ListBox': (text) => orders.ListBox.fromDrut(text).toDrut(),
  'Orders.ResponseBox': (text) =>
      orders.ResponseBox.fromDrut(text).toDrut(),
  'Orders.Scalars': (text) => orders.Scalars.fromDrut(text).toDrut(),
  'Common.UserCtx': (text) =>
      common.UserCtx.fromDrut(text).toDrut(),
  'Common.Wrapper': (text) =>
      common.Wrapper.fromDrut(text).toDrut(),
  'Common.Blob': (text) => common.Blob.fromDrut(text).toDrut(),
  'Common.Empty': (text) => common.Empty.fromDrut(text).toDrut(),
  'Common.VoidBox': (text) => common.VoidBox.fromDrut(text).toDrut(),
};

// Strict adapter-side byte-to-text step. Dart's utf8 decoder drops a leading
// BOM, so it is restored as U+FEFF to let the generated text conversions apply
// their documented BOM policy.
String _strictText(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return '\uFEFF' + utf8.decode(bytes.sublist(3));
  }
  return utf8.decode(bytes);
}

final Map<String, ByteRoundtrip> byteRegistry = {
  'Orders.ReserveRequest': (bytes) =>
      orders.ReserveRequest.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.Reservation': (bytes) =>
      orders.Reservation.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.Problem': (bytes) =>
      orders.Problem.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.ReserveResponse': (bytes) =>
      orders.ReserveResponse.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.ReservationBatch': (bytes) =>
      orders.ReservationBatch.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.Guard': (bytes) =>
      orders.Guard.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.ListBox': (bytes) =>
      orders.ListBox.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.ResponseBox': (bytes) =>
      orders.ResponseBox.fromDrut(_strictText(bytes)).toDrut(),
  'Orders.Scalars': (bytes) =>
      orders.Scalars.fromDrut(_strictText(bytes)).toDrut(),
  'Common.UserCtx': (bytes) =>
      common.UserCtx.fromDrut(_strictText(bytes)).toDrut(),
  'Common.Wrapper': (bytes) =>
      common.Wrapper.fromDrut(_strictText(bytes)).toDrut(),
  'Common.Blob': (bytes) =>
      common.Blob.fromDrut(_strictText(bytes)).toDrut(),
  'Common.Empty': (bytes) =>
      common.Empty.fromDrut(_strictText(bytes)).toDrut(),
  'Common.VoidBox': (bytes) =>
      common.VoidBox.fromDrut(_strictText(bytes)).toDrut(),
};

const Set<String> primitives = {
  'void',
  'int',
  'float',
  'bool',
  'string',
  'date',
  'record',
};

Never fail(String message) {
  stderr.writeln('FAIL: $message');
  exit(1);
}

List<Map<String, dynamic>> readEntries(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  return (decoded as List).cast<Map<String, dynamic>>();
}

String roundtrip(Map<String, dynamic> item) {
  final ops = registry[item['type']];
  if (ops == null) fail('unknown type ${item['type']}');
  return ops(item['wire'] as String);
}

bool deepEquals(dynamic left, dynamic right) {
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!deepEquals(left[i], right[i])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key)) return false;
      if (!deepEquals(left[key], right[key])) return false;
    }
    return true;
  }
  if (left is num && right is num) return left == right;
  return left == right;
}

bool sameJson(String left, String right) =>
    deepEquals(jsonDecode(left), jsonDecode(right));

void check(List<String> args) {
  final entries = readEntries(args[0]);
  final results = <Map<String, dynamic>>[];
  for (final item in entries) {
    final reencoded = roundtrip(item);
    final semantic = item['semantic'] == true;
    final matches =
        semantic ? sameJson(reencoded, item['wire'] as String) : reencoded == item['wire'];
    if (!matches) {
      fail('${item['id']} (${item['type']}): $reencoded != ${item['wire']}');
    }
    results.add({
      'id': item['id'],
      'type': item['type'],
      'wire': reencoded,
      if (semantic) 'semantic': true,
    });
  }
  File(args[1]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('dart verified ${entries.length} fixture(s)');
}

void verify(List<String> args) {
  final entries = readEntries(args[0]);
  for (final item in entries) {
    final reencoded = roundtrip(item);
    if (!sameJson(reencoded, item['wire'] as String)) {
      fail('${item['id']} (${item['type']}): $reencoded != ${item['wire']}');
    }
  }
  stdout.writeln('dart decoded ${entries.length} message(s) from peer');
}

void invalid(List<String> args) {
  final entries = readEntries(args[0]);
  for (final item in entries) {
    try {
      roundtrip(item);
      fail('${item['id']} (${item['type']}): invalid wire accepted');
    } on Object {
      // Expected rejection.
    }
  }
  stdout.writeln('dart rejected ${entries.length} invalid message(s)');
}

// optional checks absence versus a present empty value for optional
// String/List/variant fields, as api.md prescribes.
void optional() {
  void expect(String label, String got, String want) {
    if (got != want) fail('$label: $got != $want');
  }

  final absent =
      orders.ReserveRequest(ownerId: 'o1', quantity: 2).toDrut();
  expect('absent string', absent, '["o1",2,null]');
  final empty =
      orders.ReserveRequest(ownerId: 'o1', quantity: 2, note: '').toDrut();
  expect('present empty string', empty, '["o1",2,""]');
  if (absent == empty) fail('absent and empty string encode identically');
  final decodedAbsent = orders.ReserveRequest.fromDrut(absent);
  if (decodedAbsent.note != null) fail('decoded absent string is not null');
  final decodedEmpty = orders.ReserveRequest.fromDrut(empty);
  if (decodedEmpty.note != '') fail('decoded empty string is not present');

  final nilList = orders.ListBox(items: null).toDrut();
  expect('absent list', nilList, '[null]');
  final emptyList = orders.ListBox(items: <orders.Reservation>[]).toDrut();
  expect('empty list', emptyList, '[[]]');
  if (nilList == emptyList) fail('null and empty list encode identically');
  final decodedList = orders.ListBox.fromDrut(emptyList);
  if (decodedList.items == null || decodedList.items!.isEmpty == false) {
    fail('decoded empty list is not a present empty list');
  }

  final nilVariant = orders.ResponseBox(response: null).toDrut();
  expect('absent variant', nilVariant, '[null]');
  final presentVariant =
      orders.ResponseBox(response: const orders.ReserveResponseUnavailable())
          .toDrut();
  expect('present void variant', presentVariant, '[["Unavailable",null]]');

  var rejected = false;
  try {
    orders.ReserveRequest.fromDrut('["o1","x",null]');
  } on Object {
    rejected = true;
  }
  if (!rejected) fail('wrong required type accepted');
  stdout.writeln('dart optional checks passed');
}

List<int> _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

List<int> _caseBytes(Map<String, dynamic> item) {
  final hex = item['wire_hex'];
  if (hex is String) return _hexToBytes(hex);
  final wire = item['wire'];
  if (wire is String) return utf8.encode(wire);
  fail('${item['id']}: case has neither wire nor wire_hex');
}

dynamic _decodeDesc(dynamic desc, dynamic value) {
  if (desc is String) {
    switch (desc) {
      case 'void':
        w.Wire.asNull(value, '');
        return null;
      case 'int':
        return w.Wire.asInt(value, '');
      case 'float':
        return w.Wire.asFloat(value, '');
      case 'bool':
        return w.Wire.asBool(value, '');
      case 'string':
      case 'date':
        return w.Wire.asString(value, '');
      case 'record':
        return w.Wire.asRecord(value, '');
      default:
        throw StateError('unknown type $desc');
    }
  }
  if (desc is Map && desc.containsKey('list')) {
    final inner = desc['list'];
    final arr = w.Wire.asArray(value, '');
    return arr.map((item) => _decodeDesc(inner, item)).toList();
  }
  throw StateError('unsupported root descriptor');
}

dynamic _runDrutCase(Map<String, dynamic> item) {
  final bytes = _caseBytes(item);
  final desc = item['type'];
  if (desc is String && !primitives.contains(desc)) {
    final ops = byteRegistry[desc];
    if (ops == null) throw StateError('unknown type $desc');
    return jsonDecode(ops(bytes));
  }
  final value = w.Wire.parseBytes(bytes);
  final produced = _decodeDesc(desc, value);
  return jsonDecode(w.Wire.stringify(produced));
}

void drut(List<String> args) {
  final valid = readEntries(args[0]);
  final invalid = readEntries(args[1]);
  final results = <Map<String, dynamic>>[];
  String categoryOf(Map<String, dynamic> item) =>
      item['category'] as String? ?? 'runtime';
  for (final item in valid) {
    if (item['utf8_invalid'] == true) {
      // The text-only public API cannot represent invalid UTF-8 bytes.
      results.add({'id': item['id'], 'status': 'inexpressible'});
      continue;
    }
    final produced = _runDrutCase(item);
    final desc = item['type'];
    final isNamed = desc is String && !primitives.contains(desc);
    final expected =
        isNamed ? jsonDecode(item['wire'] as String) : item['value'];
    if (!deepEquals(produced, expected)) {
      fail('${item['id']}: produced value does not match');
    }
    results.add({
      'id': item['id'],
      'status': categoryOf(item) == 'public' ? 'executed' : 'executed-runtime',
    });
  }
  for (final item in invalid) {
    if (item['utf8_invalid'] == true) {
      results.add({'id': item['id'], 'status': 'inexpressible'});
      continue;
    }
    var rejected = false;
    try {
      _runDrutCase(item);
    } on Object {
      rejected = true;
    }
    if (!rejected) fail('${item['id']}: invalid wire accepted');
    results.add({
      'id': item['id'],
      'status': categoryOf(item) == 'public' ? 'rejected' : 'rejected-runtime',
    });
  }
  File(args[2]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln(
      'dart drut: ${valid.length} executed, ${invalid.length} rejected');
}

void main(List<String> argv) {
  if (argv.length < 1) fail('usage: interop <check|verify|invalid|drut|optional> <input> [output]');
  switch (argv[0]) {
    case 'drut':
      if (argv.length != 4) {
        fail('usage: interop drut <valid.json> <invalid.json> <out.json>');
      }
      drut(argv.sublist(1));
      return;
    case 'optional':
      optional();
      return;
    case 'check':
      if (argv.length != 3) fail('usage: interop check <messages.json> <out.json>');
      check(argv.sublist(1));
    case 'verify':
      if (argv.length != 2) fail('usage: interop verify <in.json>');
      verify(argv.sublist(1));
    case 'invalid':
      if (argv.length != 2) fail('usage: interop invalid <invalid.json>');
      invalid(argv.sublist(1));
    default:
      fail('unknown mode ${argv[0]}');
  }
}