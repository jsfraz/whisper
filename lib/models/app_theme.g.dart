// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_theme.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppThemeAdapter extends TypeAdapter<AppTheme> {
  @override
  final int typeId = 2;

  @override
  AppTheme read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppTheme(
      fields[0] as String,
      fields[1] as String,
      fields[2] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AppTheme obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.themeModeStr)
      ..writeByte(1)
      ..write(obj.colorHex)
      ..writeByte(2)
      ..write(obj.useMaterial3);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppThemeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
