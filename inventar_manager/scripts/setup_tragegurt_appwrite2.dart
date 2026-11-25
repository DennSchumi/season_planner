import 'dart:io';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/enums.dart' as enums;

/// Idempotentes Appwrite 2.x (TablesDB) Setup-Skript für die gesamte
/// Tragegurt-Suite (Core + Season Planner + Inventar Manager).
///
/// Aufruf (PowerShell):
///   $env:APPWRITE_API_KEY="standard_..."
///   dart run scripts/setup_tragegurt_appwrite2.dart
const String endpoint = 'https://appwrite.tragegurt.com/v1';
const String projectId = 'tragegurt';

Future<void> safeRun(String label, Future<void> Function() action) async {
  try {
    await action();
    print('  ✅ $label');
  } on AppwriteException catch (e) {
    if (e.code == 409) {
      print('  ⏭️  $label (existiert bereits)');
    } else {
      print('  ❌ $label -> [${e.code}] ${e.type}: ${e.message}');
      rethrow;
    }
  }
}

Future<void> safeIndex(String label, Future<void> Function() action) async {
  for (int attempt = 1; attempt <= 10; attempt++) {
    try {
      await action();
      print('  ✅ Index: $label');
      return;
    } on AppwriteException catch (e) {
      if (e.code == 409) {
        print('  ⏭️  Index: $label (existiert bereits)');
        return;
      }
      if (e.code == 400 && attempt < 10) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      print('  ❌ Index: $label -> [${e.code}] ${e.type}: ${e.message}');
      rethrow;
    }
  }
}

