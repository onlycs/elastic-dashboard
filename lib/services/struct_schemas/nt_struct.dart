import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:dot_cast/dot_cast.dart';

import 'package:elastic_dashboard/services/log.dart';
import 'package:elastic_dashboard/services/nt4_type.dart';

extension on Uint8List {
  List<bool> toBitArray() {
    List<bool> output = [];

    for (int value in this) {
      for (int shift = 0; shift < 8; shift++) {
        output.add(((1 << shift) & value) > 0);
      }
    }

    return output;
  }
}

extension on List<bool> {
  Uint8List toUint8List() {
    Uint8List output = Uint8List((length / 8).ceil());

    for (int i = 0; i < length; i++) {
      if (this[i]) {
        int byte = (i / 8).floor();
        int bit = i % 8;
        output[byte] |= 1 << bit;
      }
    }

    return output;
  }
}

/// This class is a singleton that manages the schemas of NTStructs.
/// It allows adding new schemas and retrieving existing ones by name.
/// It also provides a method to parse a schema string into a list of field schemas.
class SchemaManager {
  static final SchemaManager _instance = SchemaManager._internal();
  SchemaManager._internal();

  factory SchemaManager.getInstance() {
    return _instance;
  }

  final Map<String, String> _uncompiledSchemas = {};
  final Map<String, NTStructSchema> _schemas = {};

  NTStructSchema? getSchema(String name) {
    if (name.contains(':')) {
      name = name.split(':')[1];
    }

    return _schemas[name];
  }

  void processNewSchema(String name, List<int> rawData) {
    String schema = utf8.decode(rawData);
    if (name.contains(':')) {
      name = name.split(':').last;
    }

    _uncompiledSchemas[name] = schema;

    while (_uncompiledSchemas.isNotEmpty) {
      bool compiled = false;

      List<String> newlyCompiled = [];

      for (final uncompiled in _uncompiledSchemas.entries) {
        if (!_schemas.containsKey(uncompiled.key)) {
          bool success = addStringSchema(uncompiled.key, uncompiled.value);
          if (success) {
            newlyCompiled.add(uncompiled.key);
          }
          compiled = compiled || success;
        }
      }

      _uncompiledSchemas.removeWhere((k, v) => newlyCompiled.contains(k));

      if (!compiled) {
        break;
      }
    }
  }

  void addSchema(String name, NTStructSchema schema) {
    if (name.contains(':')) {
      name = name.split(':')[1];
    }

    if (_schemas.containsKey(name)) {
      return;
    }

    logger.debug(
      'Adding schema: $name, $schema',
    );

    _schemas[name] = schema;
  }

  bool addStringSchema(String name, String schema) {
    if (name.contains(':')) {
      name = name.split(':')[1];
    }
    name = name.trim();

    if (_schemas.containsKey(name)) {
      return true;
    }

    try {
      NTStructSchema parsedSchema = NTStructSchema(name: name, schema: schema);
      addSchema(name, parsedSchema);
      return true;
    } catch (err) {
      logger.info('Failed to parse schema: $name - $schema');
      return false;
    }
  }

  bool isStruct(String name) {
    name = name.trim();
    if (name.contains(':')) {
      name = name.split(':')[1];
    }

    return _schemas.containsKey(name);
  }
}

enum StructValueType {
  bool('bool', 8),
  char('char', 8),
  int8('int8', 8),
  int16('int16', 16),
  int32('int32', 32),
  int64('int64', 64),
  uint8('uint8', 8),
  uint16('uint16', 16),
  uint32('uint32', 32),
  uint64('uint64', 64),
  float('float', 32),
  float32('float32', 32),
  double('double', 64),
  float64('float64', 64),
  struct('struct', 0);

  const StructValueType(this.name, this.maxBits);

  final String name;
  final int maxBits;

  static StructValueType parse(String type) {
    return StructValueType.values.firstWhereOrNull((e) => e.name == type) ??
        StructValueType.struct;
  }

