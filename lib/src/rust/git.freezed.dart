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
mixin _$Auth {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Auth);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Auth()';
}


}

/// @nodoc
class $AuthCopyWith<$Res>  {
$AuthCopyWith(Auth _, $Res Function(Auth) __);
}


/// Adds pattern-matching-related methods to [Auth].
extension AuthPatterns on Auth {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Auth_None value)?  none,TResult Function( Auth_Token value)?  token,TResult Function( Auth_SshKey value)?  sshKey,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Auth_None() when none != null:
return none(_that);case Auth_Token() when token != null:
return token(_that);case Auth_SshKey() when sshKey != null:
return sshKey(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Auth_None value)  none,required TResult Function( Auth_Token value)  token,required TResult Function( Auth_SshKey value)  sshKey,}){
final _that = this;
switch (_that) {
case Auth_None():
return none(_that);case Auth_Token():
return token(_that);case Auth_SshKey():
return sshKey(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Auth_None value)?  none,TResult? Function( Auth_Token value)?  token,TResult? Function( Auth_SshKey value)?  sshKey,}){
final _that = this;
switch (_that) {
case Auth_None() when none != null:
return none(_that);case Auth_Token() when token != null:
return token(_that);case Auth_SshKey() when sshKey != null:
return sshKey(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function( String username,  String token)?  token,TResult Function( String username,  String? publicKey,  String privateKey,  String? passphrase)?  sshKey,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Auth_None() when none != null:
return none();case Auth_Token() when token != null:
return token(_that.username,_that.token);case Auth_SshKey() when sshKey != null:
return sshKey(_that.username,_that.publicKey,_that.privateKey,_that.passphrase);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function( String username,  String token)  token,required TResult Function( String username,  String? publicKey,  String privateKey,  String? passphrase)  sshKey,}) {final _that = this;
switch (_that) {
case Auth_None():
return none();case Auth_Token():
return token(_that.username,_that.token);case Auth_SshKey():
return sshKey(_that.username,_that.publicKey,_that.privateKey,_that.passphrase);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function( String username,  String token)?  token,TResult? Function( String username,  String? publicKey,  String privateKey,  String? passphrase)?  sshKey,}) {final _that = this;
switch (_that) {
case Auth_None() when none != null:
return none();case Auth_Token() when token != null:
return token(_that.username,_that.token);case Auth_SshKey() when sshKey != null:
return sshKey(_that.username,_that.publicKey,_that.privateKey,_that.passphrase);case _:
  return null;

}
}

}

/// @nodoc


class Auth_None extends Auth {
  const Auth_None(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Auth_None);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Auth.none()';
}


}




/// @nodoc


class Auth_Token extends Auth {
  const Auth_Token({required this.username, required this.token}): super._();
  

 final  String username;
 final  String token;

/// Create a copy of Auth
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Auth_TokenCopyWith<Auth_Token> get copyWith => _$Auth_TokenCopyWithImpl<Auth_Token>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Auth_Token&&(identical(other.username, username) || other.username == username)&&(identical(other.token, token) || other.token == token));
}


@override
int get hashCode {
    return Object.hash(runtimeType,username,token);
}

@override
String toString() {
    return 'Auth.token(username: $username, token: $token)';
}


}

