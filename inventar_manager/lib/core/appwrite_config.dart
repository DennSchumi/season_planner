class AppwriteConfig {
  static const String endpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: "https://appwrite.tragegurt.com/v1",
  );
  static const String projectId = String.fromEnvironment(
    'APPWRITE_PROJECT_ID',
    defaultValue: "tragegurt",
  );
  static const String webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: "https://inventar.tragegurt.com",
  );

  // Zentrale Rechtsseiten auf der Tragegurt-Produktwebsite
  static const String legalImprintUrl = String.fromEnvironment(
    'LEGAL_IMPRINT_URL',
    defaultValue: "https://tragegurt.com/impressum",
  );
  static const String legalPrivacyUrl = String.fromEnvironment(
    'LEGAL_PRIVACY_URL',
    defaultValue: "https://tragegurt.com/datenschutz",
  );
  static const String legalTermsUrl = String.fromEnvironment(
    'LEGAL_TERMS_URL',
    defaultValue: "https://tragegurt.com/agb",
  );

  static const String coreDatabaseId = "core_db";
  static const String inventoryDatabaseId = "inventory_db";
  static const String seasonPlannerDatabaseId = coreDatabaseId;

  // Inventory Tables (inventory_db)
  static const String categoriesCollectionId = "categories";
  static const String itemsCollectionId = "items";
  static const String transactionsCollectionId = "transactions";

  // Shared Core Tables (core_db)
  static const String spFlightSchoolsCollectionId = "flight_schools";
  static const String spUsersCollectionId = "users";
  static const String spMembershipsCollectionId = "memberships";

  // Storage Buckets
  static const String serviceProofsBucketId = "service_proofs";
  static const String userAvatarsBucketId = "user_avatars";

  // Functions
  static const String securityFunctionId = "tragegurt_security";

  static String fileViewUrl(String bucketId, String fileId) {
    return "$endpoint/storage/buckets/$bucketId/files/$fileId/view?project=$projectId";
  }
}