  NT4Type get ntType => switch (this) {
        StructValueType.bool => NT4Type.boolean(),
        StructValueType.char ||
        StructValueType.int8 ||
        StructValueType.int16 ||
        StructValueType.int32 ||
        StructValueType.int64 ||
        StructValueType.uint8 ||
        StructValueType.uint16 ||
        StructValueType.uint32 ||
        StructValueType.uint64 =>
          NT4Type.int(),
        StructValueType.float ||
        StructValueType.float32 ||
        StructValueType.double ||
        StructValueType.float64 =>
          NT4Type.double(),
        StructValueType.struct => NT4Type.struct(name),
      };

  @override
  String toString() {
    return name;
  }
}

/// This class represents a field schema in an NTStruct.
/// It contains the field name and its type.
/// It also provides a method to get type information for the field if it is a struct.
class NTFieldSchema {
  final String field;
  final String type;
  final int bitLength;
  final int? arrayLength;
  final (int start, int end) bitRange;

  StructValueType get valueType => StructValueType.parse(type);

  NT4Type get ntType => valueType != StructValueType.struct
      ? valueType.ntType
      : NT4Type.struct(type);

  bool get isArray => arrayLength != null;

  NTFieldSchema({
    required this.field,
    required this.type,
    required this.bitLength,
    this.arrayLength,
    required this.bitRange,
  });

  static NTFieldSchema fromJson(
    Map<String, dynamic> json,
  ) {
    return NTFieldSchema(
      field: json['name'] ?? json['field'],
      type: json['type'],
      bitLength: json['bit_length'],
      bitRange: (json['bit_range_start'], json['bit_range_end']),
      arrayLength: json['array_length'],
    );
  }

  int get startByte => (bitRange.$1 / 8).ceil();

  NTStructValue toValue(Uint8List data) {
    final view = data.buffer.asByteData();
    return switch (valueType) {
      StructValueType.bool => NTStructValue.fromBool(view.getUint8(0) > 0),
      StructValueType.char => NTStructValue.fromInt(0),
      StructValueType.int8 => NTStructValue.fromInt(view.getInt8(0)),
      StructValueType.int16 =>
        NTStructValue.fromInt(view.getInt16(0, Endian.little)),
      StructValueType.int32 =>
        NTStructValue.fromInt(view.getInt32(0, Endian.little)),
      StructValueType.int64 =>
        NTStructValue.fromInt(view.getInt64(0, Endian.little)),
      StructValueType.uint8 => NTStructValue.fromInt(view.getUint8(0)),
      StructValueType.uint16 =>
        NTStructValue.fromInt(view.getUint16(0, Endian.little)),
      StructValueType.uint32 =>
        NTStructValue.fromInt(view.getUint32(0, Endian.little)),
      StructValueType.uint64 =>
        NTStructValue.fromInt(view.getUint32(0, Endian.little)),
      StructValueType.float ||
      StructValueType.float32 =>
        NTStructValue.fromDouble(view.getFloat32(0, Endian.little)),
      StructValueType.double ||
      StructValueType.float64 =>
        NTStructValue.fromDouble(view.getFloat64(0, Endian.little)),
      StructValueType.struct => () {
          NTStructSchema? schema = SchemaManager.getInstance().getSchema(type);
          if (schema == null) {
            return NTStructValue.fromNullable(null);
          }
          return NTStructValue.fromStruct(NTStruct(schema: schema, data: data));
        }(),
    };
  }

