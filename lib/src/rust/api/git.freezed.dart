// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'git.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TransferEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TransferEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TransferEvent()';
}


}

/// @nodoc
class $TransferEventCopyWith<$Res>  {
$TransferEventCopyWith(TransferEvent _, $Res Function(TransferEvent) __);
}


/// Adds pattern-matching-related methods to [TransferEvent].
extension TransferEventPatterns on TransferEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TransferEvent_Progress value)?  progress,TResult Function( TransferEvent_Done value)?  done,TResult Function( TransferEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TransferEvent_Progress() when progress != null:
return progress(_that);case TransferEvent_Done() when done != null:
return done(_that);case TransferEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TransferEvent_Progress value)  progress,required TResult Function( TransferEvent_Done value)  done,required TResult Function( TransferEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case TransferEvent_Progress():
return progress(_that);case TransferEvent_Done():
return done(_that);case TransferEvent_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TransferEvent_Progress value)?  progress,TResult? Function( TransferEvent_Done value)?  done,TResult? Function( TransferEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case TransferEvent_Progress() when progress != null:
return progress(_that);case TransferEvent_Done() when done != null:
return done(_that);case TransferEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Progress field0)?  progress,TResult Function()?  done,TResult Function( CoreError field0)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TransferEvent_Progress() when progress != null:
return progress(_that.field0);case TransferEvent_Done() when done != null:
return done();case TransferEvent_Failed() when failed != null:
return failed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Progress field0)  progress,required TResult Function()  done,required TResult Function( CoreError field0)  failed,}) {final _that = this;
switch (_that) {
case TransferEvent_Progress():
return progress(_that.field0);case TransferEvent_Done():
return done();case TransferEvent_Failed():
return failed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Progress field0)?  progress,TResult? Function()?  done,TResult? Function( CoreError field0)?  failed,}) {final _that = this;
switch (_that) {
case TransferEvent_Progress() when progress != null:
return progress(_that.field0);case TransferEvent_Done() when done != null:
return done();case TransferEvent_Failed() when failed != null:
return failed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class TransferEvent_Progress extends TransferEvent {
  const TransferEvent_Progress(this.field0): super._();
  

 final  Progress field0;

/// Create a copy of TransferEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransferEvent_ProgressCopyWith<TransferEvent_Progress> get copyWith => _$TransferEvent_ProgressCopyWithImpl<TransferEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TransferEvent_Progress&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'TransferEvent.progress(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $TransferEvent_ProgressCopyWith<$Res> implements $TransferEventCopyWith<$Res> {
  factory $TransferEvent_ProgressCopyWith(TransferEvent_Progress value, $Res Function(TransferEvent_Progress) _then) = _$TransferEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 Progress field0
});




}
/// @nodoc
class _$TransferEvent_ProgressCopyWithImpl<$Res>
    implements $TransferEvent_ProgressCopyWith<$Res> {
  _$TransferEvent_ProgressCopyWithImpl(this._self, this._then);

  final TransferEvent_Progress _self;
  final $Res Function(TransferEvent_Progress) _then;

/// Create a copy of TransferEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(TransferEvent_Progress(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Progress,
  ));
}


}

/// @nodoc


class TransferEvent_Done extends TransferEvent {
  const TransferEvent_Done(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TransferEvent_Done);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TransferEvent.done()';
}


}




/// @nodoc


class TransferEvent_Failed extends TransferEvent {
  const TransferEvent_Failed(this.field0): super._();
  

 final  CoreError field0;

/// Create a copy of TransferEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransferEvent_FailedCopyWith<TransferEvent_Failed> get copyWith => _$TransferEvent_FailedCopyWithImpl<TransferEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TransferEvent_Failed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'TransferEvent.failed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $TransferEvent_FailedCopyWith<$Res> implements $TransferEventCopyWith<$Res> {
  factory $TransferEvent_FailedCopyWith(TransferEvent_Failed value, $Res Function(TransferEvent_Failed) _then) = _$TransferEvent_FailedCopyWithImpl;
@useResult
$Res call({
 CoreError field0
});


$CoreErrorCopyWith<$Res> get field0;

}
/// @nodoc
class _$TransferEvent_FailedCopyWithImpl<$Res>
    implements $TransferEvent_FailedCopyWith<$Res> {
  _$TransferEvent_FailedCopyWithImpl(this._self, this._then);

  final TransferEvent_Failed _self;
  final $Res Function(TransferEvent_Failed) _then;

/// Create a copy of TransferEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(TransferEvent_Failed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CoreError,
  ));
}

/// Create a copy of TransferEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CoreErrorCopyWith<$Res> get field0 {
  
  return $CoreErrorCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

// dart format on
