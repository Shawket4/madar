// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routes.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppRoute {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRoute);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppRoute()';
}


}

/// @nodoc
class $AppRouteCopyWith<$Res>  {
$AppRouteCopyWith(AppRoute _, $Res Function(AppRoute) __);
}


/// Adds pattern-matching-related methods to [AppRoute].
extension AppRoutePatterns on AppRoute {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppRoute_DeviceSetup value)?  deviceSetup,TResult Function( AppRoute_Login value)?  login,TResult Function( AppRoute_OpenShift value)?  openShift,TResult Function( AppRoute_Order value)?  order,TResult Function( AppRoute_KitchenDisplay value)?  kitchenDisplay,TResult Function( AppRoute_WaiterTickets value)?  waiterTickets,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppRoute_DeviceSetup() when deviceSetup != null:
return deviceSetup(_that);case AppRoute_Login() when login != null:
return login(_that);case AppRoute_OpenShift() when openShift != null:
return openShift(_that);case AppRoute_Order() when order != null:
return order(_that);case AppRoute_KitchenDisplay() when kitchenDisplay != null:
return kitchenDisplay(_that);case AppRoute_WaiterTickets() when waiterTickets != null:
return waiterTickets(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppRoute_DeviceSetup value)  deviceSetup,required TResult Function( AppRoute_Login value)  login,required TResult Function( AppRoute_OpenShift value)  openShift,required TResult Function( AppRoute_Order value)  order,required TResult Function( AppRoute_KitchenDisplay value)  kitchenDisplay,required TResult Function( AppRoute_WaiterTickets value)  waiterTickets,}){
final _that = this;
switch (_that) {
case AppRoute_DeviceSetup():
return deviceSetup(_that);case AppRoute_Login():
return login(_that);case AppRoute_OpenShift():
return openShift(_that);case AppRoute_Order():
return order(_that);case AppRoute_KitchenDisplay():
return kitchenDisplay(_that);case AppRoute_WaiterTickets():
return waiterTickets(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppRoute_DeviceSetup value)?  deviceSetup,TResult? Function( AppRoute_Login value)?  login,TResult? Function( AppRoute_OpenShift value)?  openShift,TResult? Function( AppRoute_Order value)?  order,TResult? Function( AppRoute_KitchenDisplay value)?  kitchenDisplay,TResult? Function( AppRoute_WaiterTickets value)?  waiterTickets,}){
final _that = this;
switch (_that) {
case AppRoute_DeviceSetup() when deviceSetup != null:
return deviceSetup(_that);case AppRoute_Login() when login != null:
return login(_that);case AppRoute_OpenShift() when openShift != null:
return openShift(_that);case AppRoute_Order() when order != null:
return order(_that);case AppRoute_KitchenDisplay() when kitchenDisplay != null:
return kitchenDisplay(_that);case AppRoute_WaiterTickets() when waiterTickets != null:
return waiterTickets(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  deviceSetup,TResult Function()?  login,TResult Function()?  openShift,TResult Function()?  order,TResult Function( String stationId)?  kitchenDisplay,TResult Function()?  waiterTickets,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppRoute_DeviceSetup() when deviceSetup != null:
return deviceSetup();case AppRoute_Login() when login != null:
return login();case AppRoute_OpenShift() when openShift != null:
return openShift();case AppRoute_Order() when order != null:
return order();case AppRoute_KitchenDisplay() when kitchenDisplay != null:
return kitchenDisplay(_that.stationId);case AppRoute_WaiterTickets() when waiterTickets != null:
return waiterTickets();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  deviceSetup,required TResult Function()  login,required TResult Function()  openShift,required TResult Function()  order,required TResult Function( String stationId)  kitchenDisplay,required TResult Function()  waiterTickets,}) {final _that = this;
switch (_that) {
case AppRoute_DeviceSetup():
return deviceSetup();case AppRoute_Login():
return login();case AppRoute_OpenShift():
return openShift();case AppRoute_Order():
return order();case AppRoute_KitchenDisplay():
return kitchenDisplay(_that.stationId);case AppRoute_WaiterTickets():
return waiterTickets();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  deviceSetup,TResult? Function()?  login,TResult? Function()?  openShift,TResult? Function()?  order,TResult? Function( String stationId)?  kitchenDisplay,TResult? Function()?  waiterTickets,}) {final _that = this;
switch (_that) {
case AppRoute_DeviceSetup() when deviceSetup != null:
return deviceSetup();case AppRoute_Login() when login != null:
return login();case AppRoute_OpenShift() when openShift != null:
return openShift();case AppRoute_Order() when order != null:
return order();case AppRoute_KitchenDisplay() when kitchenDisplay != null:
return kitchenDisplay(_that.stationId);case AppRoute_WaiterTickets() when waiterTickets != null:
return waiterTickets();case _:
  return null;

}
}

}

/// @nodoc


class AppRoute_DeviceSetup extends AppRoute {
  const AppRoute_DeviceSetup(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRoute_DeviceSetup);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppRoute.deviceSetup()';
}


}




/// @nodoc


class AppRoute_Login extends AppRoute {
  const AppRoute_Login(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRoute_Login);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppRoute.login()';
}


}




/// @nodoc


class AppRoute_OpenShift extends AppRoute {
  const AppRoute_OpenShift(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRoute_OpenShift);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppRoute.openShift()';
}


}




/// @nodoc


class AppRoute_Order extends AppRoute {
  const AppRoute_Order(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRoute_Order);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppRoute.order()';
}


}




/// @nodoc


class AppRoute_KitchenDisplay extends AppRoute {
  const AppRoute_KitchenDisplay({required this.stationId}): super._();
  

 final  String stationId;

/// Create a copy of AppRoute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppRoute_KitchenDisplayCopyWith<AppRoute_KitchenDisplay> get copyWith => _$AppRoute_KitchenDisplayCopyWithImpl<AppRoute_KitchenDisplay>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRoute_KitchenDisplay&&(identical(other.stationId, stationId) || other.stationId == stationId));
}


@override
int get hashCode => Object.hash(runtimeType,stationId);

@override
String toString() {
  return 'AppRoute.kitchenDisplay(stationId: $stationId)';
}


}

/// @nodoc
abstract mixin class $AppRoute_KitchenDisplayCopyWith<$Res> implements $AppRouteCopyWith<$Res> {
  factory $AppRoute_KitchenDisplayCopyWith(AppRoute_KitchenDisplay value, $Res Function(AppRoute_KitchenDisplay) _then) = _$AppRoute_KitchenDisplayCopyWithImpl;
@useResult
$Res call({
 String stationId
});




}
/// @nodoc
class _$AppRoute_KitchenDisplayCopyWithImpl<$Res>
    implements $AppRoute_KitchenDisplayCopyWith<$Res> {
  _$AppRoute_KitchenDisplayCopyWithImpl(this._self, this._then);

  final AppRoute_KitchenDisplay _self;
  final $Res Function(AppRoute_KitchenDisplay) _then;

/// Create a copy of AppRoute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stationId = null,}) {
  return _then(AppRoute_KitchenDisplay(
stationId: null == stationId ? _self.stationId : stationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppRoute_WaiterTickets extends AppRoute {
  const AppRoute_WaiterTickets(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRoute_WaiterTickets);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppRoute.waiterTickets()';
}


}




// dart format on
