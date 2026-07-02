// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'vault.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VaultCommand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'VaultCommand()';
}


}

/// @nodoc
class $VaultCommandCopyWith<$Res>  {
$VaultCommandCopyWith(VaultCommand _, $Res Function(VaultCommand) __);
}


/// Adds pattern-matching-related methods to [VaultCommand].
extension VaultCommandPatterns on VaultCommand {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( VaultCommand_Save value)?  save,TResult Function( VaultCommand_Clear value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case VaultCommand_Save() when save != null:
return save(_that);case VaultCommand_Clear() when clear != null:
return clear(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( VaultCommand_Save value)  save,required TResult Function( VaultCommand_Clear value)  clear,}){
final _that = this;
switch (_that) {
case VaultCommand_Save():
return save(_that);case VaultCommand_Clear():
return clear(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( VaultCommand_Save value)?  save,TResult? Function( VaultCommand_Clear value)?  clear,}){
final _that = this;
switch (_that) {
case VaultCommand_Save() when save != null:
return save(_that);case VaultCommand_Clear() when clear != null:
return clear(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Uint8List blob)?  save,TResult Function()?  clear,required TResult orElse(),}) {final _that = this;
switch (_that) {
case VaultCommand_Save() when save != null:
return save(_that.blob);case VaultCommand_Clear() when clear != null:
return clear();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Uint8List blob)  save,required TResult Function()  clear,}) {final _that = this;
switch (_that) {
case VaultCommand_Save():
return save(_that.blob);case VaultCommand_Clear():
return clear();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Uint8List blob)?  save,TResult? Function()?  clear,}) {final _that = this;
switch (_that) {
case VaultCommand_Save() when save != null:
return save(_that.blob);case VaultCommand_Clear() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class VaultCommand_Save extends VaultCommand {
  const VaultCommand_Save({required this.blob}): super._();
  

 final  Uint8List blob;

/// Create a copy of VaultCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultCommand_SaveCopyWith<VaultCommand_Save> get copyWith => _$VaultCommand_SaveCopyWithImpl<VaultCommand_Save>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultCommand_Save&&const DeepCollectionEquality().equals(other.blob, blob));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(blob));

@override
String toString() {
  return 'VaultCommand.save(blob: $blob)';
}


}

/// @nodoc
abstract mixin class $VaultCommand_SaveCopyWith<$Res> implements $VaultCommandCopyWith<$Res> {
  factory $VaultCommand_SaveCopyWith(VaultCommand_Save value, $Res Function(VaultCommand_Save) _then) = _$VaultCommand_SaveCopyWithImpl;
@useResult
$Res call({
 Uint8List blob
});




}
/// @nodoc
class _$VaultCommand_SaveCopyWithImpl<$Res>
    implements $VaultCommand_SaveCopyWith<$Res> {
  _$VaultCommand_SaveCopyWithImpl(this._self, this._then);

  final VaultCommand_Save _self;
  final $Res Function(VaultCommand_Save) _then;

/// Create a copy of VaultCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? blob = null,}) {
  return _then(VaultCommand_Save(
blob: null == blob ? _self.blob : blob // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class VaultCommand_Clear extends VaultCommand {
  const VaultCommand_Clear(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultCommand_Clear);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'VaultCommand.clear()';
}


}




// dart format on
