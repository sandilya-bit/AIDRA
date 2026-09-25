import 'package:flutter/material.dart';

/// Domain enums shared by data, domain and presentation layers.
/// Values mirror the PostgreSQL enum types in `docs/DATABASE-DESIGN.md` §3
/// so JSON payloads round-trip without translation tables.

enum UserRole { victim, volunteer, ngo, hospital, authority, superAdmin }

extension UserRoleX on UserRole {
  String get key => name;

  String get label => switch (this) {
        UserRole.victim => 'Victim / Citizen',
        UserRole.volunteer => 'Volunteer',
        UserRole.ngo => 'NGO Coordinator',
        UserRole.hospital => 'Hospital Coordinator',
        UserRole.authority => 'Authority / Admin',
        UserRole.superAdmin => 'Super Admin',
      };

  String get shortLabel => switch (this) {
        UserRole.victim => 'Citizen',
        UserRole.volunteer => 'Volunteer',
        UserRole.ngo => 'NGO',
        UserRole.hospital => 'Hospital',
        UserRole.authority => 'Authority',
        UserRole.superAdmin => 'Admin',
      };

  IconData get icon => switch (this) {
        UserRole.victim => Icons.person_outline,
        UserRole.volunteer => Icons.volunteer_activism_outlined,
        UserRole.ngo => Icons.diversity_3_outlined,
        UserRole.hospital => Icons.local_hospital_outlined,
        UserRole.authority => Icons.account_balance_outlined,
        UserRole.superAdmin => Icons.admin_panel_settings_outlined,
      };

  /// Copy shown on the home dashboard header.
  String get greeting => switch (this) {
        UserRole.victim => 'Stay safe. Help when needed.',
        UserRole.volunteer => 'Respond fast. Save lives.',
        UserRole.ngo => 'Coordinate relief operations.',
        UserRole.hospital => 'Track capacity. Prepare for casualties.',
        UserRole.authority => 'Command centre overview.',
        UserRole.superAdmin => 'Platform administration.',
      };

  /// Roles that belong to an organization (PRD §3 role matrix).
  bool get requiresOrganization => switch (this) {
        UserRole.ngo || UserRole.hospital || UserRole.authority => true,
        _ => false,
      };
}

/// Incident/report urgency — the L1–L4 severity framework (PRD Volume II §4).
enum UrgencyLevel { low, medium, high, critical }

extension UrgencyLevelX on UrgencyLevel {
  String get key => name;

  String get label => switch (this) {
        UrgencyLevel.low => 'Low',
        UrgencyLevel.medium => 'Medium',
        UrgencyLevel.high => 'High',
        UrgencyLevel.critical => 'Critical',
      };

  String get level => switch (this) {
        UrgencyLevel.low => 'L1',
        UrgencyLevel.medium => 'L2',
        UrgencyLevel.high => 'L3',
        UrgencyLevel.critical => 'L4',
      };

  int get rank => index;

  Color get color => switch (this) {
        UrgencyLevel.low => const Color(0xFF1DB97A),
        UrgencyLevel.medium => const Color(0xFFF5A623),
        UrgencyLevel.high => const Color(0xFFF03D3D),
        UrgencyLevel.critical => const Color(0xFFB01414),
      };

  /// Golden-hour response target from the severity matrix.
  Duration get responseTarget => switch (this) {
        UrgencyLevel.low => const Duration(hours: 4),
        UrgencyLevel.medium => const Duration(minutes: 30),
        UrgencyLevel.high => const Duration(minutes: 10),
        UrgencyLevel.critical => const Duration(minutes: 5),
      };

  bool get isEmergency => this == UrgencyLevel.high || this == UrgencyLevel.critical;
}

enum ReportInputType { text, voice, image, video }

extension ReportInputTypeX on ReportInputType {
  String get key => name;

  String get label => switch (this) {
        ReportInputType.text => 'Text',
        ReportInputType.voice => 'Voice',
        ReportInputType.image => 'Image',
        ReportInputType.video => 'Video',
      };

  IconData get icon => switch (this) {
        ReportInputType.text => Icons.edit_note_outlined,
        ReportInputType.voice => Icons.mic_none_outlined,
        ReportInputType.image => Icons.image_outlined,
        ReportInputType.video => Icons.videocam_outlined,
      };
}

/// Lifecycle of a locally-created report (offline queue aware).
enum ReportStatus { queued, submitting, submitted, triaged, verified, assigned, resolved, failed }

extension ReportStatusX on ReportStatus {
  String get key => name;

  String get label => switch (this) {
        ReportStatus.queued => 'Queued offline',
        ReportStatus.submitting => 'Submitting…',
        ReportStatus.submitted => 'Submitted',
        ReportStatus.triaged => 'AI triaged',
        ReportStatus.verified => 'Verified',
        ReportStatus.assigned => 'Responder assigned',
        ReportStatus.resolved => 'Resolved',
        ReportStatus.failed => 'Failed — retry',
      };

  Color get color => switch (this) {
        ReportStatus.queued => const Color(0xFFF5A623),
        ReportStatus.submitting => const Color(0xFF1B6FF1),
        ReportStatus.submitted => const Color(0xFF1B6FF1),
        ReportStatus.triaged => const Color(0xFF7C4DFF),
        ReportStatus.verified => const Color(0xFF1DB97A),
        ReportStatus.assigned => const Color(0xFF1DB97A),
        ReportStatus.resolved => const Color(0xFF1DB97A),
        ReportStatus.failed => const Color(0xFFF03D3D),
      };
}

enum IncidentStatus { open, assigned, inProgress, contained, resolved, falseAlarm }

extension IncidentStatusX on IncidentStatus {
  String get key => name;

