// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'realtime.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AlertCommand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlertCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AlertCommand()';
}


}

/// @nodoc
class $AlertCommandCopyWith<$Res>  {
$AlertCommandCopyWith(AlertCommand _, $Res Function(AlertCommand) __);
}


/// Adds pattern-matching-related methods to [AlertCommand].
extension AlertCommandPatterns on AlertCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AlertCommand_Ping value)?  ping,TResult Function( AlertCommand_Notify value)?  notify,TResult Function( AlertCommand_Haptic value)?  haptic,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AlertCommand_Ping() when ping != null:
return ping(_that);case AlertCommand_Notify() when notify != null:
return notify(_that);case AlertCommand_Haptic() when haptic != null:
return haptic(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AlertCommand_Ping value)  ping,required TResult Function( AlertCommand_Notify value)  notify,required TResult Function( AlertCommand_Haptic value)  haptic,}){
final _that = this;
switch (_that) {
case AlertCommand_Ping():
return ping(_that);case AlertCommand_Notify():
return notify(_that);case AlertCommand_Haptic():
return haptic(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AlertCommand_Ping value)?  ping,TResult? Function( AlertCommand_Notify value)?  notify,TResult? Function( AlertCommand_Haptic value)?  haptic,}){
final _that = this;
switch (_that) {
case AlertCommand_Ping() when ping != null:
return ping(_that);case AlertCommand_Notify() when notify != null:
return notify(_that);case AlertCommand_Haptic() when haptic != null:
return haptic(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  ping,TResult Function( String title,  String body,  String tag)?  notify,TResult Function()?  haptic,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AlertCommand_Ping() when ping != null:
return ping();case AlertCommand_Notify() when notify != null:
return notify(_that.title,_that.body,_that.tag);case AlertCommand_Haptic() when haptic != null:
return haptic();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  ping,required TResult Function( String title,  String body,  String tag)  notify,required TResult Function()  haptic,}) {final _that = this;
switch (_that) {
case AlertCommand_Ping():
return ping();case AlertCommand_Notify():
return notify(_that.title,_that.body,_that.tag);case AlertCommand_Haptic():
return haptic();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  ping,TResult? Function( String title,  String body,  String tag)?  notify,TResult? Function()?  haptic,}) {final _that = this;
switch (_that) {
case AlertCommand_Ping() when ping != null:
return ping();case AlertCommand_Notify() when notify != null:
return notify(_that.title,_that.body,_that.tag);case AlertCommand_Haptic() when haptic != null:
return haptic();case _:
  return null;

}
}

}

/// @nodoc


class AlertCommand_Ping extends AlertCommand {
  const AlertCommand_Ping(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlertCommand_Ping);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AlertCommand.ping()';
}


}




/// @nodoc


class AlertCommand_Notify extends AlertCommand {
  const AlertCommand_Notify({required this.title, required this.body, required this.tag}): super._();
  

 final  String title;
 final  String body;
 final  String tag;

/// Create a copy of AlertCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlertCommand_NotifyCopyWith<AlertCommand_Notify> get copyWith => _$AlertCommand_NotifyCopyWithImpl<AlertCommand_Notify>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlertCommand_Notify&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.tag, tag) || other.tag == tag));
}


@override
int get hashCode => Object.hash(runtimeType,title,body,tag);

@override
String toString() {
  return 'AlertCommand.notify(title: $title, body: $body, tag: $tag)';
}


}

/// @nodoc
abstract mixin class $AlertCommand_NotifyCopyWith<$Res> implements $AlertCommandCopyWith<$Res> {
  factory $AlertCommand_NotifyCopyWith(AlertCommand_Notify value, $Res Function(AlertCommand_Notify) _then) = _$AlertCommand_NotifyCopyWithImpl;
@useResult
$Res call({
 String title, String body, String tag
});




}
/// @nodoc
class _$AlertCommand_NotifyCopyWithImpl<$Res>
    implements $AlertCommand_NotifyCopyWith<$Res> {
  _$AlertCommand_NotifyCopyWithImpl(this._self, this._then);

  final AlertCommand_Notify _self;
  final $Res Function(AlertCommand_Notify) _then;

/// Create a copy of AlertCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = null,Object? body = null,Object? tag = null,}) {
  return _then(AlertCommand_Notify(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,tag: null == tag ? _self.tag : tag // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AlertCommand_Haptic extends AlertCommand {
  const AlertCommand_Haptic(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlertCommand_Haptic);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AlertCommand.haptic()';
}


}




/// @nodoc
mixin _$RealtimeMessage {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RealtimeMessage);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RealtimeMessage()';
}


}

/// @nodoc
class $RealtimeMessageCopyWith<$Res>  {
$RealtimeMessageCopyWith(RealtimeMessage _, $Res Function(RealtimeMessage) __);
}


