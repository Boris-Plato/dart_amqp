library dart_amqp.test.exceptions;

import "dart:async";
import "dart:typed_data";

import "../packages/unittest/unittest.dart";
import "../packages/mock/mock.dart";
import "../packages/stack_trace/stack_trace.dart";

import "../../lib/src/client.dart";
import "../../lib/src/enums.dart";
import "../../lib/src/protocol.dart";
import "../../lib/src/exceptions.dart";

import "mocks/mocks.dart" as mock;

class ConnectionStartMock extends Mock implements ConnectionStart {
  final bool msgHasContent = false;
  final int msgClassId = 10;
  final int msgMethodId = 10;

  // Message arguments
  int versionMajor;
  int versionMinor;
  Map<String, Object> serverProperties;
  String mechanisms;
  String locales;

  void serialize(TypeEncoder encoder) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
      ..writeUInt8(versionMajor)
      ..writeUInt8(versionMinor)
      ..writeFieldTable(serverProperties)
      ..writeLongString(mechanisms)
      ..writeLongString(locales)
    ;
  }
}

class ConnectionTuneMock extends Mock implements ConnectionTune {
  final bool msgHasContent = false;
  final int msgClassId = 10;
  final int msgMethodId = 30;

  // Message arguments
  int channelMax;
  int frameMax;
  int heartbeat;

  void serialize(TypeEncoder encoder) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
      ..writeUInt16(channelMax)
      ..writeUInt32(frameMax)
      ..writeUInt16(heartbeat)
    ;
  }
}

class ConnectionOpenOkMock extends Mock implements ConnectionOpenOk {
  final bool msgHasContent = false;
  final int msgClassId = 10;
  final int msgMethodId = 41;

  void serialize(TypeEncoder encoder) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
      ..writeShortString(reserved_1)
    ;
  }
}

class TxSelectOkMock extends Mock implements TxSelectOk {
  final bool msgHasContent = false;
  final int msgClassId = 90;
  final int msgMethodId = 11;

  void serialize(TypeEncoder encoder) {
    encoder
      ..writeUInt16(msgClassId)
      ..writeUInt16(msgMethodId)
    ;
  }
}

void generateHandshakeMessages(FrameWriter frameWriter, mock.MockServer server) {
  // Connection start
  frameWriter.writeMessage(0, new ConnectionStartMock()
    ..versionMajor = 0
    ..versionMinor = 9
    ..serverProperties = {
    "product" : "foo"
  }
    ..mechanisms = "PLAIN"
    ..locales = "en");
  server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());
  frameWriter.outputEncoder.writer.clear();

  // Connection tune
  frameWriter.writeMessage(0, new ConnectionTuneMock()
    ..channelMax = 0
    ..frameMax = (new TuningSettings()).maxFrameSize
    ..heartbeat = 0);
  server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());
  frameWriter.outputEncoder.writer.clear();

  // Connection open ok
  frameWriter.writeMessage(0, new ConnectionOpenOkMock());
  server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());
  frameWriter.outputEncoder.writer.clear();
}

