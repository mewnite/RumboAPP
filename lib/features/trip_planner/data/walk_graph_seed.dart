import "dart:convert";
import "dart:typed_data";

import "package:crypto/crypto.dart";

class WalkGraphSeedData {
  const WalkGraphSeedData({
    required this.vertexCoordinates,
    required this.edgeEndpoints,
    required this.edgeLengthsMeters,
    required this.edgeGeometryOffsets,
    required this.edgeGeometryCoordinates,
    required this.adjacencyOffsets,
    required this.adjacencyEdgeIds,
    required this.sourceDate,
    required this.sourceSha256,
    required this.boundsMicrodegrees,
    required this.wayCount,
  });

  final Int32List vertexCoordinates;
  final Int32List edgeEndpoints;
  final Float32List edgeLengthsMeters;
  final Int32List edgeGeometryOffsets;
  final Int32List edgeGeometryCoordinates;
  final Int32List adjacencyOffsets;
  final Int32List adjacencyEdgeIds;
  final String sourceDate;
  final String sourceSha256;
  final Int32List boundsMicrodegrees;
  final int wayCount;

  int get vertexCount => vertexCoordinates.length ~/ 2;
  int get edgeCount => edgeLengthsMeters.length;
  int get geometryPointCount => edgeGeometryCoordinates.length ~/ 2;
  int get arrayBytes =>
      (vertexCoordinates.length +
          edgeEndpoints.length +
          edgeLengthsMeters.length +
          edgeGeometryOffsets.length +
          edgeGeometryCoordinates.length +
          adjacencyOffsets.length +
          adjacencyEdgeIds.length) *
      4;
}

class WalkGraphSeedCodec {
  const WalkGraphSeedCodec._();

  static const int version = 1;
  static const int _headerBytes = 136;
  static const int _digestBytes = 32;
  static const int _sectionCount = 7;
  static const List<int> _magic = [0x52, 0x57, 0x42, 0x31];

  static Uint8List encode(WalkGraphSeedData data) {
    _validateData(data);
    final sections = <Uint8List>[
      _encodeInt32s(data.vertexCoordinates),
      _encodeInt32s(data.edgeEndpoints),
      _encodeFloat32s(data.edgeLengthsMeters),
      _encodeInt32s(data.edgeGeometryOffsets),
      _encodeInt32s(data.edgeGeometryCoordinates),
      _encodeInt32s(data.adjacencyOffsets),
      _encodeInt32s(data.adjacencyEdgeIds),
    ];
    final totalBytes =
        _headerBytes +
        sections.fold<int>(0, (total, section) => total + section.length) +
        _digestBytes;
    final bytes = Uint8List(totalBytes);
    final header = ByteData.sublistView(bytes);
    for (var i = 0; i < _magic.length; i++) {
      bytes[i] = _magic[i];
    }
    header.setUint16(4, version, Endian.little);
    header.setUint16(6, _headerBytes, Endian.little);
    bytes.setRange(8, 14, ascii.encode(data.sourceDate));
    bytes.setRange(14, 46, _decodeHex(data.sourceSha256));
    for (var i = 0; i < 4; i++) {
      header.setInt32(46 + i * 4, data.boundsMicrodegrees[i], Endian.little);
    }
    header.setUint32(62, data.vertexCount, Endian.little);
    header.setUint32(66, data.edgeCount, Endian.little);
    header.setUint32(70, data.geometryPointCount, Endian.little);
    header.setUint32(74, data.wayCount, Endian.little);

    var offset = _headerBytes;
    for (var i = 0; i < sections.length; i++) {
      header.setUint32(78 + i * 8, offset, Endian.little);
      header.setUint32(82 + i * 8, sections[i].length, Endian.little);
      bytes.setRange(offset, offset + sections[i].length, sections[i]);
      offset += sections[i].length;
    }
    final digest = sha256.convert(bytes.sublist(0, offset)).bytes;
    bytes.setRange(offset, offset + digest.length, digest);
    return bytes;
  }