/// @nodoc
abstract mixin class $Auth_TokenCopyWith<$Res> implements $AuthCopyWith<$Res> {
  factory $Auth_TokenCopyWith(Auth_Token value, $Res Function(Auth_Token) _then) = _$Auth_TokenCopyWithImpl;
@useResult
$Res call({
 String username, String token
});




}
/// @nodoc
class _$Auth_TokenCopyWithImpl<$Res>
    implements $Auth_TokenCopyWith<$Res> {
  _$Auth_TokenCopyWithImpl(this._self, this._then);

  final Auth_Token _self;
  final $Res Function(Auth_Token) _then;

/// Create a copy of Auth
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? username = null,Object? token = null,}) {
  return _then(Auth_Token(
username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Auth_SshKey extends Auth {
  const Auth_SshKey({required this.username, this.publicKey, required this.privateKey, this.passphrase}): super._();
  

 final  String username;
 final  String? publicKey;
 final  String privateKey;
 final  String? passphrase;

/// Create a copy of Auth
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Auth_SshKeyCopyWith<Auth_SshKey> get copyWith => _$Auth_SshKeyCopyWithImpl<Auth_SshKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Auth_SshKey&&(identical(other.username, username) || other.username == username)&&(identical(other.publicKey, publicKey) || other.publicKey == publicKey)&&(identical(other.privateKey, privateKey) || other.privateKey == privateKey)&&(identical(other.passphrase, passphrase) || other.passphrase == passphrase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,username,publicKey,privateKey,passphrase);
}

@override
String toString() {
    return 'Auth.sshKey(username: $username, publicKey: $publicKey, privateKey: $privateKey, passphrase: $passphrase)';
}


}

/// @nodoc
abstract mixin class $Auth_SshKeyCopyWith<$Res> implements $AuthCopyWith<$Res> {
  factory $Auth_SshKeyCopyWith(Auth_SshKey value, $Res Function(Auth_SshKey) _then) = _$Auth_SshKeyCopyWithImpl;
@useResult
$Res call({
 String username, String? publicKey, String privateKey, String? passphrase
});




}
/// @nodoc
class _$Auth_SshKeyCopyWithImpl<$Res>
    implements $Auth_SshKeyCopyWith<$Res> {
  _$Auth_SshKeyCopyWithImpl(this._self, this._then);

  final Auth_SshKey _self;
  final $Res Function(Auth_SshKey) _then;

/// Create a copy of Auth
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? username = null,Object? publicKey = freezed,Object? privateKey = null,Object? passphrase = freezed,}) {
  return _then(Auth_SshKey(
username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,publicKey: freezed == publicKey ? _self.publicKey : publicKey // ignore: cast_nullable_to_non_nullable
as String?,privateKey: null == privateKey ? _self.privateKey : privateKey // ignore: cast_nullable_to_non_nullable
as String,passphrase: freezed == passphrase ? _self.passphrase : passphrase // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$CoreError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError()';
}


}

/// @nodoc
class $CoreErrorCopyWith<$Res>  {
$CoreErrorCopyWith(CoreError _, $Res Function(CoreError) __);
}


/// Adds pattern-matching-related methods to [CoreError].
extension CoreErrorPatterns on CoreError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreError_HostKeyUnknown value)?  hostKeyUnknown,TResult Function( CoreError_AuthFailed value)?  authFailed,TResult Function( CoreError_Cancelled value)?  cancelled,TResult Function( CoreError_InvalidPath value)?  invalidPath,TResult Function( CoreError_InvalidArgument value)?  invalidArgument,TResult Function( CoreError_Git value)?  git,TResult Function( CoreError_Io value)?  io,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that);case CoreError_AuthFailed() when authFailed != null:
return authFailed(_that);case CoreError_Cancelled() when cancelled != null:
return cancelled(_that);case CoreError_InvalidPath() when invalidPath != null:
return invalidPath(_that);case CoreError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that);case CoreError_Git() when git != null:
return git(_that);case CoreError_Io() when io != null:
return io(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreError_HostKeyUnknown value)  hostKeyUnknown,required TResult Function( CoreError_AuthFailed value)  authFailed,required TResult Function( CoreError_Cancelled value)  cancelled,required TResult Function( CoreError_InvalidPath value)  invalidPath,required TResult Function( CoreError_InvalidArgument value)  invalidArgument,required TResult Function( CoreError_Git value)  git,required TResult Function( CoreError_Io value)  io,}){
final _that = this;
switch (_that) {
case CoreError_HostKeyUnknown():
return hostKeyUnknown(_that);case CoreError_AuthFailed():
return authFailed(_that);case CoreError_Cancelled():
return cancelled(_that);case CoreError_InvalidPath():
return invalidPath(_that);case CoreError_InvalidArgument():
return invalidArgument(_that);case CoreError_Git():
return git(_that);case CoreError_Io():
return io(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreError_HostKeyUnknown value)?  hostKeyUnknown,TResult? Function( CoreError_AuthFailed value)?  authFailed,TResult? Function( CoreError_Cancelled value)?  cancelled,TResult? Function( CoreError_InvalidPath value)?  invalidPath,TResult? Function( CoreError_InvalidArgument value)?  invalidArgument,TResult? Function( CoreError_Git value)?  git,TResult? Function( CoreError_Io value)?  io,}){
final _that = this;
switch (_that) {
case CoreError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that);case CoreError_AuthFailed() when authFailed != null:
return authFailed(_that);case CoreError_Cancelled() when cancelled != null:
return cancelled(_that);case CoreError_InvalidPath() when invalidPath != null:
return invalidPath(_that);case CoreError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that);case CoreError_Git() when git != null:
return git(_that);case CoreError_Io() when io != null:
return io(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String host,  String fingerprint)?  hostKeyUnknown,TResult Function( String message)?  authFailed,TResult Function()?  cancelled,TResult Function( String path)?  invalidPath,TResult Function( String message)?  invalidArgument,TResult Function( int code,  int class_,  String message)?  git,TResult Function( String message)?  io,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that.host,_that.fingerprint);case CoreError_AuthFailed() when authFailed != null:
return authFailed(_that.message);case CoreError_Cancelled() when cancelled != null:
return cancelled();case CoreError_InvalidPath() when invalidPath != null:
return invalidPath(_that.path);case CoreError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that.message);case CoreError_Git() when git != null:
return git(_that.code,_that.class_,_that.message);case CoreError_Io() when io != null:
return io(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String host,  String fingerprint)  hostKeyUnknown,required TResult Function( String message)  authFailed,required TResult Function()  cancelled,required TResult Function( String path)  invalidPath,required TResult Function( String message)  invalidArgument,required TResult Function( int code,  int class_,  String message)  git,required TResult Function( String message)  io,}) {final _that = this;
switch (_that) {
case CoreError_HostKeyUnknown():
return hostKeyUnknown(_that.host,_that.fingerprint);case CoreError_AuthFailed():
return authFailed(_that.message);case CoreError_Cancelled():
return cancelled();case CoreError_InvalidPath():
return invalidPath(_that.path);case CoreError_InvalidArgument():
return invalidArgument(_that.message);case CoreError_Git():
return git(_that.code,_that.class_,_that.message);case CoreError_Io():
return io(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String host,  String fingerprint)?  hostKeyUnknown,TResult? Function( String message)?  authFailed,TResult? Function()?  cancelled,TResult? Function( String path)?  invalidPath,TResult? Function( String message)?  invalidArgument,TResult? Function( int code,  int class_,  String message)?  git,TResult? Function( String message)?  io,}) {final _that = this;
switch (_that) {
case CoreError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that.host,_that.fingerprint);case CoreError_AuthFailed() when authFailed != null:
return authFailed(_that.message);case CoreError_Cancelled() when cancelled != null:
return cancelled();case CoreError_InvalidPath() when invalidPath != null:
return invalidPath(_that.path);case CoreError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that.message);case CoreError_Git() when git != null:
return git(_that.code,_that.class_,_that.message);case CoreError_Io() when io != null:
return io(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class CoreError_HostKeyUnknown extends CoreError {
  const CoreError_HostKeyUnknown({required this.host, required this.fingerprint}): super._();
  

 final  String host;
 final  String fingerprint;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_HostKeyUnknownCopyWith<CoreError_HostKeyUnknown> get copyWith => _$CoreError_HostKeyUnknownCopyWithImpl<CoreError_HostKeyUnknown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_HostKeyUnknown&&(identical(other.host, host) || other.host == host)&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint));
}