void main() async {
  final apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('FEHLER: Bitte setze die Umgebungsvariable APPWRITE_API_KEY!');
    exit(1);
  }

  final client = Client()
      .setEndpoint(endpoint)
      .setProject(projectId)
      .setKey(apiKey);

  final tablesDB = TablesDB(client);
  final storage = Storage(client);

  final userReadWrite = [
    Permission.read(Role.users()),
    Permission.create(Role.users()),
    Permission.update(Role.users()),
    Permission.delete(Role.users()),
  ];

  print('🚀 Starte Appwrite 2.x (TablesDB) Setup für Projekt "$projectId"...\n');

  // =========================================================================
  // 1. DATENBANK: core_db (Gemeinsame Stammdaten für alle Tragegurt-Apps)
  // =========================================================================
  print('📦 Datenbank 1/3: core_db (Tragegurt Core)');
  await safeRun('Database core_db', () async {
    await tablesDB.create(databaseId: 'core_db', name: 'Tragegurt Core');
  });

  // Table: users
  await safeRun('Table core_db.users', () async {
    await tablesDB.createTable(
      databaseId: 'core_db',
      tableId: 'users',
      name: 'Users',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
      ],
    );
  });
  await safeRun('users.auth_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'auth_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('users.name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'name',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('users.email', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'email',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('users.phone', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'phone',
      size: 50,
      xrequired: false,
    );
  });
  await safeRun('users.ics_token', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'ics_token',
      size: 128,
      xrequired: false,
    );
  });
  await safeRun('users.avatar_url', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'avatar_url',
      size: 1000,
      xrequired: false,
    );
  });
  await safeRun('users.avatar_file_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'avatar_file_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('users.emergency_contact_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'emergency_contact_name',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('users.emergency_contact_relation', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'emergency_contact_relation',
      size: 120,
      xrequired: false,
    );
  });
  await safeRun('users.emergency_contact_phone', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'emergency_contact_phone',
      size: 60,
      xrequired: false,
    );
  });
  await safeRun('users.birth_date', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'birth_date',
      size: 32,
      xrequired: false,
    );
  });
  await safeRun('users.address', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'address',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('users.license_number', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'license_number',
      size: 128,
      xrequired: false,
    );
  });
  await safeRun('users.license_ratings', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'license_ratings',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('users.employment_type', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'employment_type',
      size: 64,
      xrequired: false,
    );
  });
  await safeRun('users.active_since', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'active_since',
      size: 32,
      xrequired: false,
    );
  });

  // Table: flight_schools
  await safeRun('Table core_db.flight_schools', () async {
    await tablesDB.createTable(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      name: 'Flight Schools',
      permissions: userReadWrite,
    );
  });
  await safeRun('flight_schools.display_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'display_name',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('flight_schools.display_short_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'display_short_name',
      size: 50,
      xrequired: false,
    );
  });
  await safeRun('flight_schools.database_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'database_id',
      size: 255,
      xrequired: false,
      xdefault: 'season_planner_db',
    );
  });
  await safeRun('flight_schools.events_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'events_id',
      size: 255,
      xrequired: false,
      xdefault: 'events',
    );
  });
  await safeRun('flight_schools.team_assigments_events_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'team_assigments_events_id',
      size: 255,
      xrequired: false,
      xdefault: 'team_assignments_events',
    );
  });
  await safeRun('flight_schools.audit_logs_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'audit_logs_id',
      size: 255,
      xrequired: false,
      xdefault: 'audit_logs',
    );
  });
  await safeRun('flight_schools.admin_users', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'admin_users',
      size: 255,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('flight_schools.logo_link', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'logo_link',
      size: 1000,
      xrequired: false,
    );
  });
  await safeRun('flight_schools.logo_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'logo_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('flight_schools.inventoryEnabled', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'inventoryEnabled',
      xrequired: false,
      xdefault: true,
    );
  });
  await safeRun('flight_schools.seasonPlannerEnabled', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'seasonPlannerEnabled',
      xrequired: false,
      xdefault: true,
    );
  });
  await safeRun('flight_schools.tandem_enabled', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'tandem_enabled',
      xrequired: false,
      xdefault: true,
    );
  });
  await safeRun('flight_schools.timesheet_enabled', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'timesheet_enabled',
      xrequired: false,
      xdefault: true,
    );
  });
  await safeRun('flight_schools.timesheet_qualification_ids', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'timesheet_qualification_ids',
      size: 64,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('flight_schools.audit_exports_enabled', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'audit_exports_enabled',
      xrequired: false,
      xdefault: true,
    );
  });
  await safeRun('flight_schools.audit_profile_json', () async {
    await tablesDB.createTextColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'audit_profile_json',
      xrequired: false,
    );
  });
  await safeRun('flight_schools.subscription_status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'subscription_status',
      size: 30,
      xrequired: false,
      xdefault: 'pending',
    );
  });
  await safeRun('flight_schools.ics_token', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'flight_schools',
      key: 'ics_token',
      size: 128,
      xrequired: false,
    );
  });

  // Table: memberships
  await safeRun('Table core_db.memberships', () async {
    await tablesDB.createTable(
      databaseId: 'core_db',
      tableId: 'memberships',
      name: 'Memberships',
      permissions: userReadWrite,
    );
  });
  await safeRun('memberships.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'memberships',
      key: 'status',
      size: 50,
      xrequired: false,
      xdefault: 'active',
    );
  });
  await safeRun('memberships.roles', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'memberships',
      key: 'roles',
      size: 100,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('memberships.qualifications', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'memberships',
      key: 'qualifications',
      size: 255,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('memberships.requested_qualifications', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'memberships',
      key: 'requested_qualifications',
      size: 255,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('Relationship memberships.users <-> users.memberships', () async {
    await tablesDB.createRelationshipColumn(
      databaseId: 'core_db',
      tableId: 'memberships',
      relatedTableId: 'users',
      type: enums.RelationshipType.manyToOne,
      twoWay: true,
      key: 'users',
      twoWayKey: 'memberships',
      onDelete: enums.RelationMutate.cascade,
    );
  });
  await safeRun(
      'Relationship memberships.flightSchools <-> flight_schools.memberships',
      () async {
    await tablesDB.createRelationshipColumn(
      databaseId: 'core_db',
      tableId: 'memberships',
      relatedTableId: 'flight_schools',
      type: enums.RelationshipType.manyToOne,
      twoWay: true,
      key: 'flightSchools',
      twoWayKey: 'memberships',
      onDelete: enums.RelationMutate.cascade,
    );
  });

  await safeIndex('core_db.users.idx_auth_id', () async {
    await tablesDB.createIndex(
      databaseId: 'core_db',
      tableId: 'users',
      key: 'idx_auth_id',
      type: enums.TablesDBIndexType.key,
      columns: ['auth_id'],
    );
  });

  // Table: team_roles (Pro Flugschule konfigurierbare Teamrollen)
  await safeRun('Table core_db.team_roles', () async {
    await tablesDB.createTable(
      databaseId: 'core_db',
      tableId: 'team_roles',
      name: 'Team Roles',
      permissions: userReadWrite,
    );
  });
  await safeRun('team_roles.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('team_roles.name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'name',
      size: 100,
      xrequired: true,
    );
  });
  await safeRun('team_roles.is_default', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'is_default',
      xrequired: false,
      xdefault: false,
    );
  });
  await safeRun('team_roles.required_documents', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'required_documents',
      size: 120,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('team_roles.checklist_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'checklist_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('team_roles.instruction_ids', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'instruction_ids',
      size: 255,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('team_roles.required_qualification_ids', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'required_qualification_ids',
      size: 255,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('team_roles.require_all_qualifications', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'require_all_qualifications',
      xrequired: false,
      xdefault: true,
    );
  });

  // Table: qualifications (Pro Flugschule konfigurierbare Qualifikationen inkl. Pflichtnachweise)
  await safeRun('Table core_db.qualifications', () async {
    await tablesDB.createTable(
      databaseId: 'core_db',
      tableId: 'qualifications',
      name: 'Qualifications',
      permissions: userReadWrite,
    );
  });
  await safeRun('qualifications.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualifications',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('qualifications.name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualifications',
      key: 'name',
      size: 100,
      xrequired: true,
    );
  });
  await safeRun('qualifications.is_default', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'core_db',
      tableId: 'qualifications',
      key: 'is_default',
      xrequired: false,
      xdefault: false,
    );
  });
  await safeRun('qualifications.required_documents', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualifications',
      key: 'required_documents',
      size: 120,
      xrequired: false,
      array: true,
    );
  });

  // Table: qualification_documents (Einmal hochgeladene Nachweise pro Nutzer)
  await safeRun('Table core_db.qualification_documents', () async {
    await tablesDB.createTable(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      name: 'Qualification Documents',
      permissions: userReadWrite,
    );
  });
  await safeRun('qualification_documents.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'user_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('qualification_documents.document_type', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'document_type',
      size: 120,
      xrequired: true,
    );
  });
  await safeRun('qualification_documents.title', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'title',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('qualification_documents.file_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'file_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('qualification_documents.file_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'file_name',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('qualification_documents.issued_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'issued_at',
      xrequired: false,
    );
  });
  await safeRun('qualification_documents.expires_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'expires_at',
      xrequired: false,
    );
  });

  // Table: qualification_approvals (Freigabestatus je Dokument & Flugschule)
  await safeRun('Table core_db.qualification_approvals', () async {
    await tablesDB.createTable(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      name: 'Qualification Approvals',
      permissions: userReadWrite,
    );
  });
  await safeRun('qualification_approvals.document_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'document_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('qualification_approvals.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'user_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('qualification_approvals.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('qualification_approvals.document_type', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'document_type',
      size: 120,
      xrequired: true,
    );
  });
  await safeRun('qualification_approvals.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'status',
      size: 30,
      xrequired: false,
      xdefault: 'submitted',
    );
  });
  await safeRun('qualification_approvals.reviewed_by', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'reviewed_by',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('qualification_approvals.reviewed_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'reviewed_at',
      xrequired: false,
    );
  });
  await safeRun('qualification_approvals.comment', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'comment',
      size: 500,
      xrequired: false,
    );
  });

  await safeIndex('core_db.team_roles.idx_flight_school_id', () async {
    await tablesDB.createIndex(
      databaseId: 'core_db',
      tableId: 'team_roles',
      key: 'idx_flight_school_id',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id'],
    );
  });
  await safeIndex('core_db.qualifications.idx_flight_school_id', () async {
    await tablesDB.createIndex(
      databaseId: 'core_db',
      tableId: 'qualifications',
      key: 'idx_flight_school_id',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id'],
    );
  });
  await safeIndex('core_db.qualification_documents.idx_user_id', () async {
    await tablesDB.createIndex(
      databaseId: 'core_db',
      tableId: 'qualification_documents',
      key: 'idx_user_id',
      type: enums.TablesDBIndexType.key,
      columns: ['user_id'],
    );
  });
  await safeIndex('core_db.qualification_approvals.idx_school_status', () async {
    await tablesDB.createIndex(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'idx_school_status',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'status'],
    );
  });
  await safeIndex('core_db.qualification_approvals.idx_user_id', () async {
    await tablesDB.createIndex(
      databaseId: 'core_db',
      tableId: 'qualification_approvals',
      key: 'idx_user_id',
      type: enums.TablesDBIndexType.key,
      columns: ['user_id'],
    );
  });

  // =========================================================================
  // 2. DATENBANK: season_planner_db (Season Planner)
  // =========================================================================
  print('\n📦 Datenbank 2/3: season_planner_db (Season Planner)');
  await safeRun('Database season_planner_db', () async {
    await tablesDB.create(
      databaseId: 'season_planner_db',
      name: 'Season Planner',
    );
  });

  // Table: events
  await safeRun('Table season_planner_db.events', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'events',
      name: 'Events',
      permissions: userReadWrite,
    );
  });
  await safeRun('events.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'flight_school_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('events.identifier', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'identifier',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('events.display_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'display_name',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('events.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'status',
      size: 50,
      xrequired: true,
    );
  });
  await safeRun('events.start_time', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'start_time',
      xrequired: true,
    );
  });
  await safeRun('events.end_time', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'end_time',
      xrequired: true,
    );
  });
  await safeRun('events.location', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'location',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('events.notes', () async {
    await tablesDB.createTextColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'notes',
      xrequired: false,
    );
  });
  await safeRun('events.planning_period_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'planning_period_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('events.series_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'series_id',
      size: 255,
      xrequired: false,
    );
  });

  // Table: team_assignments_events
  await safeRun('Table season_planner_db.team_assignments_events', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      name: 'Team Assignments Events',
      permissions: userReadWrite,
    );
  });
  await safeRun('team_assignments_events.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'user_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('team_assignments_events.name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'name',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('team_assignments_events.role', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'role',
      size: 100,
      xrequired: true,
    );
  });
  await safeRun('team_assignments_events.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'status',
      size: 50,
      xrequired: true,
    );
  });
  await safeRun('team_assignments_events.swap_offered', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'swap_offered',
      xrequired: false,
      xdefault: false,
    );
  });
  await safeRun('team_assignments_events.swap_requested_by', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'swap_requested_by',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('team_assignments_events.swap_requested_by_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'swap_requested_by_name',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun(
      'Relationship team_assignments_events.events <-> events.team_assignments',
      () async {
    await tablesDB.createRelationshipColumn(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      relatedTableId: 'events',
      type: enums.RelationshipType.manyToOne,
      twoWay: true,
      key: 'events',
      twoWayKey: 'team_assignments',
      onDelete: enums.RelationMutate.cascade,
    );
  });

  // Table: audit_logs
  await safeRun('Table season_planner_db.audit_logs', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'audit_logs',
      name: 'Audit Logs',
      permissions: [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
      ],
    );
  });
  await safeRun('audit_logs.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'audit_logs',
      key: 'flight_school_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('audit_logs.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'audit_logs',
      key: 'user_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('audit_logs.action', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'audit_logs',
      key: 'action',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('audit_logs.details', () async {
    await tablesDB.createTextColumn(
      databaseId: 'season_planner_db',
      tableId: 'audit_logs',
      key: 'details',
      xrequired: false,
    );
  });
  await safeRun('audit_logs.timestamp', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'audit_logs',
      key: 'timestamp',
      xrequired: false,
    );
  });

  await safeIndex('season_planner_db.events.idx_start_time', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'idx_start_time',
      type: enums.TablesDBIndexType.key,
      columns: ['start_time'],
    );
  });
  await safeIndex('season_planner_db.events.idx_school_start_time', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'idx_school_start_time',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'start_time'],
    );
  });
  await safeIndex('season_planner_db.events.idx_school_end_time', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'idx_school_end_time',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'end_time'],
    );
  });
  await safeIndex('season_planner_db.team_assignments_events.idx_user_id',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'idx_user_id',
      type: enums.TablesDBIndexType.key,
      columns: ['user_id'],
    );
  });
  await safeIndex('season_planner_db.team_assignments_events.idx_swap_offered',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'team_assignments_events',
      key: 'idx_swap_offered',
      type: enums.TablesDBIndexType.key,
      columns: ['swap_offered'],
    );
  });
  await safeIndex('season_planner_db.events.idx_planning_period_id', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'events',
      key: 'idx_planning_period_id',
      type: enums.TablesDBIndexType.key,
      columns: ['planning_period_id'],
    );
  });
  await safeIndex('season_planner_db.audit_logs.idx_school_timestamp',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'audit_logs',
      key: 'idx_school_timestamp',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'timestamp'],
    );
  });

  // Table: planning_periods (Planungsstufen 1/2/3 je Flugschule & Saison)
  await safeRun('Table season_planner_db.planning_periods', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'planning_periods',
      name: 'Planning Periods',
      permissions: userReadWrite,
    );
  });
  await safeRun('planning_periods.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'planning_periods',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('planning_periods.season_label', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'planning_periods',
      key: 'season_label',
      size: 100,
      xrequired: true,
    );
  });
  await safeRun('planning_periods.stage', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'planning_periods',
      key: 'stage',
      xrequired: false,
      min: 1,
      max: 3,
      xdefault: 3,
    );
  });
  await safeRun('planning_periods.start_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'planning_periods',
      key: 'start_date',
      xrequired: false,
    );
  });
  await safeRun('planning_periods.end_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'planning_periods',
      key: 'end_date',
      xrequired: false,
    );
  });

  // Table: availability_submissions (Stufe-1-Verfügbarkeiten + Blackout-Tage)
  await safeRun('Table season_planner_db.availability_submissions', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      name: 'Availability Submissions',
      permissions: userReadWrite,
    );
  });
  await safeRun('availability_submissions.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'user_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('availability_submissions.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('availability_submissions.planning_period_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'planning_period_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('availability_submissions.kind', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'kind',
      size: 30,
      xrequired: false,
      xdefault: 'available',
    );
  });
  await safeRun('availability_submissions.start_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'start_date',
      xrequired: true,
    );
  });
  await safeRun('availability_submissions.end_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'end_date',
      xrequired: true,
    );
  });
  await safeRun('availability_submissions.notes', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'notes',
      size: 500,
      xrequired: false,
    );
  });

  await safeIndex('season_planner_db.planning_periods.idx_flight_school_id',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'planning_periods',
      key: 'idx_flight_school_id',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id'],
    );
  });
  await safeIndex(
      'season_planner_db.availability_submissions.idx_school_period', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'idx_school_period',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'planning_period_id'],
    );
  });
  await safeIndex('season_planner_db.availability_submissions.idx_user_id',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'availability_submissions',
      key: 'idx_user_id',
      type: enums.TablesDBIndexType.key,
      columns: ['user_id'],
    );
  });

  // Table: event_templates (Wiederverwendbare Event-Vorlagen je Flugschule)
  await safeRun('Table season_planner_db.event_templates', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      name: 'Event Templates',
      permissions: userReadWrite,
    );
  });
  await safeRun('event_templates.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('event_templates.template_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'template_name',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('event_templates.display_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'display_name',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('event_templates.identifier', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'identifier',
      size: 100,
      xrequired: false,
    );
  });
  await safeRun('event_templates.location', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'location',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('event_templates.notes', () async {
    await tablesDB.createTextColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'notes',
      xrequired: false,
    );
  });
  await safeRun('event_templates.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'status',
      size: 50,
      xrequired: false,
      xdefault: 'scheduled',
    );
  });
  await safeRun('event_templates.duration_minutes', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'duration_minutes',
      xrequired: true,
      min: 1,
    );
  });
  await safeRun('event_templates.default_start_hour', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'default_start_hour',
      xrequired: false,
      min: 0,
      max: 23,
      xdefault: 9,
    );
  });
  await safeRun('event_templates.default_start_minute', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'default_start_minute',
      xrequired: false,
      min: 0,
      max: 59,
      xdefault: 0,
    );
  });
  await safeRun('event_templates.roles', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'roles',
      size: 255,
      xrequired: false,
      array: true,
    );
  });
  await safeIndex('season_planner_db.event_templates.idx_fs', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'event_templates',
      key: 'idx_fs',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id'],
    );
  });

  // Table: role_documents (Arbeitsanweisungen & Checklisten als Markdown)
  await safeRun('Table season_planner_db.role_documents', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      name: 'Role Documents',
      permissions: userReadWrite,
    );
  });
  await safeRun('role_documents.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('role_documents.doc_type', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'doc_type',
      size: 30,
      xrequired: true,
    );
  });
  await safeRun('role_documents.title', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'title',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('role_documents.content_md', () async {
    await tablesDB.createTextColumn(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'content_md',
      xrequired: true,
    );
  });
  await safeRun('role_documents.asset_file_ids', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'asset_file_ids',
      size: 255,
      xrequired: false,
      array: true,
    );
  });
  await safeRun('role_documents.version', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'version',
      xrequired: false,
      xdefault: 1,
    );
  });
  await safeRun('role_documents.updated_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'updated_at',
      xrequired: false,
    );
  });

  // Table: checklist_completions (Zwischenstände & unterschriebene Protokolle)
  await safeRun('Table season_planner_db.checklist_completions', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      name: 'Checklist Completions',
      permissions: userReadWrite,
    );
  });
  await safeRun('checklist_completions.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.event_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'event_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.assignment_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'assignment_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'user_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.role_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'role_name',
      size: 120,
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.checklist_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'checklist_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.checklist_title', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'checklist_title',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.checklist_version', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'checklist_version',
      xrequired: false,
      xdefault: 1,
    );
  });
  await safeRun('checklist_completions.items_snapshot_json', () async {
    await tablesDB.createTextColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'items_snapshot_json',
      xrequired: true,
    );
  });
  await safeRun('checklist_completions.total_count', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'total_count',
      xrequired: false,
      xdefault: 0,
    );
  });
  await safeRun('checklist_completions.checked_count', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'checked_count',
      xrequired: false,
      xdefault: 0,
    );
  });
  await safeRun('checklist_completions.is_complete', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'is_complete',
      xrequired: false,
      xdefault: false,
    );
  });
  await safeRun('checklist_completions.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'status',
      size: 30,
      xrequired: false,
      xdefault: 'in_progress',
    );
  });
  await safeRun('checklist_completions.notes', () async {
    await tablesDB.createTextColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'notes',
      xrequired: false,
    );
  });
  await safeRun('checklist_completions.signature_file_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'signature_file_id',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('checklist_completions.signed_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'signed_at',
      xrequired: false,
    );
  });
  await safeRun('checklist_completions.updated_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'updated_at',
      xrequired: false,
    );
  });

  await safeIndex('season_planner_db.role_documents.idx_school_type', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'role_documents',
      key: 'idx_school_type',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'doc_type'],
    );
  });
  await safeIndex('season_planner_db.checklist_completions.idx_assignment_id',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'idx_assignment_id',
      type: enums.TablesDBIndexType.key,
      columns: ['assignment_id'],
    );
  });
  await safeIndex('season_planner_db.checklist_completions.idx_event_id',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'idx_event_id',
      type: enums.TablesDBIndexType.key,
      columns: ['event_id'],
    );
  });
  await safeIndex('season_planner_db.checklist_completions.idx_school_status',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'checklist_completions',
      key: 'idx_school_status',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'status'],
    );
  });

  // Table: tandem_duties (Tandempilot-Einteilungen & Anfragen)
  await safeRun('Table season_planner_db.tandem_duties', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      name: 'Tandem Duties',
      permissions: userReadWrite,
    );
  });
  await safeRun('tandem_duties.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('tandem_duties.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'user_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('tandem_duties.start_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'start_date',
      xrequired: true,
    );
  });
  await safeRun('tandem_duties.end_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'end_date',
      xrequired: true,
    );
  });
  await safeRun('tandem_duties.is_full_day', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'is_full_day',
      xrequired: false,
      xdefault: true,
    );
  });
  await safeRun('tandem_duties.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'status',
      size: 40,
      xrequired: false,
      xdefault: 'confirmed',
    );
  });
  await safeRun('tandem_duties.notes', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'notes',
      size: 500,
      xrequired: false,
    );
  });
  await safeRun('tandem_duties.created_by', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'created_by',
      size: 255,
      xrequired: false,
    );
  });
  await safeIndex('season_planner_db.tandem_duties.idx_school_dates', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'idx_school_dates',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'start_date'],
    );
  });
  await safeIndex('season_planner_db.tandem_duties.idx_school_end_date',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'idx_school_end_date',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'end_date'],
    );
  });
  await safeIndex('season_planner_db.tandem_duties.idx_user', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'tandem_duties',
      key: 'idx_user',
      type: enums.TablesDBIndexType.key,
      columns: ['user_id'],
    );
  });

  // Table: tandem_demands (Tandempilot-Bedarfszeiträume nach Saison & Wochentag)
  await safeRun('Table season_planner_db.tandem_demands', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      name: 'Tandem Demands',
      permissions: userReadWrite,
    );
  });
  await safeRun('tandem_demands.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('tandem_demands.start_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      key: 'start_date',
      xrequired: true,
    );
  });
  await safeRun('tandem_demands.end_date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      key: 'end_date',
      xrequired: true,
    );
  });
  await safeRun('tandem_demands.target_pilots', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      key: 'target_pilots',
      xrequired: true,
      min: 0,
      max: 100,
    );
  });
  await safeRun('tandem_demands.weekdays', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      key: 'weekdays',
      size: 30,
      xrequired: false,
      xdefault: '1,2,3,4,5,6,7',
    );
  });
  await safeRun('tandem_demands.label', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      key: 'label',
      size: 120,
      xrequired: false,
    );
  });
  await safeIndex('season_planner_db.tandem_demands.idx_school', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'tandem_demands',
      key: 'idx_school',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id'],
    );
  });

  // Table: event_timesheets (Stundenzettel / Lehrtätigkeits-Nachweise je Event-Einsatz)
  await safeRun('Table season_planner_db.event_timesheets', () async {
    await tablesDB.createTable(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      name: 'Event Timesheets',
      permissions: userReadWrite,
    );
  });
  await safeRun('event_timesheets.flight_school_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'flight_school_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('event_timesheets.event_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'event_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('event_timesheets.assignment_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'assignment_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('event_timesheets.user_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'user_id',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('event_timesheets.event_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'event_name',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('event_timesheets.role_name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'role_name',
      size: 128,
      xrequired: false,
    );
  });
  await safeRun('event_timesheets.event_start', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'event_start',
      xrequired: false,
    );
  });
  await safeRun('event_timesheets.event_end', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'event_end',
      xrequired: false,
    );
  });
  await safeRun('event_timesheets.entries_json', () async {
    await tablesDB.createTextColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'entries_json',
      xrequired: false,
    );
  });
  await safeRun('event_timesheets.total_minutes', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'total_minutes',
      xrequired: false,
      xdefault: 0,
    );
  });
  await safeRun('event_timesheets.active_days', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'active_days',
      xrequired: false,
      xdefault: 0,
    );
  });
  await safeRun('event_timesheets.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'status',
      size: 32,
      xrequired: false,
      xdefault: 'draft',
    );
  });
  await safeRun('event_timesheets.signature_file_id', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'signature_file_id',
      size: 128,
      xrequired: false,
    );
  });
  await safeRun('event_timesheets.submitted_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'submitted_at',
      xrequired: false,
    );
  });
  await safeRun('event_timesheets.updated_at', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'updated_at',
      xrequired: false,
    );
  });
  await safeIndex('season_planner_db.event_timesheets.idx_assignment_id',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'idx_assignment_id',
      type: enums.TablesDBIndexType.key,
      columns: ['assignment_id'],
    );
  });
  await safeIndex('season_planner_db.event_timesheets.idx_event_id', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'idx_event_id',
      type: enums.TablesDBIndexType.key,
      columns: ['event_id'],
    );
  });
  await safeIndex('season_planner_db.event_timesheets.idx_user_id', () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'idx_user_id',
      type: enums.TablesDBIndexType.key,
      columns: ['user_id'],
    );
  });
  await safeIndex('season_planner_db.event_timesheets.idx_school_status',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'idx_school_status',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'status'],
    );
  });
  await safeIndex('season_planner_db.event_timesheets.idx_school_event_start',
      () async {
    await tablesDB.createIndex(
      databaseId: 'season_planner_db',
      tableId: 'event_timesheets',
      key: 'idx_school_event_start',
      type: enums.TablesDBIndexType.key,
      columns: ['flight_school_id', 'event_start'],
    );
  });

  // =========================================================================
  // 3. DATENBANK: inventory_db (Inventar Manager)
  // =========================================================================
  print('\n📦 Datenbank 3/3: inventory_db (Inventar Manager)');
  await safeRun('Database inventory_db', () async {
    await tablesDB.create(
      databaseId: 'inventory_db',
      name: 'Inventar Manager',
    );
  });

  // Table: categories
  await safeRun('Table inventory_db.categories', () async {
    await tablesDB.createTable(
      databaseId: 'inventory_db',
      tableId: 'categories',
      name: 'Categories',
      permissions: userReadWrite,
    );
  });
  await safeRun('categories.schoolId', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'categories',
      key: 'schoolId',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('categories.name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'categories',
      key: 'name',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('categories.prefix', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'categories',
      key: 'prefix',
      size: 10,
      xrequired: true,
    );
  });
  await safeRun('categories.serviceIntervalMonths', () async {
    await tablesDB.createIntegerColumn(
      databaseId: 'inventory_db',
      tableId: 'categories',
      key: 'serviceIntervalMonths',
      xrequired: true,
    );
  });
  await safeRun('categories.serviceRequiresDoc', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'inventory_db',
      tableId: 'categories',
      key: 'serviceRequiresDoc',
      xrequired: false,
      xdefault: false,
    );
  });
  await safeRun('categories.iconData', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'categories',
      key: 'iconData',
      size: 100,
      xrequired: false,
      xdefault: 'support',
    );
  });

  // Table: items
  await safeRun('Table inventory_db.items', () async {
    await tablesDB.createTable(
      databaseId: 'inventory_db',
      tableId: 'items',
      name: 'Items',
      permissions: userReadWrite,
    );
  });
  await safeRun('items.schoolId', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'schoolId',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('items.categoryId', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'categoryId',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('items.materialNumber', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'materialNumber',
      size: 50,
      xrequired: true,
    );
  });
  await safeRun('items.name', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'name',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('items.serialNumber', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'serialNumber',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('items.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'status',
      size: 50,
      xrequired: false,
      xdefault: 'in_stock',
    );
  });
  await safeRun('items.assignedTo', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'assignedTo',
      size: 255,
      xrequired: false,
    );
  });
  await safeRun('items.lastServiceDate', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'lastServiceDate',
      xrequired: false,
    );
  });
  await safeRun('items.nextServiceDate', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'nextServiceDate',
      xrequired: false,
    );
  });
  await safeRun('items.isLocked', () async {
    await tablesDB.createBooleanColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'isLocked',
      xrequired: false,
      xdefault: false,
    );
  });
  await safeRun('items.lockReason', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'lockReason',
      size: 500,
      xrequired: false,
    );
  });

  // Table: transactions
  await safeRun('Table inventory_db.transactions', () async {
    await tablesDB.createTable(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      name: 'Transactions',
      permissions: userReadWrite,
    );
  });
  await safeRun('transactions.schoolId', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'schoolId',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('transactions.itemId', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'itemId',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('transactions.type', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'type',
      size: 50,
      xrequired: true,
    );
  });
  await safeRun('transactions.status', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'status',
      size: 50,
      xrequired: true,
    );
  });
  await safeRun('transactions.initiator', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'initiator',
      size: 255,
      xrequired: true,
    );
  });
  await safeRun('transactions.captureMethod', () async {
    await tablesDB.createVarcharColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'captureMethod',
      size: 50,
      xrequired: true,
    );
  });
  await safeRun('transactions.details', () async {
    await tablesDB.createTextColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'details',
      xrequired: false,
    );
  });
  await safeRun('transactions.date', () async {
    await tablesDB.createDatetimeColumn(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'date',
      xrequired: false,
    );
  });

  // Indexes for inventory_db
  await safeIndex('inventory_db.categories.idx_schoolId', () async {
    await tablesDB.createIndex(
      databaseId: 'inventory_db',
      tableId: 'categories',
      key: 'idx_schoolId',
      type: enums.TablesDBIndexType.key,
      columns: ['schoolId'],
    );
  });
  await safeIndex('inventory_db.items.idx_schoolId', () async {
    await tablesDB.createIndex(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'idx_schoolId',
      type: enums.TablesDBIndexType.key,
      columns: ['schoolId'],
    );
  });
  await safeIndex('inventory_db.items.idx_categoryId', () async {
    await tablesDB.createIndex(
      databaseId: 'inventory_db',
      tableId: 'items',
      key: 'idx_categoryId',
      type: enums.TablesDBIndexType.key,
      columns: ['categoryId'],
    );
  });
  await safeIndex('inventory_db.transactions.idx_itemId', () async {
    await tablesDB.createIndex(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'idx_itemId',
      type: enums.TablesDBIndexType.key,
      columns: ['itemId'],
    );
  });
  await safeIndex('inventory_db.transactions.idx_type_status', () async {
    await tablesDB.createIndex(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'idx_type_status',
      type: enums.TablesDBIndexType.key,
      columns: ['type', 'status'],
    );
  });
  await safeIndex('inventory_db.transactions.idx_date', () async {
    await tablesDB.createIndex(
      databaseId: 'inventory_db',
      tableId: 'transactions',
      key: 'idx_date',
      type: enums.TablesDBIndexType.key,
      columns: ['date'],
    );
  });

  // =========================================================================
  // 4. STORAGE BUCKETS
  // =========================================================================
  print('\n🗂️  Storage Buckets');
  await safeRun('Bucket flight_school_logos', () async {
    await storage.createBucket(
      bucketId: 'flight_school_logos',
      name: 'Flight School Logos',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
        Permission.delete(Role.users()),
      ],
      allowedFileExtensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'],
      maximumFileSize: 5242880, // 5 MB
    );
  });
  await safeRun('Bucket service_proofs', () async {
    await storage.createBucket(
      bucketId: 'service_proofs',
      name: 'Service Proofs',
      permissions: userReadWrite,
      allowedFileExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      maximumFileSize: 10485760, // 10 MB
    );
  });
  await safeRun('Bucket qualification_documents', () async {
    await storage.createBucket(
      bucketId: 'qualification_documents',
      name: 'Qualification Documents',
      permissions: userReadWrite,
      allowedFileExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      maximumFileSize: 15728640, // 15 MB
    );
  });
  await safeRun('Bucket instruction_assets', () async {
    await storage.createBucket(
      bucketId: 'instruction_assets',
      name: 'Instruction Assets',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
        Permission.delete(Role.users()),
      ],
      allowedFileExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg'],
      maximumFileSize: 10485760, // 10 MB
    );
  });
  await safeRun('Bucket checklist_signatures', () async {
    await storage.createBucket(
      bucketId: 'checklist_signatures',
      name: 'Checklist Signatures',
      permissions: userReadWrite,
      allowedFileExtensions: ['png'],
      maximumFileSize: 2097152, // 2 MB
    );
  });
  await safeRun('Bucket timesheet_signatures', () async {
    await storage.createBucket(
      bucketId: 'timesheet_signatures',
      name: 'Timesheet Signatures',
      permissions: userReadWrite,
      allowedFileExtensions: ['png'],
      maximumFileSize: 2097152, // 2 MB
    );
  });
  await safeRun('Bucket user_avatars', () async {
    await storage.createBucket(
      bucketId: 'user_avatars',
      name: 'User Avatars',
      permissions: [
        Permission.read(Role.any()),
        Permission.create(Role.users()),
        Permission.update(Role.users()),
        Permission.delete(Role.users()),
      ],
      allowedFileExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      maximumFileSize: 5242880, // 5 MB
    );
  });

  print('\n🎉 Tragegurt Appwrite 2.x Setup komplett abgeschlossen!');
}
