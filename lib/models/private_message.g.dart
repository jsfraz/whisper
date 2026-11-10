// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'private_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PrivateMessageAdapter extends TypeAdapter<PrivateMessage> {
  @override
  final int typeId = 3;

  @override
  PrivateMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PrivateMessage(
      fields[0] as int,
      fields[1] as String,
      fields[2] as DateTime,
      fields[3] as DateTime,
      fields[4] as bool,
      mediaId: fields[5] as String?,
      mediaTypeStr: fields[6] as String?,
      localPath: fields[7] as String?,
      mediaSize: fields[8] as int?,
      width: fields[9] as int?,
      height: fields[10] as int?,
      durationMs: fields[11] as int?,
      downloadStatus: fields[12] == null ? 1 : fields[12] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PrivateMessage obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.senderId)
      ..writeByte(1)
      ..write(obj.message)
      ..writeByte(2)
      ..write(obj.sentAt)
      ..writeByte(3)
      ..write(obj.receivedAt)
      ..writeByte(4)
      ..write(obj.read)
      ..writeByte(5)
      ..write(obj.mediaId)
      ..writeByte(6)
      ..write(obj.mediaTypeStr)
      ..writeByte(7)
      ..write(obj.localPath)
      ..writeByte(8)
      ..write(obj.mediaSize)
      ..writeByte(9)
      ..write(obj.width)
      ..writeByte(10)
      ..write(obj.height)
      ..writeByte(11)
      ..write(obj.durationMs)
      ..writeByte(12)
      ..write(obj.downloadStatus);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivateMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
