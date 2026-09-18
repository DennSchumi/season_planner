class AppwriteConfig {
  static const String endpoint = String.fromEnvironment('APPWRITE_ENDPOINT', defaultValue: "http://localhost/v1");
  static const String projectId = String.fromEnvironment('APPWRITE_PROJECT_ID', defaultValue: "6aa0f487000340aa9e05");
  
  static const String inventoryDatabaseId = "inventory_db"; 
  static const String seasonPlannerDatabaseId = "6aa137f3001249bfafae";
  
  // Inventory Collections
  static const String flightSchoolsCollectionId = "6aaa8c490011bf62c622"; // Deprecated (local copy)
  static const String categoriesCollectionId = "6aa99ffb00070a53db7e";
  static const String itemsCollectionId = "6aa9a1460031485a030f";
  static const String transactionsCollectionId = "6aa9a24a003116ab6a56";

  // Season Planner Collections
  static const String spFlightSchoolsCollectionId = "6aa1395d002f8a08aa82";
  static const String spUsersCollectionId = "6aa1394b0029b8f3bb56";
  static const String spMembershipsCollectionId = "6aa13952003db5da63a9";
  
  // Storage
  static const String serviceProofsBucketId = "6aaafd07000885e37e40";
}
