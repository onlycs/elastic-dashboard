import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:dot_cast/dot_cast.dart';

class DynStructField {
  final String name;
  final String type;
  final bool isArray;
  final bool isNullable;

  final DynStructSchema? substruct;

  DynStructField({
    required this.name,
    required this.type,
    this.isArray = false,
    this.isNullable = false,
    this.substruct,
  });

  static DynStructField fromJson(
    Map<String, dynamic> json,
  ) {
    return DynStructField(
      name: json['name'],
      type: json['type'],
      isArray: json['isArray'],
      isNullable: json['isNullable'],
      substruct: json['substruct'] != null
          ? DynStructSchema.fromJson(tryCast(json['substruct']) ?? {})
          : null,
    );
  }

  static DynStructField _parseField(
      String name, String type, Map<String, String> schemas) {
    if (type == "boolean") {
      return DynStructField(name: name, type: type);
    } else if (type == "int") {
      return DynStructField(name: name, type: type);
    } else if (type == "long") {
      return DynStructField(name: name, type: type);
    } else if (type == "float") {
      return DynStructField(name: name, type: type);
    } else if (type == "double") {
      return DynStructField(name: name, type: type);
    } else if (type.endsWith("?")) {
      String subtype = type.substring(0, type.length - 1);
      return DynStructField(
        name: name,
        type: subtype,
        isNullable: true,
      );
    } else if (type.endsWith("[]")) {
      String subtype = type.substring(0, type.length - 2);
      return DynStructField(
        name: name,
        type: subtype,
        isArray: true,
      );
    } else if (type == "string") {
      return DynStructField(name: name, type: "string");
    } else if (schemas.containsKey('struct:$type')) {
      return DynStructField(
        name: name,
        type: type,
        substruct: DynStructSchema(
          type: 'struct:$type',
          schemas: schemas,
        ),
      );
    } else {
      throw Exception("Unknown type: $type");
    }
  }

  DynStructField clone() {
    return DynStructField(
      name: name,
      type: type,
      isArray: isArray,
      isNullable: isNullable,
      substruct: substruct?.clone(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'isArray': isArray,
      'isNullable': isNullable,
      'substruct': substruct?.toJson(),
    };
  }
}

class DynStructSchema {
  final String type;
  final List<DynStructField> fields;

  DynStructSchema({
    required this.type,
    required Map<String, String> schemas,
  }) : fields = _tryParseSchema(type, schemas);

  DynStructSchema.raw({
    required this.type,
    required this.fields,
  });

  DynStructField? operator [](String key) {
    for (final field in fields) {
      if (field.name == key) {
        return field;
      }
    }

    return null;
  }

  static List<DynStructField> _tryParseSchema(
      String name, Map<String, String> schemas) {
    try {
      return _parseSchema(name, schemas);
    } catch (_e) {
      return [];
    }
  }

  static List<DynStructField> _parseSchema(
      String name, Map<String, String> schemas) {
    List<DynStructField> fields = [];
    List<String>? schemaParts = schemas[name]?.split(';');

    if (schemaParts == null) {
      throw Exception("Schema not found: $name");
    }

    for (final String part in schemaParts) {
      var [type, name] = part.split(' ');
      var field = DynStructField._parseField(name, type, schemas);
      fields.add(field);
    }

    return fields;
  }

  @override
  String toString() {
    return fields.map((field) => "${field.name}: ${field.type}").join(", ");
  }

  DynStructSchema clone() {
    return DynStructSchema.raw(
      type: type,
      fields: fields.map((field) => field.clone()).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'fields': fields.map((field) => field.toJson()).toList(),
    };
  }

  static DynStructSchema fromJson(Map<String, dynamic> json) {
    return DynStructSchema.raw(
      type: json['type'],
      fields: (tryCast<List<dynamic>>(json['fields']) ?? [])
          .map((field) => DynStructField.fromJson(tryCast(field) ?? {}))
          .toList(),
    );
  }
}

sealed class DynStructValue {
  final Object? anyValue;

  DynStructValue({required this.anyValue});

  bool get boolValue => (this as DynStructBoolean).value;
  int get intValue => (this as DynStructInt).value;
  int get longValue => (this as DynStructLong).value;
  double get floatValue => (this as DynStructFloat).value;
  double get doubleValue => (this as DynStructDouble).value;
  String get stringValue => (this as DynStructString).value;
  DynStructValue? get nullableValue => (this as DynStructNullable).value;
  List<DynStructValue> get arrayValue => (this as DynStructArray).value;
  DynStruct get structValue => (this as DynStructStruct).value;
}

class DynStructBoolean extends DynStructValue {
  final bool value;