  static NTFieldSchema _parseField(int start, String definition, String type) {
    StructValueType fieldType = StructValueType.parse(type);
    late String fieldName;
    late (int start, int end) bitRange;
    int? bitLength;
    int? arrayLength;

    if (fieldType == StructValueType.struct) {
      NTStructSchema? schema = SchemaManager.getInstance().getSchema(type);
      if (schema == null) {
        logger.debug('Unknown struct type: $type');
        throw Exception();
      }
      bitLength = schema.bitLength;
    }

    if (definition.contains(':')) {
      var [name, length] = definition.split(':');
      fieldName = name.trim();
      bitLength = int.tryParse(length.trim());
    } else {
      fieldName = definition;
    }

    if (definition.contains('[')) {
      String rawLength = definition.substring(
        definition.indexOf('['),
        definition.indexOf(']'),
      );
      arrayLength = int.parse(rawLength);
      bitLength = (bitLength ?? fieldType.maxBits) * arrayLength;
    }

    bitLength ??= fieldType.maxBits;

    bitRange = (start, start + bitLength);

    return NTFieldSchema(
      field: fieldName,
      type: type,
      bitRange: bitRange,
      arrayLength: arrayLength,
      bitLength: bitLength,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'field': field,
      'type': type,
    };
  }

  NTStructSchema? get substruct => valueType == StructValueType.struct
      ? SchemaManager.getInstance().getSchema(type)
      : null;
}

/// This class represents a schema for an NTStruct.
/// It contains the name of the struct and a list of field schemas.
class NTStructSchema {
  final String name;
  final List<NTFieldSchema> fields;
  late final int bitLength;

  NTStructSchema({
    required this.name,
    required String schema,
  }) : fields = _tryParseSchema(name, schema) {
    int bits = 0;
    for (final field in fields) {
      bits += field.bitLength;
    }
    bitLength = bits;
  }

  NTStructSchema.raw({
    required this.name,
    required this.fields,
  });

  NTFieldSchema? operator [](String key) {
    for (final field in fields) {
      if (field.field == key) {
        return field;
      }
    }

    return null;
  }

  static List<NTFieldSchema> _tryParseSchema(String name, String schema) {
    return _parseSchema(name, schema.replaceAll('\n', ''));
  }

  static List<NTFieldSchema> _parseSchema(String name, String schema) {
    List<NTFieldSchema> fields = [];
    List<String> schemaParts = schema.split(';');

    int bitStart = 0;
    for (final String part in schemaParts.map((e) => e.trim())) {
      if (part.isEmpty) {
        continue;
      }
      var [type, definition] = [
        part.substring(0, part.indexOf(' ')),
        part.substring(part.indexOf(' ') + 1)
      ];
      var field = NTFieldSchema._parseField(bitStart, definition, type);
      bitStart += field.bitLength;
      fields.add(field);
    }

    return fields;
  }

  @override
  String toString() {
    return '$name { ${fields.map((field) => '${field.field}: ${field.type}').join(', ')} }';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'fields': fields.map((field) => field.toJson()).toList(),
    };
  }

  static NTStructSchema fromJson(Map<String, dynamic> json) {
    return NTStructSchema.raw(
      name: json['name'] ?? json['type'],
      fields: (tryCast<List<dynamic>>(json['fields']) ?? [])
          .map((field) => NTFieldSchema.fromJson(tryCast(field) ?? {}))
          .toList(),
    );
  }
}

typedef ArrayValue<T> = List<NTStructValue<T>>;

/// This class represents a value in an NTStruct.
/// It can be of different types, including int, bool, double, string,
/// nullable, array, or another NTStruct.
/// It provides static methods to create instances of NTStructValue
/// for each type.
class NTStructValue<T> {
  final T value;

  static NTStructValue<int> fromInt(int value) => NTStructValue._(value);

  static NTStructValue<bool> fromBool(bool value) => NTStructValue._(value);

  static NTStructValue<double> fromDouble(double value) =>
      NTStructValue._(value);

  static NTStructValue<String> fromString(String value) =>
      NTStructValue._(value);

  static NTStructValue<K?> fromNullable<K>(K? value) => NTStructValue._(value);

  static NTStructValue<ArrayValue<K>> fromArray<K>(ArrayValue<K> value) =>
      NTStructValue._(value);

  static NTStructValue<NTStruct> fromStruct(NTStruct value) =>
      NTStructValue._(value);

  NTStructValue._(this.value);
}