  String get label => switch (this) {
        IncidentStatus.open => 'Open',
        IncidentStatus.assigned => 'Assigned',
        IncidentStatus.inProgress => 'In progress',
        IncidentStatus.contained => 'Contained',
        IncidentStatus.resolved => 'Resolved',
        IncidentStatus.falseAlarm => 'False alarm',
      };
}

enum AssignmentStatus { offered, accepted, enRoute, onScene, resolved, declined, expired }

extension AssignmentStatusX on AssignmentStatus {
  String get key => name;

  String get label => switch (this) {
        AssignmentStatus.offered => 'Offered',
        AssignmentStatus.accepted => 'Accepted',
        AssignmentStatus.enRoute => 'En route',
        AssignmentStatus.onScene => 'On scene',
        AssignmentStatus.resolved => 'Resolved',
        AssignmentStatus.declined => 'Declined',
        AssignmentStatus.expired => 'Expired',
      };

  Color get color => switch (this) {
        AssignmentStatus.offered => const Color(0xFFF5A623),
        AssignmentStatus.accepted => const Color(0xFF1B6FF1),
        AssignmentStatus.enRoute => const Color(0xFF1B6FF1),
        AssignmentStatus.onScene => const Color(0xFF7C4DFF),
        AssignmentStatus.resolved => const Color(0xFF1DB97A),
        AssignmentStatus.declined => const Color(0xFFB01414),
        AssignmentStatus.expired => const Color(0xFF6B7A90),
      };

  bool get isActive =>
      this == AssignmentStatus.accepted ||
      this == AssignmentStatus.enRoute ||
      this == AssignmentStatus.onScene;
}

enum VolunteerAvailability { available, assigned, enRoute, onScene, offline, unavailable }

extension VolunteerAvailabilityX on VolunteerAvailability {
  String get key => name;

  String get label => switch (this) {
        VolunteerAvailability.available => 'Available',
        VolunteerAvailability.assigned => 'Assigned',
        VolunteerAvailability.enRoute => 'En route',
        VolunteerAvailability.onScene => 'On scene',
        VolunteerAvailability.offline => 'Offline',
        VolunteerAvailability.unavailable => 'Unavailable',
      };

  Color get color => switch (this) {
        VolunteerAvailability.available => const Color(0xFF1DB97A),
        VolunteerAvailability.assigned => const Color(0xFFF5A623),
        VolunteerAvailability.enRoute => const Color(0xFF1B6FF1),
        VolunteerAvailability.onScene => const Color(0xFF7C4DFF),
        VolunteerAvailability.offline => const Color(0xFF6B7A90),
        VolunteerAvailability.unavailable => const Color(0xFF6B7A90),
      };
}

enum ResourceCategory { food, water, medicine, shelter, equipment, fuel, hygiene, other }

extension ResourceCategoryX on ResourceCategory {
  String get key => name;

  String get label => switch (this) {
        ResourceCategory.food => 'Food',
        ResourceCategory.water => 'Water',
        ResourceCategory.medicine => 'Medicine',
        ResourceCategory.shelter => 'Shelter',
        ResourceCategory.equipment => 'Equipment',
        ResourceCategory.fuel => 'Fuel',
        ResourceCategory.hygiene => 'Hygiene',
        ResourceCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        ResourceCategory.food => Icons.rice_bowl_outlined,
        ResourceCategory.water => Icons.water_drop_outlined,
        ResourceCategory.medicine => Icons.medication_outlined,
        ResourceCategory.shelter => Icons.holiday_village_outlined,
        ResourceCategory.equipment => Icons.handyman_outlined,
        ResourceCategory.fuel => Icons.local_gas_station_outlined,
        ResourceCategory.hygiene => Icons.soap_outlined,
        ResourceCategory.other => Icons.inventory_2_outlined,
      };
}

enum RequestStatus { open, approved, dispatched, fulfilled, declined, cancelled }

extension RequestStatusX on RequestStatus {
  String get key => name;
  String get label => switch (this) {
        RequestStatus.open => 'Open',
        RequestStatus.approved => 'Approved',
        RequestStatus.dispatched => 'Dispatched',
        RequestStatus.fulfilled => 'Fulfilled',
        RequestStatus.declined => 'Declined',
        RequestStatus.cancelled => 'Cancelled',
      };
}

/// Escalation priority (PRD Volume II §7.1): P0 bypasses quiet hours.
enum NotificationPriority { p0, p1, p2, p3 }

extension NotificationPriorityX on NotificationPriority {
  String get key => name;
  String get label => name.toUpperCase();
  bool get bypassesQuietHours => this == NotificationPriority.p0 || this == NotificationPriority.p1;
  Color get color => switch (this) {
        NotificationPriority.p0 => const Color(0xFFB01414),
        NotificationPriority.p1 => const Color(0xFFF03D3D),
        NotificationPriority.p2 => const Color(0xFFF5A623),
        NotificationPriority.p3 => const Color(0xFF6B7A90),
      };
}

enum NotificationChannel { push, sms, email, inApp }

extension NotificationChannelX on NotificationChannel {
  String get key => name;
  IconData get icon => switch (this) {
        NotificationChannel.push => Icons.notifications_active_outlined,
        NotificationChannel.sms => Icons.sms_outlined,
        NotificationChannel.email => Icons.mail_outline,
        NotificationChannel.inApp => Icons.inbox_outlined,
      };
}

/// Generic key → enum resolver used by the JSON mappers.
T enumFromKey<T extends Enum>(List<T> values, String? key, T fallback) {
  if (key == null) return fallback;
  for (final T value in values) {
    if (value.name == key) return value;
  }
  return fallback;
}
