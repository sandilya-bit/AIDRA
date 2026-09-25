import '../constants/app_enums.dart';

/// Things a signed-in user may attempt.
///
/// This is **navigation and affordance policy only**. The authoritative
/// enforcement lives in the database as row-level security policies
/// (`docs/DATABASE-DESIGN.md` §13) and in the API's middleware. Hiding a
/// destination the server would reject is UX; it is not a security control.
enum Permission {
  /// File an emergency report (any authenticated account).
  reportEmergency,

  /// See the live operational map.
  viewLiveMap,

  /// Read and follow up on one's own reports.
  manageOwnReports,

  /// Accept / progress a dispatch assignment.
  respondToAssignments,

  /// Toggle volunteer availability.
  manageAvailability,

  /// Deploy field teams and see area coverage overlaps.
  coordinateNgoTeams,

  /// Edit bed / ICU / oxygen / blood capacity and acknowledge pre-alerts.
  manageHospitalCapacity,

  /// Move inventory and act on inter-org resource requests.
  manageResources,

  /// Authority command-centre overview across every agency.
  viewCommandCentre,

  /// Send a public broadcast alert.
  broadcastAlert,

  /// Approve or suspend organisation accounts.
  verifyOrganisations,

  /// Platform-wide administration.
  administerPlatform,
}

/// Role → permission matrix, mirroring the PRD role matrix and the RLS policy
/// table so the client and the database agree on who does what.
abstract final class RolePolicy {
  static const Set<Permission> _victim = <Permission>{
    Permission.reportEmergency,
    Permission.viewLiveMap,
    Permission.manageOwnReports,
  };

  static const Set<Permission> _volunteer = <Permission>{
    Permission.reportEmergency,
    Permission.viewLiveMap,
    Permission.manageOwnReports,
    Permission.respondToAssignments,
    Permission.manageAvailability,
  };

  static const Set<Permission> _ngo = <Permission>{
    Permission.reportEmergency,
    Permission.viewLiveMap,
    Permission.respondToAssignments,
    Permission.manageAvailability,
    Permission.coordinateNgoTeams,
    Permission.manageResources,
  };

  static const Set<Permission> _hospital = <Permission>{
    Permission.reportEmergency,
    Permission.viewLiveMap,
    Permission.manageHospitalCapacity,
    Permission.manageResources,
  };

  static const Set<Permission> _authority = <Permission>{
    Permission.reportEmergency,
    Permission.viewLiveMap,
    Permission.manageOwnReports,
    Permission.manageResources,
    Permission.viewCommandCentre,
    Permission.broadcastAlert,
    Permission.verifyOrganisations,
  };

  static const Set<Permission> _superAdmin = <Permission>{
    Permission.reportEmergency,
    Permission.viewLiveMap,
    Permission.manageOwnReports,
    Permission.respondToAssignments,
    Permission.manageAvailability,
    Permission.coordinateNgoTeams,
    Permission.manageHospitalCapacity,
    Permission.manageResources,
    Permission.viewCommandCentre,
    Permission.broadcastAlert,
    Permission.verifyOrganisations,
    Permission.administerPlatform,
  };

  static Set<Permission> permissionsOf(UserRole role) => switch (role) {
        UserRole.victim => _victim,
        UserRole.volunteer => _volunteer,
        UserRole.ngo => _ngo,
        UserRole.hospital => _hospital,
        UserRole.authority => _authority,
        UserRole.superAdmin => _superAdmin,
      };

  static bool can(UserRole role, Permission permission) =>
      permissionsOf(role).contains(permission);

  // ------------------------------------------------------------ route guards

  /// Screens that are not for every role. Unlisted prefixes are open to any
  /// authenticated user (home, map, reports, notifications, profile).
  static const Map<String, Set<UserRole>> guardedRoutes = <String, Set<UserRole>>{
    '/hospital': <UserRole>{UserRole.hospital, UserRole.authority, UserRole.superAdmin},
    '/ngo': <UserRole>{UserRole.ngo, UserRole.authority, UserRole.superAdmin},
    '/resources': <UserRole>{
      UserRole.ngo,
      UserRole.hospital,
      UserRole.authority,
      UserRole.superAdmin,
    },
    '/volunteers': <UserRole>{
      UserRole.victim,
      UserRole.volunteer,
      UserRole.ngo,
      UserRole.authority,
      UserRole.superAdmin,
    },
  };

  /// The guarded prefix matching [location], or null when unguarded.
  static String? guardFor(String location) {
    for (final String prefix in guardedRoutes.keys) {
      if (location == prefix || location.startsWith('$prefix/')) return prefix;
    }
    return null;
  }

  static bool canAccessRoute(UserRole role, String location) {
    final String? prefix = guardFor(location);
    if (prefix == null) return true;
    return guardedRoutes[prefix]!.contains(role);
  }

  /// Roles allowed into [location], for the "who can go here" copy.
  static Set<UserRole> rolesFor(String location) {
    final String? prefix = guardFor(location);
    return prefix == null ? UserRole.values.toSet() : guardedRoutes[prefix]!;
  }

  // ------------------------------------------------------- role resolution

  /// The role the app should act as.
  ///
  /// The role inside the server-signed access token always wins: a client can
  /// *request* a role at sign-up, but only the backend can *grant* one. The
  /// locally selected role is used before sign-in (or in demo mode) purely so
  /// the right dashboard can be reviewed.
  static UserRole resolveRole({
    required UserRole requested,
    String? tokenRole,
    bool trustRequested = true,
  }) {
    final UserRole? claimed = roleFromKey(tokenRole);
    if (claimed != null) return claimed;
    return trustRequested ? requested : UserRole.victim;
  }

  /// Map a claim value onto a role, or null when it is unknown.
  ///
  /// Tolerates the snake_case spelling (`super_admin`) the PostgreSQL enum uses
  /// so a token minted straight from the database schema still resolves.
  static UserRole? roleFromKey(String? key) {
    if (key == null) return null;
    final String normalised = key.trim().toLowerCase();
    if (normalised.isEmpty) return null;
    if (normalised == 'super_admin' || normalised == 'superadmin') {
      return UserRole.superAdmin;
    }
    for (final UserRole role in UserRole.values) {
      if (role.name.toLowerCase() == normalised) return role;
    }
    return null;
  }
}