/// This class represents an NTStruct.
/// It contains a schema and a map of values.
/// It provides methods to parse data into NTStructValue instances
/// and to retrieve values by key.
class NTStruct {
  final NTStructSchema schema;
  late final Map<String, NTStructValue> values;

  NTStruct({
    required this.schema,
    required Uint8List data,
  }) {
    var (consumed, values) = _parseData(schema, data);
    this.values = values;
  }

  NTStructValue? operator [](String key) {
    return values[key];
  }

  NTStructValue? get(List<String> key) {
    NTStructValue value = NTStructValue.fromStruct(this);

    for (final k in key) {
      if (value is NTStructValue<NTStruct>) {
        value = value.value[k]!;
      } else {
        return null;
      }
    }

    return value;
  }

  static (int, Map<String, NTStructValue>) _parseData(
    NTStructSchema schema,
    Uint8List data,
  ) {
    List<bool> dataBitArray = data.toBitArray();

    Map<String, NTStructValue> values = {};
    int offset = 0;

    for (final field in schema.fields) {
      final value = field.toValue(dataBitArray
          .slice(field.bitRange.$1, field.bitRange.$2)
          .toUint8List());

      values[field.field] = value;

      // var (consumed, value) = _parseValue(
      //   field,
      //   data.sublist(offset),
      // );
      // values[field.field] = value;
      // offset += consumed;
    }

    return (offset, values);
  }

  // static (int, NTStructValue) _parseValue(
  //   NTFieldSchema field,
  //   Uint8List data,
  // ) {
  //   if (field.isArray) {
  //     var (consumed, value) = _parseArray(field, data, field.arrayLength!);
  //     return (consumed, value);
  //   } else {
  //     return _parseValueInner(field, data);
  //   }
  // }

  // static (int, NTStructValue) _parseValueInner(
  //     NTFieldSchema field, Uint8List data) {
  //   if (field.type.fragment == NT4TypeFragment.boolean) {
  //     return (1, NTStructValue.fromBool(data[0] != 0));
  //   } else if (field.type.fragment == NT4TypeFragment.int32) {
  //     return (
  //       4,
  //       NTStructValue.fromInt(
  //           data.buffer.asByteData().getInt32(0, Endian.little))
  //     );
  //   } else if (field.type.fragment == NT4TypeFragment.float32) {
  //     return (
  //       4,
  //       NTStructValue.fromDouble(
  //           data.buffer.asByteData().getFloat32(0, Endian.little))
  //     );
  //   } else if (field.type.fragment == NT4TypeFragment.float64) {
  //     return (
  //       8,
  //       NTStructValue.fromDouble(
  //           data.buffer.asByteData().getFloat64(0, Endian.little))
  //     );
  //   } else if (field.type.fragment == NT4TypeFragment.string) {
  //     int length = data.buffer.asByteData().getInt32(0, Endian.little);
  //     return (
  //       length + 4,
  //       NTStructValue.fromString(
  //           String.fromCharCodes(data.sublist(4, 4 + length)))
  //     );
  //   } else if (field.type.isStruct) {
  //     NTStructSchema? substruct = field.substruct;

  //     if (substruct == null) {
  //       throw Exception('No schema found for struct: ${field.type.name}');
  //     }

  //     NTStruct sub = NTStruct(
  //       schema: substruct,
  //       data: data,
  //     );

  //     return (sub.consumed, NTStructValue.fromStruct(sub));
  //   } else {
  //     throw Exception('Unknown type: ${field.type}');
  //   }
  // }

  // static (int, NTStructValue<List<NTStructValue>>) _parseArray(
  //     NTFieldSchema field, Uint8List data, int length) {
  //   List<NTStructValue> values = [];
  //   int offset = 0;

  //   for (int i = 0; i < length; i++) {
  //     var (consumed, value) = _parseValueInner(field, data.sublist(offset));
  //     values.add(value);
  //     offset += consumed;
  //   }

  //   return (offset, NTStructValue.fromArray(values));
  // }
}