  DynStructBoolean(this.value) : super(anyValue: value);
}

class DynStructInt extends DynStructValue {
  final int value;

  DynStructInt(this.value) : super(anyValue: value);
}

class DynStructLong extends DynStructValue {
  final int value;

  DynStructLong(this.value) : super(anyValue: value);
}

class DynStructFloat extends DynStructValue {
  final double value;

  DynStructFloat(this.value) : super(anyValue: value);
}

class DynStructDouble extends DynStructValue {
  final double value;

  DynStructDouble(this.value) : super(anyValue: value);
}

class DynStructString extends DynStructValue {
  final String value;

  DynStructString(this.value) : super(anyValue: value);
}

class DynStructNullable extends DynStructValue {
  final DynStructValue? value;

  DynStructNullable(this.value) : super(anyValue: value);
}

class DynStructArray extends DynStructValue {
  final List<DynStructValue> value;

  DynStructArray(this.value) : super(anyValue: value);
}

class DynStructStruct extends DynStructValue {
  final DynStruct value;

  DynStructStruct(this.value) : super(anyValue: value);
}

class DynStruct {
  final DynStructSchema schema;
  late final Map<String, DynStructValue> values;
  late final int consumed;

  DynStruct({
    required this.schema,
    required Uint8List data,
  }) {
    var (consumed, values) = _parseData(schema, data);
    this.values = values;
    this.consumed = consumed;
  }

  DynStructValue? operator [](String key) {
    return values[key];
  }

  DynStructValue? get(List<String> key) {
    DynStructValue value = DynStructStruct(this);

    for (final k in key) {
      if (value is DynStructStruct) {
        value = value.structValue[k]!;
      } else {
        return null;
      }
    }

    return value;
  }

  static (int, Map<String, DynStructValue>) _parseData(
      DynStructSchema schema, Uint8List data) {
    Map<String, DynStructValue> values = {};
    int offset = 0;

    for (final field in schema.fields) {
      var (consumed, value) = _parseValue(field, data.sublist(offset));
      values[field.name] = value;
      offset += consumed;
    }

    return (offset, values);
  }

  static (int, DynStructValue) _parseValue(
      DynStructField field, Uint8List data) {
    if (field.isArray) {
      int length = data.buffer.asByteData().getInt32(0, Endian.little);
      var (consumed, value) = _parseArray(field, data.sublist(4), length);
      return (consumed + 4, value);
    } else if (field.isNullable) {
      bool isNull = data[0] != 0;
      if (isNull) {
        return (1, DynStructNullable(null));
      } else {
        var (consumed, value) = _parseValueInner(field, data.sublist(1));
        return (consumed + 1, DynStructNullable(value));
      }
    } else {
      return _parseValueInner(field, data);
    }
  }

  static (int, DynStructValue) _parseValueInner(
      DynStructField field, Uint8List data) {
    if (field.type == "boolean") {
      return (1, DynStructBoolean(data[0] != 0));
    } else if (field.type == "int") {
      return (
        4,
        DynStructInt(data.buffer.asByteData().getInt32(0, Endian.little))
      );
    } else if (field.type == "long") {
      return (
        8,
        DynStructLong(data.buffer.asByteData().getInt64(0, Endian.little))
      );
    } else if (field.type == "float") {
      return (
        4,
        DynStructFloat(data.buffer.asByteData().getFloat32(0, Endian.little))
      );
    } else if (field.type == "double") {
      return (
        8,
        DynStructDouble(data.buffer.asByteData().getFloat64(0, Endian.little))
      );
    } else if (field.type == "string") {
      int length = data.buffer.asByteData().getInt32(0, Endian.little);
      return (
        length + 4,
        DynStructString(String.fromCharCodes(data.sublist(4, 4 + length)))
      );
    } else if (field.substruct != null) {
      DynStruct sub = DynStruct(
        schema: field.substruct!,
        data: data,
      );

      return (sub.consumed, DynStructStruct(sub));
    } else {
      throw Exception("Unknown type: ${field.type}");
    }
  }

  static (int, DynStructArray) _parseArray(
      DynStructField field, Uint8List data, int length) {
    List<DynStructValue> values = [];
    int offset = 0;

    for (int i = 0; i < length; i++) {
      var (consumed, value) = _parseValueInner(field, data.sublist(offset));
      values.add(value);
      offset += consumed;
    }

    return (offset, DynStructArray(values));
  }
}