/// Adds pattern-matching-related methods to [RealtimeMessage].
extension RealtimeMessagePatterns on RealtimeMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RealtimeMessage_Event value)?  event,TResult Function( RealtimeMessage_ConnectionChanged value)?  connectionChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RealtimeMessage_Event() when event != null:
return event(_that);case RealtimeMessage_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RealtimeMessage_Event value)  event,required TResult Function( RealtimeMessage_ConnectionChanged value)  connectionChanged,}){
final _that = this;
switch (_that) {
case RealtimeMessage_Event():
return event(_that);case RealtimeMessage_ConnectionChanged():
return connectionChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RealtimeMessage_Event value)?  event,TResult? Function( RealtimeMessage_ConnectionChanged value)?  connectionChanged,}){
final _that = this;
switch (_that) {
case RealtimeMessage_Event() when event != null:
return event(_that);case RealtimeMessage_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String eventType,  String data)?  event,TResult Function( bool connected)?  connectionChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RealtimeMessage_Event() when event != null:
return event(_that.eventType,_that.data);case RealtimeMessage_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that.connected);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String eventType,  String data)  event,required TResult Function( bool connected)  connectionChanged,}) {final _that = this;
switch (_that) {
case RealtimeMessage_Event():
return event(_that.eventType,_that.data);case RealtimeMessage_ConnectionChanged():
return connectionChanged(_that.connected);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String eventType,  String data)?  event,TResult? Function( bool connected)?  connectionChanged,}) {final _that = this;
switch (_that) {
case RealtimeMessage_Event() when event != null:
return event(_that.eventType,_that.data);case RealtimeMessage_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that.connected);case _:
  return null;

}
}

}

/// @nodoc


class RealtimeMessage_Event extends RealtimeMessage {
  const RealtimeMessage_Event({required this.eventType, required this.data}): super._();
  

 final  String eventType;
 final  String data;

/// Create a copy of RealtimeMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RealtimeMessage_EventCopyWith<RealtimeMessage_Event> get copyWith => _$RealtimeMessage_EventCopyWithImpl<RealtimeMessage_Event>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RealtimeMessage_Event&&(identical(other.eventType, eventType) || other.eventType == eventType)&&(identical(other.data, data) || other.data == data));
}


@override
int get hashCode => Object.hash(runtimeType,eventType,data);

@override
String toString() {
  return 'RealtimeMessage.event(eventType: $eventType, data: $data)';
}


}

/// @nodoc
abstract mixin class $RealtimeMessage_EventCopyWith<$Res> implements $RealtimeMessageCopyWith<$Res> {
  factory $RealtimeMessage_EventCopyWith(RealtimeMessage_Event value, $Res Function(RealtimeMessage_Event) _then) = _$RealtimeMessage_EventCopyWithImpl;
@useResult
$Res call({
 String eventType, String data
});




}
/// @nodoc
class _$RealtimeMessage_EventCopyWithImpl<$Res>
    implements $RealtimeMessage_EventCopyWith<$Res> {
  _$RealtimeMessage_EventCopyWithImpl(this._self, this._then);

  final RealtimeMessage_Event _self;
  final $Res Function(RealtimeMessage_Event) _then;

/// Create a copy of RealtimeMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? eventType = null,Object? data = null,}) {
  return _then(RealtimeMessage_Event(
eventType: null == eventType ? _self.eventType : eventType // ignore: cast_nullable_to_non_nullable
as String,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RealtimeMessage_ConnectionChanged extends RealtimeMessage {
  const RealtimeMessage_ConnectionChanged({required this.connected}): super._();
  

 final  bool connected;

/// Create a copy of RealtimeMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RealtimeMessage_ConnectionChangedCopyWith<RealtimeMessage_ConnectionChanged> get copyWith => _$RealtimeMessage_ConnectionChangedCopyWithImpl<RealtimeMessage_ConnectionChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RealtimeMessage_ConnectionChanged&&(identical(other.connected, connected) || other.connected == connected));
}


@override
int get hashCode => Object.hash(runtimeType,connected);

@override
String toString() {
  return 'RealtimeMessage.connectionChanged(connected: $connected)';
}


}

/// @nodoc
abstract mixin class $RealtimeMessage_ConnectionChangedCopyWith<$Res> implements $RealtimeMessageCopyWith<$Res> {
  factory $RealtimeMessage_ConnectionChangedCopyWith(RealtimeMessage_ConnectionChanged value, $Res Function(RealtimeMessage_ConnectionChanged) _then) = _$RealtimeMessage_ConnectionChangedCopyWithImpl;
@useResult
$Res call({
 bool connected
});




}
/// @nodoc
class _$RealtimeMessage_ConnectionChangedCopyWithImpl<$Res>
    implements $RealtimeMessage_ConnectionChangedCopyWith<$Res> {
  _$RealtimeMessage_ConnectionChangedCopyWithImpl(this._self, this._then);

  final RealtimeMessage_ConnectionChanged _self;
  final $Res Function(RealtimeMessage_ConnectionChanged) _then;

/// Create a copy of RealtimeMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? connected = null,}) {
  return _then(RealtimeMessage_ConnectionChanged(
connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
