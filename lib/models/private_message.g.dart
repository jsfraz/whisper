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
      fields[0] as String,
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
      fileName: fields[13] as String?,
      sendStatus: fields[14] == null ? 1 : fields[14] as int,
      albumJson: fields[15] as String?,
      replyToSenderId: fields[16] as String?,
      replyToSentAt: fields[17] as DateTime?,
      replyToPreview: fields[18] as String?,
      editedAt: fields[20] as DateTime?,
      reactions: (fields[21] as Map?)?.cast<String, String>(),
      forwarded: fields[22] == null ? false : fields[22] as bool,
      mediaRefJson: fields[23] as String?,
      expiresAt: fields[24] as DateTime?,
      systemState: fields[25] as String?,
      systemSeconds: fields[26] == null ? 0 : fields[26] as int,
      viewOnce: fields[27] == null ? false : fields[27] as bool,
      locationJson: fields[28] as String?,
      openedAt: fields[29] as DateTime?,
      deletedAt: fields[30] as DateTime?,
    )..id = fields[19] as String?;
  }

  @override
  void write(BinaryWriter writer, PrivateMessage obj) {
    writer
      ..writeByte(31)
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
      ..write(obj.downloadStatus)
      ..writeByte(13)
      ..write(obj.fileName)
      ..writeByte(14)
      ..write(obj.sendStatus)
      ..writeByte(15)
      ..write(obj.albumJson)
      ..writeByte(16)
      ..write(obj.replyToSenderId)
      ..writeByte(17)
      ..write(obj.replyToSentAt)
      ..writeByte(18)
      ..write(obj.replyToPreview)
      ..writeByte(19)
      ..write(obj.id)
      ..writeByte(20)
      ..write(obj.editedAt)
      ..writeByte(21)
      ..write(obj.reactions)
      ..writeByte(22)
      ..write(obj.forwarded)
      ..writeByte(23)
      ..write(obj.mediaRefJson)
      ..writeByte(24)
      ..write(obj.expiresAt)
      ..writeByte(25)
      ..write(obj.systemState)
      ..writeByte(26)
      ..write(obj.systemSeconds)
      ..writeByte(27)
      ..write(obj.viewOnce)
      ..writeByte(28)
      ..write(obj.locationJson)
      ..writeByte(29)
      ..write(obj.openedAt)
      ..writeByte(30)
      ..write(obj.deletedAt);
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
