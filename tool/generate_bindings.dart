import "dart:io";
import "dart:async";
import "package:xml/xml.dart" as xml;
import "package:http/http.dart" as http;
import "package:logging/logging.dart";

final Logger logger = Logger("tools");

class AmqpBindingsBuilder {
  // The following list of messages will be excluded from
  // the generated bindings
  List<String> excludedMessages = const [
    "BasicGet",
    "BasicGetOk",
    "BasicGetEmpty",
    "BasicRecoverAsync"
  ];

  StringBuffer generatedMessageFactoryFile = StringBuffer("""
// The file contains the base class for AMQP method messages
// and a factory constructor for unserializing AMQP messages
// from incoming frames
//
// File was auto-generated by generate_bindings.dart at ${DateTime.now()}
//
// Do not modify

part of dart_amqp.protocol;

abstract class Message {

  int get msgClassId;

  int get msgMethodId;

  bool get msgHasContent;

  void serialize(TypeEncoder encoder);

  factory Message.fromStream(TypeDecoder decoder){
    int msgClassId = decoder.readUInt16();
    int msgMethodId = decoder.readUInt16();

    switch( msgClassId ){
""");

  StringBuffer generatedMessageFactoryFooter = StringBuffer(r"""
    }

    // Message decoding failed; unknown message
    throw ArgumentError("Unknown message type (class: ${msgClassId}, method: ${msgMethodId})");
  }
}
""");

  StringBuffer generatedLibraryFile = StringBuffer("""
// The file contains AMQP binding imports
//
// File was auto-generated by generate_bindings.dart at ${DateTime.now()}
//
// Do not modify

library dart_amqp.protocol;

import "dart:async";
import "dart:convert";
import "dart:typed_data";
import "dart:collection";
import "dart:math" as math;

// Internal lib dependencies
import "enums.dart";
import "exceptions.dart";

// Stream reader/writers
part "protocol/stream/chunked_input_reader.dart";
part "protocol/stream/chunked_output_writer.dart";
part "protocol/stream/type_decoder.dart";
part "protocol/stream/type_encoder.dart";

// Message interface
part "protocol/messages/message.dart";
part "protocol/messages/message_properties.dart";

// Frame headers
part "protocol/headers/header.dart";
part "protocol/headers/protocol_header.dart";
part "protocol/headers/frame_header.dart";
part "protocol/headers/content_header.dart";

// Writers
part "protocol/io/frame_writer.dart";
part "protocol/io/tuning_settings.dart";

// Frame interfaces and implementations
part "protocol/frame/raw_frame.dart";
part "protocol/frame/impl/heartbeat_frame_impl.dart";
part "protocol/frame/decoded_message.dart";
part "protocol/frame/impl/decoded_message_impl.dart";

// Readers
part "protocol/io/raw_frame_parser.dart";
part "protocol/io/amqp_message_decoder.dart";

// Autogenerated class bindings
""");

  Map<String, String> _amqpTypeToDartType = {
    "bit": "bool",
    "octet": "int",
    "short": "int",
    "long": "int",
    "longlong": "int",
    "shortstr": "String",
    "longstr": "String",
    "timestamp": "DateTime",
    "table": "Map<String, Object>"
  };
  Map<String, String> _amqpCustomTypeToBasicType = {};

  Future<xml.XmlDocument> _retrieveSchema(String schemaUrl) async {
    logger.info("- Retrieving schema from ${schemaUrl}");

    // Check for cached copy
    File cachedCopy = File(schemaUrl.split('/').last);
    bool exists = await cachedCopy.exists();
    String data =
        exists ? await cachedCopy.readAsString() : await http.read(schemaUrl);
    logger.info("- Parsing schema");
    return xml.parse(data);
  }

