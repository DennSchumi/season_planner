import 'dart:core';

class AppwriteConfig {
  String appwriteEnpoint = const String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: "https://appwrite.tragegurt.com/v1",
  );
  String projectId = const String.fromEnvironment(
    'APPWRITE_PROJECT_ID',
    defaultValue: "tragegurt",
  );

  // Basis-URL für Passwort-Reset & ICS-Abo-Feed
  String webBaseUrl = const String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: "https://planner.tragegurt.com",
  );
  String icsFeedBaseUrl = const String.fromEnvironment(
    'ICS_FEED_URL',
    defaultValue: "https://ics.tragegurt.com",
  );
  String inventoryWebUrl = const String.fromEnvironment(
    'INVENTORY_WEB_URL',
    defaultValue: "https://inventar.tragegurt.com",
  );

  // Zentrale Rechtsseiten auf der Tragegurt-Produktwebsite
  String legalImprintUrl = const String.fromEnvironment(
    'LEGAL_IMPRINT_URL',
    defaultValue: "https://tragegurt.com/impressum",
  );
  String legalPrivacyUrl = const String.fromEnvironment(
    'LEGAL_PRIVACY_URL',
    defaultValue: "https://tragegurt.com/datenschutz",
  );
  String legalTermsUrl = const String.fromEnvironment(
    'LEGAL_TERMS_URL',
    defaultValue: "https://tragegurt.com/agb",
  );

  // Shared Core DB (core_db)
  String mainDatabaseId = "core_db";
  String usersCollectionID = "users";
  String flightSchoolsCollectionId = "flight_schools";
  String membershipsId = "memberships";
  String teamRolesTableId = "team_roles";
  String qualificationsTableId = "qualifications";
  String qualificationDocumentsTableId = "qualification_documents";
  String qualificationApprovalsTableId = "qualification_approvals";

  // Season Planner DB (season_planner_db)
  String seasonPlannerDatabaseId = "season_planner_db";
  String eventsTableId = "events";
  String teamAssignmentsEventsTableId = "team_assignments_events";
  String auditLogsTableId = "audit_logs";
  String planningPeriodsTableId = "planning_periods";
  String availabilitySubmissionsTableId = "availability_submissions";
  String roleDocumentsTableId = "role_documents";
  String checklistCompletionsTableId = "checklist_completions";
  String eventTemplatesTableId = "event_templates";
  String tandemDutiesTableId = "tandem_duties";
  String tandemDemandsTableId = "tandem_demands";
  String eventTimesheetsTableId = "event_timesheets";

  // Inventory Manager DB (inventory_db) – gemeinsame Appwrite-Instanz
  String inventoryDatabaseId = "inventory_db";
  String inventoryCategoriesTableId = "categories";
  String inventoryItemsTableId = "items";
  String inventoryTransactionsTableId = "transactions";

  // Storage Buckets
  String flightSchoolLogosId = "flight_school_logos";
  String qualificationDocumentsBucketId = "qualification_documents";
  String instructionAssetsBucketId = "instruction_assets";
  String checklistSignaturesBucketId = "checklist_signatures";
  String timesheetSignaturesBucketId = "timesheet_signatures";
  String userAvatarsBucketId = "user_avatars";

  // Functions
  String flightSchoolFunctionsId = "flight_school_functions";
  String icsFeedFunctionId = "ics_feed";
  String auditPdfMergerFunctionId = "audit_pdf_merger";
  String securityFunctionId = "tragegurt_security";

  // Optionale Appwrite Messaging Provider-IDs (leer = Standard-Provider im Projekt)
  String fcmProviderId = const String.fromEnvironment(
    'APPWRITE_FCM_PROVIDER_ID',
    defaultValue: '',
  );
  String apnsProviderId = const String.fromEnvironment(
    'APPWRITE_APNS_PROVIDER_ID',
    defaultValue: '',
  );

  String fileViewUrl(String bucketId, String fileId) {
    return "$appwriteEnpoint/storage/buckets/$bucketId/files/$fileId/view?project=$projectId";
  }

  String fileDownloadUrl(String bucketId, String fileId) {
    return "$appwriteEnpoint/storage/buckets/$bucketId/files/$fileId/download?project=$projectId";
  }
}