main({bool enableLogger : true}) {
  if (enableLogger) {
    mock.initLogger();
  }

  group("Exception handling:", () {
    Client client;
    mock.MockServer server;
    FrameWriter frameWriter;
    TuningSettings tuningSettings;

    setUp(() {
      tuningSettings = new TuningSettings();
      frameWriter = new FrameWriter(tuningSettings);
      server = new mock.MockServer();
      client = new Client(settings : new ConnectionSettings(port : 9000));
      return server.listen('127.0.0.1', 9000);
    });

    tearDown(() {
      return client.close()
      .then((_) => server.shutdown());
    });

    group("fatal exceptions:", () {
      test("protocol mismatch", () {
        TypeEncoder encoder = new TypeEncoder();
        new ProtocolHeader()
          ..protocolVersion = 0
          ..majorVersion = 0
          ..minorVersion = 8
          ..revision = 0
          ..serialize(encoder);

        server.replayList.add(encoder.writer.joinChunks());

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<FatalException>());
          expect(ex.message, equalsIgnoringCase("Could not negotiate a valid AMQP protocol version. Server supports AMQP 0.8.0"));
        }

        client
        .open()
        .then((_) {
          fail("Expected a FatalException to be thrown");
        }).catchError(expectAsync(handleError));
      });

      test("frame without terminator", () {
        frameWriter.writeMessage(0, new ConnectionStartMock()
          ..versionMajor = 0
          ..versionMinor = 9
          ..serverProperties = {
          "product" : "foo"
        }
          ..mechanisms = "PLAIN"
          ..locales = "en");
        Uint8List frameData = frameWriter.outputEncoder.writer.joinChunks();
        // Set an invalid frame terminator to the mock server response
        frameData[ frameData.length - 1 ] = 0xF0;
        server.replayList.add(frameData);

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<FatalException>());
          expect(ex.message, equalsIgnoringCase("Frame did not end with the expected frame terminator (0xCE)"));
        }

        client
        .open()
        .then((_) {
          fail("Expected an exception to be thrown");
        }).catchError(expectAsync(handleError));
      });

      test("frame on channel > 0 while handshake in progress", () {
        frameWriter.writeMessage(1, new ConnectionStartMock()
          ..versionMajor = 0
          ..versionMinor = 9
          ..serverProperties = {
          "product" : "foo"
        }
          ..mechanisms = "PLAIN"
          ..locales = "en");
        server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<FatalException>());
          expect(ex.message, equalsIgnoringCase("Received message for channel 1 while still handshaking"));
        }

        client
        .open()
        .then((_) {
          fail("Expected an exception to be thrown");
        }).catchError(expectAsync(handleError));
      });

      test("unexpected frame during handshake", () {
        // Connection start
        frameWriter.writeMessage(0, new ConnectionStartMock()
          ..versionMajor = 0
          ..versionMinor = 9
          ..serverProperties = {
          "product" : "foo"
        }
          ..mechanisms = "PLAIN"
          ..locales = "en");
        server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());
        frameWriter.outputEncoder.writer.clear();

        // Connection tune
        frameWriter.writeMessage(0, new ConnectionTuneMock()
          ..channelMax = 0
          ..frameMax = (new TuningSettings()).maxFrameSize
          ..heartbeat = 0);
        server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());
        frameWriter.outputEncoder.writer.clear();

        // Unexpected frame
        frameWriter.writeMessage(0, new TxSelectOkMock());
        server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());
        frameWriter.outputEncoder.writer.clear();

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<FatalException>());
          expect(ex.message, equalsIgnoringCase("Received unexpected message TxSelectOk during handshake"));
        }

        client
        .open()
        .then((_) {
          fail("Expected an exception to be thrown");
        }).catchError(expectAsync(handleError));
      });

    });

    group("connection exceptions:", () {
      test("illegal frame size", () {
        frameWriter.writeMessage(0, new ConnectionStartMock()
          ..versionMajor = 0
          ..versionMinor = 9
          ..serverProperties = {
          "product" : "foo"
        }
          ..mechanisms = "PLAIN"
          ..locales = "en");
        Uint8List frameData = frameWriter.outputEncoder.writer.joinChunks();
        // Manipulate the frame header to indicate a too long message
        int len = tuningSettings.maxFrameSize + 1;
        frameData[ 3 ] = (len >> 24) & 0xFF;
        frameData[ 4 ] = (len >> 16) & 0xFF;
        frameData[ 5 ] = (len >> 8) & 0xFF;
        frameData[ 6 ] = (len) & 0xFF;
        server.replayList.add(frameData);

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<ConnectionException>());
          expect(ex.message, equalsIgnoringCase("Frame size cannot be larger than ${tuningSettings.maxFrameSize} bytes. Server sent ${tuningSettings.maxFrameSize + 1} bytes"));
        }

        client
        .open()
        .then((_) {
          fail("Expected an exception to be thrown");
        }).catchError(expectAsync(handleError));
      });

      test("connection-class message on channel > 0 post handshake", () {
        generateHandshakeMessages(frameWriter, server);

        // Add a fake connection start message at channel 1
        frameWriter.writeMessage(1, new ConnectionStartMock()
          ..versionMajor = 0
          ..versionMinor = 9
          ..serverProperties = {
          "product" : "foo"
        }
          ..mechanisms = "PLAIN"
          ..locales = "en");
        server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<ConnectionException>());
          expect(ex.message, equalsIgnoringCase("Received CONNECTION class message on a channel > 0"));
        }

        client
        .channel()
        .then((_) {
          fail("Expected an exception to be thrown");
        }).catchError(expectAsync(handleError));
      });

      test("HEARTBEAT message on channel > 0", () {
        generateHandshakeMessages(frameWriter, server);

        // Add a heartbeat start message at channel 1
        frameWriter.outputEncoder.writer.addLast(new Uint8List.fromList([8, 0, 1, 0, 0, 0, 0, RawFrameParser.FRAME_TERMINATOR]));
        server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<ConnectionException>());
          expect(ex.message, equalsIgnoringCase("Received HEARTBEAT message on a channel > 0"));
        }

        client
        .channel()
        .then((_) {
          fail("Expected an exception to be thrown");
        }).catchError(expectAsync(handleError));
      });

      test("connection close message post handshake", () {
        generateHandshakeMessages(frameWriter, server);

        // Add a fake connection start message at channel 1
        frameWriter.writeMessage(0, new ConnectionClose()
          ..classId = 10
          ..methodId = 40
          ..replyCode = ErrorType.ACCESS_REFUSED.value
          ..replyText = "No access"
        );
        server.replayList.add(frameWriter.outputEncoder.writer.joinChunks());

        void handleError(ex, s) {
          expect(ex, new isInstanceOf<ConnectionException>());
          expect(ex.toString(), equals("ConnectionException(ACCESS_REFUSED): No access"));
        }

        client
        .channel()
        .then((_) {
          fail("Expected an exception to be thrown");
        }).catchError(expectAsync(handleError));
      });
    });

  });
}