@override
int get hashCode {
    return Object.hash(runtimeType,host,fingerprint);
}

@override
String toString() {
    return 'CoreError.hostKeyUnknown(host: $host, fingerprint: $fingerprint)';
}


}

/// @nodoc
abstract mixin class $CoreError_HostKeyUnknownCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_HostKeyUnknownCopyWith(CoreError_HostKeyUnknown value, $Res Function(CoreError_HostKeyUnknown) _then) = _$CoreError_HostKeyUnknownCopyWithImpl;
@useResult
$Res call({
 String host, String fingerprint
});




}
/// @nodoc
class _$CoreError_HostKeyUnknownCopyWithImpl<$Res>
    implements $CoreError_HostKeyUnknownCopyWith<$Res> {
  _$CoreError_HostKeyUnknownCopyWithImpl(this._self, this._then);

  final CoreError_HostKeyUnknown _self;
  final $Res Function(CoreError_HostKeyUnknown) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? fingerprint = null,}) {
  return _then(CoreError_HostKeyUnknown(
host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_AuthFailed extends CoreError {
  const CoreError_AuthFailed({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_AuthFailedCopyWith<CoreError_AuthFailed> get copyWith => _$CoreError_AuthFailedCopyWithImpl<CoreError_AuthFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_AuthFailed&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.authFailed(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_AuthFailedCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_AuthFailedCopyWith(CoreError_AuthFailed value, $Res Function(CoreError_AuthFailed) _then) = _$CoreError_AuthFailedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_AuthFailedCopyWithImpl<$Res>
    implements $CoreError_AuthFailedCopyWith<$Res> {
  _$CoreError_AuthFailedCopyWithImpl(this._self, this._then);

  final CoreError_AuthFailed _self;
  final $Res Function(CoreError_AuthFailed) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_AuthFailed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Cancelled extends CoreError {
  const CoreError_Cancelled(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.cancelled()';
}


}




/// @nodoc


class CoreError_InvalidPath extends CoreError {
  const CoreError_InvalidPath({required this.path}): super._();
  

 final  String path;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InvalidPathCopyWith<CoreError_InvalidPath> get copyWith => _$CoreError_InvalidPathCopyWithImpl<CoreError_InvalidPath>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_InvalidPath&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}

@override
String toString() {
    return 'CoreError.invalidPath(path: $path)';
}


}

/// @nodoc
abstract mixin class $CoreError_InvalidPathCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InvalidPathCopyWith(CoreError_InvalidPath value, $Res Function(CoreError_InvalidPath) _then) = _$CoreError_InvalidPathCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$CoreError_InvalidPathCopyWithImpl<$Res>
    implements $CoreError_InvalidPathCopyWith<$Res> {
  _$CoreError_InvalidPathCopyWithImpl(this._self, this._then);

  final CoreError_InvalidPath _self;
  final $Res Function(CoreError_InvalidPath) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(CoreError_InvalidPath(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_InvalidArgument extends CoreError {
  const CoreError_InvalidArgument({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InvalidArgumentCopyWith<CoreError_InvalidArgument> get copyWith => _$CoreError_InvalidArgumentCopyWithImpl<CoreError_InvalidArgument>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_InvalidArgument&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.invalidArgument(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_InvalidArgumentCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InvalidArgumentCopyWith(CoreError_InvalidArgument value, $Res Function(CoreError_InvalidArgument) _then) = _$CoreError_InvalidArgumentCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_InvalidArgumentCopyWithImpl<$Res>
    implements $CoreError_InvalidArgumentCopyWith<$Res> {
  _$CoreError_InvalidArgumentCopyWithImpl(this._self, this._then);

  final CoreError_InvalidArgument _self;
  final $Res Function(CoreError_InvalidArgument) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_InvalidArgument(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Git extends CoreError {
  const CoreError_Git({required this.code, required this.class_, required this.message}): super._();
  

 final  int code;
 final  int class_;
 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_GitCopyWith<CoreError_Git> get copyWith => _$CoreError_GitCopyWithImpl<CoreError_Git>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Git&&(identical(other.code, code) || other.code == code)&&(identical(other.class_, class_) || other.class_ == class_)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,class_,message);
}

@override
String toString() {
    return 'CoreError.git(code: $code, class_: $class_, message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_GitCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_GitCopyWith(CoreError_Git value, $Res Function(CoreError_Git) _then) = _$CoreError_GitCopyWithImpl;
@useResult
$Res call({
 int code, int class_, String message
});




}
/// @nodoc
class _$CoreError_GitCopyWithImpl<$Res>
    implements $CoreError_GitCopyWith<$Res> {
  _$CoreError_GitCopyWithImpl(this._self, this._then);

  final CoreError_Git _self;
  final $Res Function(CoreError_Git) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? class_ = null,Object? message = null,}) {
  return _then(CoreError_Git(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int,class_: null == class_ ? _self.class_ : class_ // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Io extends CoreError {
  const CoreError_Io({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_IoCopyWith<CoreError_Io> get copyWith => _$CoreError_IoCopyWithImpl<CoreError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Io&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.io(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_IoCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_IoCopyWith(CoreError_Io value, $Res Function(CoreError_Io) _then) = _$CoreError_IoCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_IoCopyWithImpl<$Res>
    implements $CoreError_IoCopyWith<$Res> {
  _$CoreError_IoCopyWithImpl(this._self, this._then);

  final CoreError_Io _self;
  final $Res Function(CoreError_Io) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_Io(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$PushOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PushOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PushOutcome()';
}


}

/// @nodoc
class $PushOutcomeCopyWith<$Res>  {
$PushOutcomeCopyWith(PushOutcome _, $Res Function(PushOutcome) __);
}


/// Adds pattern-matching-related methods to [PushOutcome].
extension PushOutcomePatterns on PushOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PushOutcome_Pushed value)?  pushed,TResult Function( PushOutcome_UpToDate value)?  upToDate,TResult Function( PushOutcome_Rejected value)?  rejected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PushOutcome_Pushed() when pushed != null:
return pushed(_that);case PushOutcome_UpToDate() when upToDate != null:
return upToDate(_that);case PushOutcome_Rejected() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PushOutcome_Pushed value)  pushed,required TResult Function( PushOutcome_UpToDate value)  upToDate,required TResult Function( PushOutcome_Rejected value)  rejected,}){
final _that = this;
switch (_that) {
case PushOutcome_Pushed():
return pushed(_that);case PushOutcome_UpToDate():
return upToDate(_that);case PushOutcome_Rejected():
return rejected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PushOutcome_Pushed value)?  pushed,TResult? Function( PushOutcome_UpToDate value)?  upToDate,TResult? Function( PushOutcome_Rejected value)?  rejected,}){
final _that = this;
switch (_that) {
case PushOutcome_Pushed() when pushed != null:
return pushed(_that);case PushOutcome_UpToDate() when upToDate != null:
return upToDate(_that);case PushOutcome_Rejected() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  pushed,TResult Function()?  upToDate,TResult Function( String reason)?  rejected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PushOutcome_Pushed() when pushed != null:
return pushed();case PushOutcome_UpToDate() when upToDate != null:
return upToDate();case PushOutcome_Rejected() when rejected != null:
return rejected(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  pushed,required TResult Function()  upToDate,required TResult Function( String reason)  rejected,}) {final _that = this;
switch (_that) {
case PushOutcome_Pushed():
return pushed();case PushOutcome_UpToDate():
return upToDate();case PushOutcome_Rejected():
return rejected(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  pushed,TResult? Function()?  upToDate,TResult? Function( String reason)?  rejected,}) {final _that = this;
switch (_that) {
case PushOutcome_Pushed() when pushed != null:
return pushed();case PushOutcome_UpToDate() when upToDate != null:
return upToDate();case PushOutcome_Rejected() when rejected != null:
return rejected(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class PushOutcome_Pushed extends PushOutcome {
  const PushOutcome_Pushed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PushOutcome_Pushed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PushOutcome.pushed()';
}


}




/// @nodoc


class PushOutcome_UpToDate extends PushOutcome {
  const PushOutcome_UpToDate(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PushOutcome_UpToDate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PushOutcome.upToDate()';
}


}




/// @nodoc


class PushOutcome_Rejected extends PushOutcome {
  const PushOutcome_Rejected({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of PushOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PushOutcome_RejectedCopyWith<PushOutcome_Rejected> get copyWith => _$PushOutcome_RejectedCopyWithImpl<PushOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PushOutcome_Rejected&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'PushOutcome.rejected(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $PushOutcome_RejectedCopyWith<$Res> implements $PushOutcomeCopyWith<$Res> {
  factory $PushOutcome_RejectedCopyWith(PushOutcome_Rejected value, $Res Function(PushOutcome_Rejected) _then) = _$PushOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$PushOutcome_RejectedCopyWithImpl<$Res>
    implements $PushOutcome_RejectedCopyWith<$Res> {
  _$PushOutcome_RejectedCopyWithImpl(this._self, this._then);

  final PushOutcome_Rejected _self;
  final $Res Function(PushOutcome_Rejected) _then;

/// Create a copy of PushOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(PushOutcome_Rejected(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RebaseOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RebaseOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RebaseOutcome()';
}


}

/// @nodoc
class $RebaseOutcomeCopyWith<$Res>  {
$RebaseOutcomeCopyWith(RebaseOutcome _, $Res Function(RebaseOutcome) __);
}


/// Adds pattern-matching-related methods to [RebaseOutcome].
extension RebaseOutcomePatterns on RebaseOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RebaseOutcome_UpToDate value)?  upToDate,TResult Function( RebaseOutcome_FastForwarded value)?  fastForwarded,TResult Function( RebaseOutcome_Rebased value)?  rebased,TResult Function( RebaseOutcome_Conflicts value)?  conflicts,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RebaseOutcome_UpToDate() when upToDate != null:
return upToDate(_that);case RebaseOutcome_FastForwarded() when fastForwarded != null:
return fastForwarded(_that);case RebaseOutcome_Rebased() when rebased != null:
return rebased(_that);case RebaseOutcome_Conflicts() when conflicts != null:
return conflicts(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RebaseOutcome_UpToDate value)  upToDate,required TResult Function( RebaseOutcome_FastForwarded value)  fastForwarded,required TResult Function( RebaseOutcome_Rebased value)  rebased,required TResult Function( RebaseOutcome_Conflicts value)  conflicts,}){
final _that = this;
switch (_that) {
case RebaseOutcome_UpToDate():
return upToDate(_that);case RebaseOutcome_FastForwarded():
return fastForwarded(_that);case RebaseOutcome_Rebased():
return rebased(_that);case RebaseOutcome_Conflicts():
return conflicts(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RebaseOutcome_UpToDate value)?  upToDate,TResult? Function( RebaseOutcome_FastForwarded value)?  fastForwarded,TResult? Function( RebaseOutcome_Rebased value)?  rebased,TResult? Function( RebaseOutcome_Conflicts value)?  conflicts,}){
final _that = this;
switch (_that) {
case RebaseOutcome_UpToDate() when upToDate != null:
return upToDate(_that);case RebaseOutcome_FastForwarded() when fastForwarded != null:
return fastForwarded(_that);case RebaseOutcome_Rebased() when rebased != null:
return rebased(_that);case RebaseOutcome_Conflicts() when conflicts != null:
return conflicts(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  upToDate,TResult Function( String commit)?  fastForwarded,TResult Function( String commit,  int commits)?  rebased,TResult Function( String commit,  List<Conflict> conflicts)?  conflicts,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RebaseOutcome_UpToDate() when upToDate != null:
return upToDate();case RebaseOutcome_FastForwarded() when fastForwarded != null:
return fastForwarded(_that.commit);case RebaseOutcome_Rebased() when rebased != null:
return rebased(_that.commit,_that.commits);case RebaseOutcome_Conflicts() when conflicts != null:
return conflicts(_that.commit,_that.conflicts);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  upToDate,required TResult Function( String commit)  fastForwarded,required TResult Function( String commit,  int commits)  rebased,required TResult Function( String commit,  List<Conflict> conflicts)  conflicts,}) {final _that = this;
switch (_that) {
case RebaseOutcome_UpToDate():
return upToDate();case RebaseOutcome_FastForwarded():
return fastForwarded(_that.commit);case RebaseOutcome_Rebased():
return rebased(_that.commit,_that.commits);case RebaseOutcome_Conflicts():
return conflicts(_that.commit,_that.conflicts);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  upToDate,TResult? Function( String commit)?  fastForwarded,TResult? Function( String commit,  int commits)?  rebased,TResult? Function( String commit,  List<Conflict> conflicts)?  conflicts,}) {final _that = this;
switch (_that) {
case RebaseOutcome_UpToDate() when upToDate != null:
return upToDate();case RebaseOutcome_FastForwarded() when fastForwarded != null:
return fastForwarded(_that.commit);case RebaseOutcome_Rebased() when rebased != null:
return rebased(_that.commit,_that.commits);case RebaseOutcome_Conflicts() when conflicts != null:
return conflicts(_that.commit,_that.conflicts);case _:
  return null;

}
}

}

/// @nodoc


class RebaseOutcome_UpToDate extends RebaseOutcome {
  const RebaseOutcome_UpToDate(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RebaseOutcome_UpToDate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RebaseOutcome.upToDate()';
}


}




/// @nodoc


class RebaseOutcome_FastForwarded extends RebaseOutcome {
  const RebaseOutcome_FastForwarded({required this.commit}): super._();
  

 final  String commit;

/// Create a copy of RebaseOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RebaseOutcome_FastForwardedCopyWith<RebaseOutcome_FastForwarded> get copyWith => _$RebaseOutcome_FastForwardedCopyWithImpl<RebaseOutcome_FastForwarded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RebaseOutcome_FastForwarded&&(identical(other.commit, commit) || other.commit == commit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,commit);
}

@override
String toString() {
    return 'RebaseOutcome.fastForwarded(commit: $commit)';
}


}

/// @nodoc
abstract mixin class $RebaseOutcome_FastForwardedCopyWith<$Res> implements $RebaseOutcomeCopyWith<$Res> {
  factory $RebaseOutcome_FastForwardedCopyWith(RebaseOutcome_FastForwarded value, $Res Function(RebaseOutcome_FastForwarded) _then) = _$RebaseOutcome_FastForwardedCopyWithImpl;
@useResult
$Res call({
 String commit
});




}
/// @nodoc
class _$RebaseOutcome_FastForwardedCopyWithImpl<$Res>
    implements $RebaseOutcome_FastForwardedCopyWith<$Res> {
  _$RebaseOutcome_FastForwardedCopyWithImpl(this._self, this._then);

  final RebaseOutcome_FastForwarded _self;
  final $Res Function(RebaseOutcome_FastForwarded) _then;

/// Create a copy of RebaseOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? commit = null,}) {
  return _then(RebaseOutcome_FastForwarded(
commit: null == commit ? _self.commit : commit // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RebaseOutcome_Rebased extends RebaseOutcome {
  const RebaseOutcome_Rebased({required this.commit, required this.commits}): super._();
  

 final  String commit;
 final  int commits;

/// Create a copy of RebaseOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RebaseOutcome_RebasedCopyWith<RebaseOutcome_Rebased> get copyWith => _$RebaseOutcome_RebasedCopyWithImpl<RebaseOutcome_Rebased>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RebaseOutcome_Rebased&&(identical(other.commit, commit) || other.commit == commit)&&(identical(other.commits, commits) || other.commits == commits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,commit,commits);
}

@override
String toString() {
    return 'RebaseOutcome.rebased(commit: $commit, commits: $commits)';
}


}

/// @nodoc
abstract mixin class $RebaseOutcome_RebasedCopyWith<$Res> implements $RebaseOutcomeCopyWith<$Res> {
  factory $RebaseOutcome_RebasedCopyWith(RebaseOutcome_Rebased value, $Res Function(RebaseOutcome_Rebased) _then) = _$RebaseOutcome_RebasedCopyWithImpl;
@useResult
$Res call({
 String commit, int commits
});




}
/// @nodoc
class _$RebaseOutcome_RebasedCopyWithImpl<$Res>
    implements $RebaseOutcome_RebasedCopyWith<$Res> {
  _$RebaseOutcome_RebasedCopyWithImpl(this._self, this._then);

  final RebaseOutcome_Rebased _self;
  final $Res Function(RebaseOutcome_Rebased) _then;

/// Create a copy of RebaseOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? commit = null,Object? commits = null,}) {
  return _then(RebaseOutcome_Rebased(
commit: null == commit ? _self.commit : commit // ignore: cast_nullable_to_non_nullable
as String,commits: null == commits ? _self.commits : commits // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RebaseOutcome_Conflicts extends RebaseOutcome {
  const RebaseOutcome_Conflicts({required this.commit, required  List<Conflict> conflicts}): _conflicts = conflicts,super._();
  

 final  String commit;
 final  List<Conflict> _conflicts;
 List<Conflict> get conflicts {
  if (_conflicts is EqualUnmodifiableListView) return _conflicts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_conflicts);
}


/// Create a copy of RebaseOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RebaseOutcome_ConflictsCopyWith<RebaseOutcome_Conflicts> get copyWith => _$RebaseOutcome_ConflictsCopyWithImpl<RebaseOutcome_Conflicts>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RebaseOutcome_Conflicts&&(identical(other.commit, commit) || other.commit == commit)&&const DeepCollectionEquality().equals(other.conflicts, _conflicts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,commit,const DeepCollectionEquality().hash(_conflicts));
}

@override
String toString() {
    return 'RebaseOutcome.conflicts(commit: $commit, conflicts: $conflicts)';
}


}

/// @nodoc
abstract mixin class $RebaseOutcome_ConflictsCopyWith<$Res> implements $RebaseOutcomeCopyWith<$Res> {
  factory $RebaseOutcome_ConflictsCopyWith(RebaseOutcome_Conflicts value, $Res Function(RebaseOutcome_Conflicts) _then) = _$RebaseOutcome_ConflictsCopyWithImpl;
@useResult
$Res call({
 String commit, List<Conflict> conflicts
});




}
/// @nodoc
class _$RebaseOutcome_ConflictsCopyWithImpl<$Res>
    implements $RebaseOutcome_ConflictsCopyWith<$Res> {
  _$RebaseOutcome_ConflictsCopyWithImpl(this._self, this._then);

  final RebaseOutcome_Conflicts _self;
  final $Res Function(RebaseOutcome_Conflicts) _then;

/// Create a copy of RebaseOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? commit = null,Object? conflicts = null,}) {
  return _then(RebaseOutcome_Conflicts(
commit: null == commit ? _self.commit : commit // ignore: cast_nullable_to_non_nullable
as String,conflicts: null == conflicts ? _self._conflicts : conflicts // ignore: cast_nullable_to_non_nullable
as List<Conflict>,
  ));
}


}

// dart format on
