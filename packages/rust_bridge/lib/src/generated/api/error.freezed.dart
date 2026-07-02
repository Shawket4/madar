// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MadarError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MadarError()';
}


}

/// @nodoc
class $MadarErrorCopyWith<$Res>  {
$MadarErrorCopyWith(MadarError _, $Res Function(MadarError) __);
}


/// Adds pattern-matching-related methods to [MadarError].
extension MadarErrorPatterns on MadarError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MadarError_Offline value)?  offline,TResult Function( MadarError_Unauthenticated value)?  unauthenticated,TResult Function( MadarError_Forbidden value)?  forbidden,TResult Function( MadarError_Validation value)?  validation,TResult Function( MadarError_Server value)?  server,TResult Function( MadarError_Transient value)?  transient,TResult Function( MadarError_Internal value)?  internal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MadarError_Offline() when offline != null:
return offline(_that);case MadarError_Unauthenticated() when unauthenticated != null:
return unauthenticated(_that);case MadarError_Forbidden() when forbidden != null:
return forbidden(_that);case MadarError_Validation() when validation != null:
return validation(_that);case MadarError_Server() when server != null:
return server(_that);case MadarError_Transient() when transient != null:
return transient(_that);case MadarError_Internal() when internal != null:
return internal(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MadarError_Offline value)  offline,required TResult Function( MadarError_Unauthenticated value)  unauthenticated,required TResult Function( MadarError_Forbidden value)  forbidden,required TResult Function( MadarError_Validation value)  validation,required TResult Function( MadarError_Server value)  server,required TResult Function( MadarError_Transient value)  transient,required TResult Function( MadarError_Internal value)  internal,}){
final _that = this;
switch (_that) {
case MadarError_Offline():
return offline(_that);case MadarError_Unauthenticated():
return unauthenticated(_that);case MadarError_Forbidden():
return forbidden(_that);case MadarError_Validation():
return validation(_that);case MadarError_Server():
return server(_that);case MadarError_Transient():
return transient(_that);case MadarError_Internal():
return internal(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MadarError_Offline value)?  offline,TResult? Function( MadarError_Unauthenticated value)?  unauthenticated,TResult? Function( MadarError_Forbidden value)?  forbidden,TResult? Function( MadarError_Validation value)?  validation,TResult? Function( MadarError_Server value)?  server,TResult? Function( MadarError_Transient value)?  transient,TResult? Function( MadarError_Internal value)?  internal,}){
final _that = this;
switch (_that) {
case MadarError_Offline() when offline != null:
return offline(_that);case MadarError_Unauthenticated() when unauthenticated != null:
return unauthenticated(_that);case MadarError_Forbidden() when forbidden != null:
return forbidden(_that);case MadarError_Validation() when validation != null:
return validation(_that);case MadarError_Server() when server != null:
return server(_that);case MadarError_Transient() when transient != null:
return transient(_that);case MadarError_Internal() when internal != null:
return internal(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String detail)?  offline,TResult Function( String detail)?  unauthenticated,TResult Function( String resource,  String action)?  forbidden,TResult Function( String field,  String detail)?  validation,TResult Function( int status,  String code,  String detail)?  server,TResult Function( String detail)?  transient,TResult Function( String detail)?  internal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MadarError_Offline() when offline != null:
return offline(_that.detail);case MadarError_Unauthenticated() when unauthenticated != null:
return unauthenticated(_that.detail);case MadarError_Forbidden() when forbidden != null:
return forbidden(_that.resource,_that.action);case MadarError_Validation() when validation != null:
return validation(_that.field,_that.detail);case MadarError_Server() when server != null:
return server(_that.status,_that.code,_that.detail);case MadarError_Transient() when transient != null:
return transient(_that.detail);case MadarError_Internal() when internal != null:
return internal(_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String detail)  offline,required TResult Function( String detail)  unauthenticated,required TResult Function( String resource,  String action)  forbidden,required TResult Function( String field,  String detail)  validation,required TResult Function( int status,  String code,  String detail)  server,required TResult Function( String detail)  transient,required TResult Function( String detail)  internal,}) {final _that = this;
switch (_that) {
case MadarError_Offline():
return offline(_that.detail);case MadarError_Unauthenticated():
return unauthenticated(_that.detail);case MadarError_Forbidden():
return forbidden(_that.resource,_that.action);case MadarError_Validation():
return validation(_that.field,_that.detail);case MadarError_Server():
return server(_that.status,_that.code,_that.detail);case MadarError_Transient():
return transient(_that.detail);case MadarError_Internal():
return internal(_that.detail);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String detail)?  offline,TResult? Function( String detail)?  unauthenticated,TResult? Function( String resource,  String action)?  forbidden,TResult? Function( String field,  String detail)?  validation,TResult? Function( int status,  String code,  String detail)?  server,TResult? Function( String detail)?  transient,TResult? Function( String detail)?  internal,}) {final _that = this;
switch (_that) {
case MadarError_Offline() when offline != null:
return offline(_that.detail);case MadarError_Unauthenticated() when unauthenticated != null:
return unauthenticated(_that.detail);case MadarError_Forbidden() when forbidden != null:
return forbidden(_that.resource,_that.action);case MadarError_Validation() when validation != null:
return validation(_that.field,_that.detail);case MadarError_Server() when server != null:
return server(_that.status,_that.code,_that.detail);case MadarError_Transient() when transient != null:
return transient(_that.detail);case MadarError_Internal() when internal != null:
return internal(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class MadarError_Offline extends MadarError {
  const MadarError_Offline({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MadarError_OfflineCopyWith<MadarError_Offline> get copyWith => _$MadarError_OfflineCopyWithImpl<MadarError_Offline>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError_Offline&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'MadarError.offline(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $MadarError_OfflineCopyWith<$Res> implements $MadarErrorCopyWith<$Res> {
  factory $MadarError_OfflineCopyWith(MadarError_Offline value, $Res Function(MadarError_Offline) _then) = _$MadarError_OfflineCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$MadarError_OfflineCopyWithImpl<$Res>
    implements $MadarError_OfflineCopyWith<$Res> {
  _$MadarError_OfflineCopyWithImpl(this._self, this._then);

  final MadarError_Offline _self;
  final $Res Function(MadarError_Offline) _then;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(MadarError_Offline(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MadarError_Unauthenticated extends MadarError {
  const MadarError_Unauthenticated({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MadarError_UnauthenticatedCopyWith<MadarError_Unauthenticated> get copyWith => _$MadarError_UnauthenticatedCopyWithImpl<MadarError_Unauthenticated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError_Unauthenticated&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'MadarError.unauthenticated(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $MadarError_UnauthenticatedCopyWith<$Res> implements $MadarErrorCopyWith<$Res> {
  factory $MadarError_UnauthenticatedCopyWith(MadarError_Unauthenticated value, $Res Function(MadarError_Unauthenticated) _then) = _$MadarError_UnauthenticatedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$MadarError_UnauthenticatedCopyWithImpl<$Res>
    implements $MadarError_UnauthenticatedCopyWith<$Res> {
  _$MadarError_UnauthenticatedCopyWithImpl(this._self, this._then);

  final MadarError_Unauthenticated _self;
  final $Res Function(MadarError_Unauthenticated) _then;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(MadarError_Unauthenticated(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MadarError_Forbidden extends MadarError {
  const MadarError_Forbidden({required this.resource, required this.action}): super._();
  

 final  String resource;
 final  String action;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MadarError_ForbiddenCopyWith<MadarError_Forbidden> get copyWith => _$MadarError_ForbiddenCopyWithImpl<MadarError_Forbidden>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError_Forbidden&&(identical(other.resource, resource) || other.resource == resource)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode => Object.hash(runtimeType,resource,action);

@override
String toString() {
  return 'MadarError.forbidden(resource: $resource, action: $action)';
}


}

/// @nodoc
abstract mixin class $MadarError_ForbiddenCopyWith<$Res> implements $MadarErrorCopyWith<$Res> {
  factory $MadarError_ForbiddenCopyWith(MadarError_Forbidden value, $Res Function(MadarError_Forbidden) _then) = _$MadarError_ForbiddenCopyWithImpl;
@useResult
$Res call({
 String resource, String action
});




}
/// @nodoc
class _$MadarError_ForbiddenCopyWithImpl<$Res>
    implements $MadarError_ForbiddenCopyWith<$Res> {
  _$MadarError_ForbiddenCopyWithImpl(this._self, this._then);

  final MadarError_Forbidden _self;
  final $Res Function(MadarError_Forbidden) _then;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? resource = null,Object? action = null,}) {
  return _then(MadarError_Forbidden(
resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as String,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MadarError_Validation extends MadarError {
  const MadarError_Validation({required this.field, required this.detail}): super._();
  

 final  String field;
 final  String detail;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MadarError_ValidationCopyWith<MadarError_Validation> get copyWith => _$MadarError_ValidationCopyWithImpl<MadarError_Validation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError_Validation&&(identical(other.field, field) || other.field == field)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,field,detail);

@override
String toString() {
  return 'MadarError.validation(field: $field, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $MadarError_ValidationCopyWith<$Res> implements $MadarErrorCopyWith<$Res> {
  factory $MadarError_ValidationCopyWith(MadarError_Validation value, $Res Function(MadarError_Validation) _then) = _$MadarError_ValidationCopyWithImpl;
@useResult
$Res call({
 String field, String detail
});




}
/// @nodoc
class _$MadarError_ValidationCopyWithImpl<$Res>
    implements $MadarError_ValidationCopyWith<$Res> {
  _$MadarError_ValidationCopyWithImpl(this._self, this._then);

  final MadarError_Validation _self;
  final $Res Function(MadarError_Validation) _then;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field = null,Object? detail = null,}) {
  return _then(MadarError_Validation(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MadarError_Server extends MadarError {
  const MadarError_Server({required this.status, required this.code, required this.detail}): super._();
  

 final  int status;
 final  String code;
 final  String detail;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MadarError_ServerCopyWith<MadarError_Server> get copyWith => _$MadarError_ServerCopyWithImpl<MadarError_Server>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError_Server&&(identical(other.status, status) || other.status == status)&&(identical(other.code, code) || other.code == code)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,status,code,detail);

@override
String toString() {
  return 'MadarError.server(status: $status, code: $code, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $MadarError_ServerCopyWith<$Res> implements $MadarErrorCopyWith<$Res> {
  factory $MadarError_ServerCopyWith(MadarError_Server value, $Res Function(MadarError_Server) _then) = _$MadarError_ServerCopyWithImpl;
@useResult
$Res call({
 int status, String code, String detail
});




}
/// @nodoc
class _$MadarError_ServerCopyWithImpl<$Res>
    implements $MadarError_ServerCopyWith<$Res> {
  _$MadarError_ServerCopyWithImpl(this._self, this._then);

  final MadarError_Server _self;
  final $Res Function(MadarError_Server) _then;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? code = null,Object? detail = null,}) {
  return _then(MadarError_Server(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MadarError_Transient extends MadarError {
  const MadarError_Transient({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MadarError_TransientCopyWith<MadarError_Transient> get copyWith => _$MadarError_TransientCopyWithImpl<MadarError_Transient>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError_Transient&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'MadarError.transient(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $MadarError_TransientCopyWith<$Res> implements $MadarErrorCopyWith<$Res> {
  factory $MadarError_TransientCopyWith(MadarError_Transient value, $Res Function(MadarError_Transient) _then) = _$MadarError_TransientCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$MadarError_TransientCopyWithImpl<$Res>
    implements $MadarError_TransientCopyWith<$Res> {
  _$MadarError_TransientCopyWithImpl(this._self, this._then);

  final MadarError_Transient _self;
  final $Res Function(MadarError_Transient) _then;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(MadarError_Transient(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MadarError_Internal extends MadarError {
  const MadarError_Internal({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MadarError_InternalCopyWith<MadarError_Internal> get copyWith => _$MadarError_InternalCopyWithImpl<MadarError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MadarError_Internal&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'MadarError.internal(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $MadarError_InternalCopyWith<$Res> implements $MadarErrorCopyWith<$Res> {
  factory $MadarError_InternalCopyWith(MadarError_Internal value, $Res Function(MadarError_Internal) _then) = _$MadarError_InternalCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$MadarError_InternalCopyWithImpl<$Res>
    implements $MadarError_InternalCopyWith<$Res> {
  _$MadarError_InternalCopyWithImpl(this._self, this._then);

  final MadarError_Internal _self;
  final $Res Function(MadarError_Internal) _then;

/// Create a copy of MadarError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(MadarError_Internal(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
