import 'dart:convert';
import 'dart:io';

class CsvTable {
  CsvTable.parse(String input) : _readRows = (() => _readStringRows(input)) {
    final iterator = _readRows().iterator;
    if (iterator.moveNext()) {
      headers = _cleanHeaders(iterator.current.fields);
    } else {
      headers = const [];
    }
  }

  CsvTable.fromFile(File file)
    : _readRows = (() => _readFileRows(file)),
      headers = _readFileHeader(file);

  final Iterable<_CsvRow> Function() _readRows;
  late final List<String> headers;
  int invalidRowCount = 0;

  /// Rows are decoded lazily so large `stop_times.txt` files do not allocate
  /// a second list containing every CSV record.
  Iterable<Map<String, String>> get records sync* {
    var first = true;
    for (final row in _readRows()) {
      if (first) {
        first = false;
        continue;
      }
      if (row.fields.every((value) => value.isEmpty)) continue;
      if (row.malformed || row.fields.length != headers.length) {
        invalidRowCount++;
        continue;
      }
      yield <String, String>{
        for (var i = 0; i < headers.length; i++) headers[i]: row.fields[i],
      };
    }
  }

  static List<String> _cleanHeaders(List<String> fields) => [
    for (var i = 0; i < fields.length; i++)
      i == 0 ? fields[i].replaceFirst('\uFEFF', '') : fields[i],
  ];

  static List<String> _readFileHeader(File file) {
    final input = file.openSync();
    final bytes = <int>[];
    var quoted = false;
    try {
      while (true) {
        final byte = input.readByteSync();
        if (byte < 0) break;
        if (byte == 0x22) quoted = !quoted;
        if (!quoted && (byte == 0x0a || byte == 0x0d)) break;
        bytes.add(byte);
      }
    } finally {
      input.closeSync();
    }
    final row = _readStringRows(utf8.decode(bytes, allowMalformed: true))
        .firstOrNull;
    return row == null ? const [] : _cleanHeaders(row.fields);
  }

  static Iterable<_CsvRow> _readStringRows(String source) sync* {
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char == '"') {
        if (quoted && i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        row.add(field.toString());
        field.clear();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        row.add(field.toString());
        field.clear();
        if (char == '\r' && i + 1 < source.length && source[i + 1] == '\n') {
          i++;
        }
        yield _CsvRow(row, false);
        row = <String>[];
      } else {
        field.write(char);
      }
    }
    if (field.length > 0 || row.isNotEmpty) {
      row.add(field.toString());
      yield _CsvRow(row, quoted);
    }
  }

  /// Reads a CSV file in bounded-size chunks. GTFS stop_times can contain
  /// millions of records, so this avoids retaining the uncompressed table.
  static Iterable<_CsvRow> _readFileRows(File file) sync* {
    final probe = file.openSync();
    late final bool hasBom;
    try {
      final prefix = probe.readSync(3);
      hasBom =
          prefix.length == 3 &&
          prefix[0] == 0xef &&
          prefix[1] == 0xbb &&
          prefix[2] == 0xbf;
    } finally {
      probe.closeSync();
    }
    final input = file.openSync();
    if (hasBom) input.setPositionSync(3);
    final row = <String>[];
    final field = <int>[];
    var quoted = false;
    var pendingQuote = false;
    var skipLineFeed = false;

    String decodeField() => utf8.decode(field, allowMalformed: true);

    void finishField() {
      row.add(decodeField());
      field.clear();
    }

    try {
      while (true) {
        final chunk = input.readSync(64 * 1024);
        if (chunk.isEmpty) break;
        for (var byte in chunk) {
          if (skipLineFeed) {
            skipLineFeed = false;
            if (byte == 0x0a) continue;
          }
          if (pendingQuote) {
            pendingQuote = false;
            if (byte == 0x22) {
              field.add(byte);
              continue;
            }
            quoted = false;
          }
          if (quoted) {
            if (byte == 0x22) {
              pendingQuote = true;
            } else {
              field.add(byte);
            }
            continue;
          }
          if (byte == 0x22) {
            quoted = true;
          } else if (byte == 0x2c) {
            finishField();
          } else if (byte == 0x0a || byte == 0x0d) {
            finishField();
            yield _CsvRow(List<String>.of(row), false);
            row.clear();
            if (byte == 0x0d) skipLineFeed = true;
          } else {
            field.add(byte);
          }
        }
      }
      final malformed = quoted && !pendingQuote;
      if (pendingQuote) quoted = false;
      if (field.isNotEmpty || row.isNotEmpty) {
        finishField();
        yield _CsvRow(List<String>.of(row), malformed);
      }
    } finally {
      input.closeSync();
    }
  }
}

class _CsvRow {
  const _CsvRow(this.fields, this.malformed);
  final List<String> fields;
  final bool malformed;
}

int? parseGtfsTime(String value) {
  final match = RegExp(r'^(\d{1,3}):(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final hours = int.parse(match[1]!);
  final minutes = int.parse(match[2]!);
  final seconds = int.parse(match[3]!);
  if (minutes > 59 || seconds > 59) return null;
  return hours * 3600 + minutes * 60 + seconds;
}