  String _parseMethod(
      String className, int classId, xml.XmlElement amqpMethod) {
    // Convert dashed field name to class case
    String methodName = amqpMethod
        .getAttribute("name")
        .replaceAllMapped(RegExp(r"^([a-z])"), (Match m) {
      return m.group(1).toUpperCase();
    }).replaceAllMapped(RegExp(r"-([a-z])"), (Match m) {
      return m.group(1).toUpperCase();
    });

    // Check if method message should have a body
    String hasContentAttr = amqpMethod.getAttribute("content");
    bool hasContent = hasContentAttr != null && hasContentAttr == "1";

    // Extract clmethod id
    int methodId = int.parse(amqpMethod.getAttribute("index"), radix: 10);

    bool implementedByClient = amqpMethod
        .findAllElements("chassis")
        .any((xml.XmlElement elem) => elem.getAttribute("name") == "client");

    bool implementedByServer = amqpMethod
        .findAllElements("chassis")
        .any((xml.XmlElement elem) => elem.getAttribute("name") == "server");

    // Update message factory
    if (implementedByClient) {
      generatedMessageFactoryFile.write("""
          case $methodId:
            return ${className}${methodName}.fromStream(decoder);
""");
    }

    logger.fine("    Method: ${methodName} (id: ${methodId})");

    // Generate class
    StringBuffer generatedClass = StringBuffer("""
class ${className}${methodName} implements Message {
  final bool msgHasContent = ${hasContent};
  final int msgClassId = ${classId};
  final int msgMethodId = ${methodId};

  // Message arguments
""");
    StringBuffer serializerMethod = StringBuffer("""
  void serialize(TypeEncoder encoder) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
""");
    StringBuffer ctors =
        StringBuffer((implementedByServer || !implementedByClient)
            ? """
  ${className}${methodName}();
"""
            : "");
    if (implementedByClient) {
      ctors.write("""
  ${className}${methodName}.fromStream(TypeDecoder decoder) {
""");
    }
    StringBuffer toStringMethod = StringBuffer("""
  String toString(){
    return \"\"\"
${className}.${methodName}
${String.fromCharCodes(List<int>.filled(className.length + methodName.length + 1, "-".codeUnitAt(0)))}
""");

    bool emittingBits = false;
    bool declaredBitVar = false;
    int bitOffset = 0;

    // Parse fields
    amqpMethod.descendants
        .where((xml.XmlNode node) =>
            node is xml.XmlElement && node.name.local == "field")
        .forEach((xml.XmlNode node) {
      xml.XmlElement amqpMethodField = node as xml.XmlElement;

      // Convert dashed field name to camelCase
      String fieldName = amqpMethodField
          .getAttribute("name")
          .replaceAllMapped(RegExp(r"-([a-z])"), (Match m) {
        return m.group(1).toUpperCase();
      }).replaceAll("-", "_");

      // Retrieve Dart type for field domain
      String fieldDomain = amqpMethodField.getAttribute("domain") ??
          amqpMethodField.getAttribute("type");
      String amqpType = _amqpCustomTypeToBasicType.containsKey(fieldDomain)
          ? _amqpCustomTypeToBasicType[fieldDomain]
          : fieldDomain;
      String dartType = _amqpTypeToDartType[amqpType];

      logger.fine("      Field: ${fieldName} (=> ${dartType})");

      generatedClass.write("  ${dartType} ${fieldName};\n");

      String encoderFunc = "";
      switch (amqpType) {
        case "bit":
          encoderFunc = "writeBits";
          break;
        case "octet":
          encoderFunc = "writeUInt8";
          break;
        case "short":
          encoderFunc = "writeUInt16";
          break;
        case "long":
          encoderFunc = "writeUInt32";
          break;
        case "longlong":
          encoderFunc = "writeUInt64";
          break;
        case "shortstr":
          encoderFunc = "writeShortString";
          break;
        case "longstr":
          encoderFunc = "writeLongString";
          break;
        case "timestamp":
          encoderFunc = "writeTimestamp";
          break;
        case "table":
          encoderFunc = "writeFieldTable";
          break;
        default:
          throw ArgumentError(
              "Not sure how to encode amqp type ${amqpType} for field ${fieldName} (field domain: ${fieldDomain})");
      }

      if (amqpType == "bit") {
        // If not emitting bits, start a block
        if (!emittingBits) {
          serializerMethod.write("      ..${encoderFunc}([${fieldName}");
          emittingBits = true;

          // Declare a temp var for parsing bitmasks in c-tor and reset bit offset
          if (!declaredBitVar && implementedByClient) {
            ctors.write("""
    int _bitmask;
""");
            declaredBitVar = true;
          }
          if (implementedByClient) {
            ctors.write("""
    _bitmask = decoder.readUInt8();
""");
          }

          // Unserialize field value from read _bitmask
          bitOffset = 0;
          if (implementedByClient) {
            ctors.write(
                "    ${fieldName} = _bitmask & 0x${(1 << bitOffset).toRadixString(16)} != 0;\n");
          }
          bitOffset++;
        } else {
          serializerMethod.write(", ${fieldName}");

          // Unserialize field value from read _bitmask
          if (implementedByClient) {
            ctors.write(
                "    ${fieldName} = _bitmask & 0x${(1 << bitOffset).toRadixString(16)} != 0;\n");
          }
          bitOffset++;
        }
      } else {
        // If was emitting bits, flush the block
        if (emittingBits) {
          serializerMethod.write("])\n");
          emittingBits = false;
        }
        serializerMethod.write("      ..${encoderFunc}(${fieldName})\n");

        if (implementedByClient) {
          ctors.write(
              "    ${fieldName} = decoder.${encoderFunc.replaceAll("write", "read")}(${amqpType == "table" ? '"${fieldName}"' : ""});\n");
        }
      }

      // Emit to string part
      toStringMethod.write(
          "${fieldName} : \${${amqpType == "table" ? "indentingJsonEncoder.convert($fieldName)" : fieldName}}\n");
    });

    // If was emitting bits, flush the block
    if (emittingBits) {
      serializerMethod.write("])\n");
    }

    // Finish toString block
    toStringMethod.write("\"\"\";\n  }\n");

    // Finish c-tor block
    if (implementedByClient) {
      ctors.write("  }");
    }

    // End casacade
    serializerMethod..write("    ;\n")..write("  }\n");

    generatedClass..write("\n")..write(ctors);

    if (implementedByServer || !implementedByClient) {
      generatedClass..write("\n")..write(serializerMethod);
    } else {
      // Write an empty serializer stub to avoid warnings
      generatedClass..write("\n\n")..write("""
  void serialize(TypeEncoder encoder) {}
""");
    }
//      ..write("\n")
//      ..write(toStringMethod)
    generatedClass.write("}\n");

    return generatedClass.toString();
  }

