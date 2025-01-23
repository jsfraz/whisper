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
    );
  }

  @override
  void write(BinaryWriter writer, PrivateMessage obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.senderId)
      ..writeByte(1)
      ..write(obj.message)
      ..writeByte(2)
      ..write(obj.sentAt)
      ..writeByte(3)
      ..write(obj.receivedAt);
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
