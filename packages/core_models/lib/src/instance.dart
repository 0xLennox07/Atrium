import 'package:freezed_annotation/freezed_annotation.dart';

import 'instance_auth.dart';
import 'service_kind.dart';
import 'url_mode.dart';

part 'instance.freezed.dart';
part 'instance.g.dart';

/// One configured connection to a self-hosted service.
///
/// An instance is what the user adds when they "add a Sonarr" - it carries
/// the URLs to reach that Sonarr, the auth material to authenticate against
/// it, and a few preferences (URL mode, TLS leniency).
///
/// Users may have multiple instances of the same [kind] (e.g., two Sonarrs:
/// "Home" and "Seedbox"); each is a separate [Instance] with its own [id].
@freezed
abstract class Instance with _$Instance {
  const factory Instance({
    /// Stable identifier, generated once at create time. Used as the key for
    /// secret storage and Riverpod scoping. Never reuse.
    required String id,

    /// Display name shown in lists and the title bar. Free-form.
    required String name,

    /// What service this instance speaks to.
    required ServiceKind kind,

    /// URL reachable from the home LAN (e.g., `http://192.168.1.10:8989`).
    /// May be empty if the user only has remote access.
    required String localUrl,

    /// URL reachable from outside the LAN (e.g., `https://sonarr.example.com`).
    /// May be empty if the user only ever uses the LAN URL.
    required String externalUrl,

    /// Routing strategy between [localUrl] and [externalUrl].
    required UrlMode urlMode,

    /// Auth material. See [InstanceAuth].
    required InstanceAuth auth,

    /// Accept self-signed TLS certificates. Off by default - turning this on
    /// is the user explicitly opting out of cert validation for this
    /// instance only.
    @Default(false) bool allowSelfSignedCerts,

    /// How frequently this instance should be polled by the dashboard/widgets.
    /// Used by services that need high frequency updates like Glances.
    @Default(5) int pollingIntervalSeconds,
  }) = _Instance;

  factory Instance.fromJson(Map<String, dynamic> json) =>
      _$InstanceFromJson(json);
}
