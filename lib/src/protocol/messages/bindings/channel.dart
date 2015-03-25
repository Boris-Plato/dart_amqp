// The file contains all method messages for AMQP class Channel (id: 20)
//
// File was auto-generated by generate_bindings.dart at 2015-03-25 16:48:25.919
//
// Do not modify

part of dart_amqp.protocol;

class ChannelOpen implements Message {
  final bool msgHasContent = false;
  final int msgClassId = 20;
  final int msgMethodId = 10;

  // Message arguments
  String reserved_1;

  ChannelOpen();

  void serialize( TypeEncoder encoder ) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
      ..writeShortString(reserved_1)
    ;
  }
}

class ChannelOpenOk implements Message {
  final bool msgHasContent = false;
  final int msgClassId = 20;
  final int msgMethodId = 11;

  // Message arguments
  String reserved_1;

  ChannelOpenOk.fromStream( TypeDecoder decoder ){
    reserved_1 = decoder.readLongString();
 }}

class ChannelFlow implements Message {
  final bool msgHasContent = false;
  final int msgClassId = 20;
  final int msgMethodId = 20;

  // Message arguments
  bool active;

  ChannelFlow();
  ChannelFlow.fromStream( TypeDecoder decoder ){
    int _bitmask;
    _bitmask = decoder.readUInt8();
    active = _bitmask & 0x1 != 0;
 }
  void serialize( TypeEncoder encoder ) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
      ..writeBits([active])
    ;
  }
}

class ChannelFlowOk implements Message {
  final bool msgHasContent = false;
  final int msgClassId = 20;
  final int msgMethodId = 21;

  // Message arguments
  bool active;

  ChannelFlowOk();
  ChannelFlowOk.fromStream( TypeDecoder decoder ){
    int _bitmask;
    _bitmask = decoder.readUInt8();
    active = _bitmask & 0x1 != 0;
 }
  void serialize( TypeEncoder encoder ) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
      ..writeBits([active])
    ;
  }
}

class ChannelClose implements Message {
  final bool msgHasContent = false;
  final int msgClassId = 20;
  final int msgMethodId = 40;

  // Message arguments
  int replyCode;
  String replyText;
  int classId;
  int methodId;

  ChannelClose();
  ChannelClose.fromStream( TypeDecoder decoder ){
    replyCode = decoder.readUInt16();
    replyText = decoder.readShortString();
    classId = decoder.readUInt16();
    methodId = decoder.readUInt16();
 }
  void serialize( TypeEncoder encoder ) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
      ..writeUInt16(replyCode)
      ..writeShortString(replyText)
      ..writeUInt16(classId)
      ..writeUInt16(methodId)
    ;
  }
}

class ChannelCloseOk implements Message {
  final bool msgHasContent = false;
  final int msgClassId = 20;
  final int msgMethodId = 41;

  // Message arguments

  ChannelCloseOk();
  ChannelCloseOk.fromStream( TypeDecoder decoder ){
 }
  void serialize( TypeEncoder encoder ) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
    ;
  }
}