  static WalkGraphSeedData decode(Uint8List bytes) {
    if (bytes.length < _headerBytes + _digestBytes) {
      throw const FormatException("Seed peatonal truncada.");
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException("Magic inválido para seed peatonal.");
      }
    }
    final header = ByteData.sublistView(bytes);
    if (header.getUint16(4, Endian.little) != version ||
        header.getUint16(6, Endian.little) != _headerBytes) {
      throw const FormatException("Versión de seed peatonal no soportada.");
    }
    final vertexCount = header.getUint32(62, Endian.little);
    final edgeCount = header.getUint32(66, Endian.little);
    final pointCount = header.getUint32(70, Endian.little);
    final wayCount = header.getUint32(74, Endian.little);
    final expectedLengths = <int>[
      vertexCount * 8,
      edgeCount * 8,
      edgeCount * 4,
      (edgeCount + 1) * 4,
      pointCount * 8,
      (vertexCount + 1) * 4,
      edgeCount * 2 * 4,
    ];
    final sectionOffsets = <int>[];
    var expectedOffset = _headerBytes;
    for (var i = 0; i < _sectionCount; i++) {
      final offset = header.getUint32(78 + i * 8, Endian.little);
      final length = header.getUint32(82 + i * 8, Endian.little);
      if (offset != expectedOffset || length != expectedLengths[i]) {
        throw const FormatException("Offsets o tamaños inválidos en seed.");
      }
      sectionOffsets.add(offset);
      expectedOffset += length;
    }
    if (expectedOffset + _digestBytes != bytes.length) {
      throw const FormatException("Longitud total inválida en seed peatonal.");
    }
    final digest = sha256.convert(bytes.sublist(0, expectedOffset)).bytes;
    for (var i = 0; i < _digestBytes; i++) {
      if (bytes[expectedOffset + i] != digest[i]) {
        throw const FormatException("Checksum inválido en seed peatonal.");
      }
    }
    final sourceDate = ascii.decode(bytes.sublist(8, 14));
    final sourceSha256 = _encodeHex(bytes.sublist(14, 46));
    final bounds = _readInt32s(bytes, 46, 4);
    final data = WalkGraphSeedData(
      vertexCoordinates: _readInt32s(bytes, sectionOffsets[0], vertexCount * 2),
      edgeEndpoints: _readInt32s(bytes, sectionOffsets[1], edgeCount * 2),
      edgeLengthsMeters: _readFloat32s(bytes, sectionOffsets[2], edgeCount),
      edgeGeometryOffsets: _readInt32s(bytes, sectionOffsets[3], edgeCount + 1),
      edgeGeometryCoordinates: _readInt32s(
        bytes,
        sectionOffsets[4],
        pointCount * 2,
      ),
      adjacencyOffsets: _readInt32s(bytes, sectionOffsets[5], vertexCount + 1),
      adjacencyEdgeIds: _readInt32s(bytes, sectionOffsets[6], edgeCount * 2),
      sourceDate: sourceDate,
      sourceSha256: sourceSha256,
      boundsMicrodegrees: bounds,
      wayCount: wayCount,
    );
    _validateData(data);
    return data;
  }

  static void _validateData(WalkGraphSeedData data) {
    if (data.sourceDate.length != 6 ||
        !RegExp(r"^\d{6}$").hasMatch(data.sourceDate)) {
      throw const FormatException("Fecha de extracto inválida.");
    }
    if (!RegExp(r"^[0-9a-f]{64}$").hasMatch(data.sourceSha256)) {
      throw const FormatException("SHA-256 del extracto inválido.");
    }
    if (data.boundsMicrodegrees.length != 4 ||
        data.vertexCoordinates.length.isOdd ||
        data.edgeEndpoints.length != data.edgeCount * 2 ||
        data.edgeGeometryOffsets.length != data.edgeCount + 1 ||
        data.edgeGeometryCoordinates.length.isOdd ||
        data.adjacencyOffsets.length != data.vertexCount + 1 ||
        data.adjacencyEdgeIds.length != data.edgeCount * 2 ||
        data.vertexCount == 0) {
      throw const FormatException("Conteos inconsistentes en seed peatonal.");
    }
    if (data.edgeGeometryOffsets.first != 0 ||
        data.edgeGeometryOffsets.last != data.geometryPointCount ||
        data.adjacencyOffsets.first != 0 ||
        data.adjacencyOffsets.last != data.adjacencyEdgeIds.length) {
      throw const FormatException("Offsets finales inconsistentes en seed.");
    }
    for (var i = 0; i < data.edgeCount; i++) {
      final a = data.edgeEndpoints[i * 2];
      final b = data.edgeEndpoints[i * 2 + 1];
      if (a < 0 ||
          a >= data.vertexCount ||
          b < 0 ||
          b >= data.vertexCount ||
          data.edgeGeometryOffsets[i] >= data.edgeGeometryOffsets[i + 1] ||
          data.edgeGeometryOffsets[i + 1] - data.edgeGeometryOffsets[i] < 2 ||
          !data.edgeLengthsMeters[i].isFinite ||
          data.edgeLengthsMeters[i] <= 0) {
        throw const FormatException("Arista inválida en seed peatonal.");
      }
    }
    for (var i = 0; i < data.vertexCount; i++) {
      if (data.adjacencyOffsets[i] > data.adjacencyOffsets[i + 1]) {
        throw const FormatException("Adyacencia CSR inválida.");
      }
    }
    for (final edgeId in data.adjacencyEdgeIds) {
      if (edgeId < 0 || edgeId >= data.edgeCount) {
        throw const FormatException("ID de arista inválido en CSR.");
      }
    }
  }

  static Uint8List _encodeInt32s(Int32List values) {
    final bytes = Uint8List(values.length * 4);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < values.length; i++) {
      data.setInt32(i * 4, values[i], Endian.little);
    }
    return bytes;
  }

  static Uint8List _encodeFloat32s(Float32List values) {
    final bytes = Uint8List(values.length * 4);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < values.length; i++) {
      data.setFloat32(i * 4, values[i], Endian.little);
    }
    return bytes;
  }

  static Int32List _readInt32s(Uint8List bytes, int offset, int count) {
    final data = ByteData.sublistView(bytes);
    final values = Int32List(count);
    for (var i = 0; i < count; i++) {
      values[i] = data.getInt32(offset + i * 4, Endian.little);
    }
    return values;
  }

  static Float32List _readFloat32s(Uint8List bytes, int offset, int count) {
    final data = ByteData.sublistView(bytes);
    final values = Float32List(count);
    for (var i = 0; i < count; i++) {
      values[i] = data.getFloat32(offset + i * 4, Endian.little);
    }
    return values;
  }

  static Uint8List _decodeHex(String value) {
    final bytes = Uint8List(value.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static String _encodeHex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, "0")).join();
}
