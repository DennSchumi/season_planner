import 'dart:convert';

enum NotificationCategory {
  // Mitarbeiter – Einsätze & Planung
  assignmentRequests,
  swapRequests,
  openOpportunities,
  stage1Availability,

  // Mitarbeiter – To-Do & Erinnerungen
  checklistsAndDocs,
  inventoryTodos,
  flightSchoolInvites,

  // Admin-Aufgaben
  adminJoinRequests,
  adminApplicationsAndSwaps,
  adminDocumentsAndQuals,
  adminUnfilledAndChecklists,
}

class NotificationPreferences {
  /// Master-Schalter: Wenn `false`, werden gar keine Benachrichtigungen ausgelöst.
  final bool enabled;

  /// In-App-Banner im Vordergrund anzeigen.
  final bool inAppBanners;

  // Mitarbeiter – Einsätze & Planung
  final bool assignmentRequests;
  final bool swapRequests;
  final bool openOpportunities;
  final bool stage1Availability;

  // Mitarbeiter – To-Do & Erinnerungen
  final bool checklistsAndDocs;
  final bool inventoryTodos;
  final bool flightSchoolInvites;

  // Admin-Meldungen
  final bool adminJoinRequests;
  final bool adminApplicationsAndSwaps;
  final bool adminDocumentsAndQuals;
  final bool adminUnfilledAndChecklists;

  const NotificationPreferences({
    this.enabled = true,
    this.inAppBanners = true,
    this.assignmentRequests = true,
    this.swapRequests = true,
    this.openOpportunities = true,
    this.stage1Availability = true,
    this.checklistsAndDocs = true,
    this.inventoryTodos = true,
    this.flightSchoolInvites = true,
    this.adminJoinRequests = true,
    this.adminApplicationsAndSwaps = true,
    this.adminDocumentsAndQuals = true,
    this.adminUnfilledAndChecklists = true,
  });

  bool isCategoryEnabled(NotificationCategory cat) {
    if (!enabled) return false;
    return switch (cat) {
      NotificationCategory.assignmentRequests => assignmentRequests,
      NotificationCategory.swapRequests => swapRequests,
      NotificationCategory.openOpportunities => openOpportunities,
      NotificationCategory.stage1Availability => stage1Availability,
      NotificationCategory.checklistsAndDocs => checklistsAndDocs,
      NotificationCategory.inventoryTodos => inventoryTodos,
      NotificationCategory.flightSchoolInvites => flightSchoolInvites,
      NotificationCategory.adminJoinRequests => adminJoinRequests,
      NotificationCategory.adminApplicationsAndSwaps =>
        adminApplicationsAndSwaps,
      NotificationCategory.adminDocumentsAndQuals => adminDocumentsAndQuals,
      NotificationCategory.adminUnfilledAndChecklists =>
        adminUnfilledAndChecklists,
    };
  }

  int get activeUserCategoryCount => [
        assignmentRequests,
        swapRequests,
        openOpportunities,
        stage1Availability,
        checklistsAndDocs,
        inventoryTodos,
        flightSchoolInvites,
      ].where((v) => v).length;

  int get activeAdminCategoryCount => [
        adminJoinRequests,
        adminApplicationsAndSwaps,
        adminDocumentsAndQuals,
        adminUnfilledAndChecklists,
      ].where((v) => v).length;

  NotificationPreferences copyWith({
    bool? enabled,
    bool? inAppBanners,
    bool? assignmentRequests,
    bool? swapRequests,
    bool? openOpportunities,
    bool? stage1Availability,
    bool? checklistsAndDocs,
    bool? inventoryTodos,
    bool? flightSchoolInvites,
    bool? adminJoinRequests,
    bool? adminApplicationsAndSwaps,
    bool? adminDocumentsAndQuals,
    bool? adminUnfilledAndChecklists,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      inAppBanners: inAppBanners ?? this.inAppBanners,
      assignmentRequests: assignmentRequests ?? this.assignmentRequests,
      swapRequests: swapRequests ?? this.swapRequests,
      openOpportunities: openOpportunities ?? this.openOpportunities,
      stage1Availability: stage1Availability ?? this.stage1Availability,
      checklistsAndDocs: checklistsAndDocs ?? this.checklistsAndDocs,
      inventoryTodos: inventoryTodos ?? this.inventoryTodos,
      flightSchoolInvites: flightSchoolInvites ?? this.flightSchoolInvites,
      adminJoinRequests: adminJoinRequests ?? this.adminJoinRequests,
      adminApplicationsAndSwaps:
          adminApplicationsAndSwaps ?? this.adminApplicationsAndSwaps,
      adminDocumentsAndQuals:
          adminDocumentsAndQuals ?? this.adminDocumentsAndQuals,
      adminUnfilledAndChecklists:
          adminUnfilledAndChecklists ?? this.adminUnfilledAndChecklists,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'inAppBanners': inAppBanners,
        'assignmentRequests': assignmentRequests,
        'swapRequests': swapRequests,
        'openOpportunities': openOpportunities,
        'stage1Availability': stage1Availability,
        'checklistsAndDocs': checklistsAndDocs,
        'inventoryTodos': inventoryTodos,
        'flightSchoolInvites': flightSchoolInvites,
        'adminJoinRequests': adminJoinRequests,
        'adminApplicationsAndSwaps': adminApplicationsAndSwaps,
        'adminDocumentsAndQuals': adminDocumentsAndQuals,
        'adminUnfilledAndChecklists': adminUnfilledAndChecklists,
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    bool b(String key, [bool fallback = true]) {
      final v = json[key];
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return fallback;
    }

    return NotificationPreferences(
      enabled: b('enabled'),
      inAppBanners: b('inAppBanners'),
      assignmentRequests: b('assignmentRequests'),
      swapRequests: b('swapRequests'),
      openOpportunities: b('openOpportunities'),
      stage1Availability: b('stage1Availability'),
      checklistsAndDocs: b('checklistsAndDocs'),
      inventoryTodos: b('inventoryTodos'),
      flightSchoolInvites: b('flightSchoolInvites'),
      adminJoinRequests: b('adminJoinRequests'),
      adminApplicationsAndSwaps: b('adminApplicationsAndSwaps'),
      adminDocumentsAndQuals: b('adminDocumentsAndQuals'),
      adminUnfilledAndChecklists: b('adminUnfilledAndChecklists'),
    );
  }

  String encode() => jsonEncode(toJson());

  static NotificationPreferences decode(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return NotificationPreferences.fromJson(parsed);
      }
    } catch (_) {}
    return const NotificationPreferences();
  }
}

class AppNotificationEntry {
  final String key;
  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime createdAt;

  const AppNotificationEntry({
    required this.key,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
  });
}