  void _parseClass(xml.XmlElement amqpClass) {
    // Convert dashed field name to class case
    String className = amqpClass
        .getAttribute("name")
        .replaceAllMapped(RegExp(r"^([a-z])"), (Match m) {
      return m.group(1).toUpperCase();
    }).replaceAllMapped(RegExp(r"-([a-z])"), (Match m) {
      return m.group(1).toUpperCase();
    });

    // Extract class id
    int classId = int.parse(amqpClass.getAttribute("index"), radix: 10);

    logger.fine("  Class: ${className} (id: ${classId})");

    // Update message factory for the new class
    generatedMessageFactoryFile.write("""
      case ${classId}: // Class: ${className}
        switch (msgMethodId) {
""");

    // Begin generation of method classes for this message class
    StringBuffer generatedMethodsFile = StringBuffer("""
// The file contains all method messages for AMQP class ${className} (id: ${classId})
//
// File was auto-generated by generate_bindings.dart at ${DateTime.now()}
//
// Do not modify

// ignore_for_file: empty_constructor_bodies

part of dart_amqp.protocol;
""");

    // Fetch methods
    amqpClass.descendants
        .where((xml.XmlNode node) =>
            node is xml.XmlElement && node.name.local == "method")
        .where((xml.XmlNode elemNode) {
      xml.XmlElement node = elemNode as xml.XmlElement;

      // Apply method exclusion list
      String methodName = node
          .getAttribute("name")
          .replaceAllMapped(RegExp(r"^([a-z])"), (Match m) {
        return m.group(1).toUpperCase();
      }).replaceAllMapped(RegExp(r"-([a-z])"), (Match m) {
        return m.group(1).toUpperCase();
      });

      String fullClassName = "${className}${methodName}";
      return !excludedMessages.contains(fullClassName);
    }).forEach((xml.XmlNode elemNode) {
      xml.XmlElement node = elemNode as xml.XmlElement;

      generatedMethodsFile
        ..write("\n")
        ..write(_parseMethod(className, classId, node));
    });

    //logger.fine(generatedFile.toString());

    // Write method class file file
    File methodFile = File(
        "../lib/src/protocol/messages/bindings/${className.toLowerCase()}.dart");
    methodFile.writeAsStringSync(generatedMethodsFile.toString());

    // Update message factory
    generatedMessageFactoryFile.write("""
        }
      break;
""");
  }

  void _parseDomain(xml.XmlElement amqpDomain) {
    // If this is an unknown domain but has an alias to a known type add it to the list
    String name = amqpDomain.getAttribute("name");
    String type = amqpDomain.getAttribute("type");

    // Already there
    if (_amqpTypeToDartType.containsKey(name) ||
        _amqpCustomTypeToBasicType.containsKey(name)) {
      return;
    }

    // We can map the domain type to an existing amqp type
    if (_amqpTypeToDartType.containsKey(type)) {
      _amqpCustomTypeToBasicType[name] = type;
      return;
    }

    throw Exception(
        "Could not map domain ${name} of type ${type} to a known Dart type");
  }

  void _parseSchema(xml.XmlDocument schema) {
    logger.info("- Processing custom domains");
    schema.descendants
        .whereType<xml.XmlElement>()
        .where((xml.XmlElement node) => node.name.local == "domain")
        .forEach(_parseDomain);

    logger.info("- Processing amqp classes");
    schema.descendants
        .where((xml.XmlNode node) =>
            node is xml.XmlElement && node.name.local == "class")
        .forEach((xml.XmlNode elemNode) {
      xml.XmlElement amqpClassElement = elemNode as xml.XmlElement;

      String className = amqpClassElement.getAttribute("name").toLowerCase();
      generatedLibraryFile
          .write("part \"protocol/messages/bindings/${className}.dart\";\n");
      _parseClass(amqpClassElement);
    });

    // Write output files
    File libFile = File("../lib/src/protocol.dart");
    libFile.writeAsStringSync(generatedLibraryFile.toString());

    File messageFile = File("../lib/src/protocol/messages/message.dart");
    generatedMessageFactoryFile.write(generatedMessageFactoryFooter);
    messageFile.writeAsStringSync(generatedMessageFactoryFile.toString());
  }

  void build(String schemaUrl) async {
    _parseSchema(await _retrieveSchema(schemaUrl));
  }
}

main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print("${rec.level.name}: ${rec.time}: ${rec.message}");
  });

  logger.info("Building amqp bindings");

  AmqpBindingsBuilder()
      .build("https://www.rabbitmq.com/resources/specs/amqp0-9-1.xml");
}
