class AppwriteConfig {
  static const String endpoint = String.fromEnvironment('APPWRITE_ENDPOINT', defaultValue: "http://localhost/v1");
  static const String projectId = String.fromEnvironment('APPWRITE_PROJECT_ID', defaultValue: "6aa0f487000340aa9e05");
  
  static const String inventoryDatabaseId = "inventory_db"; 
  
  // Collections
  static const String flightSchoolsCollectionId = "6aaa8c490011bf62c622";
  static const String categoriesCollectionId = "6aa99ffb00070a53db7e";
  static const String itemsCollectionId = "6aa9a1460031485a030f";
  static const String transactionsCollectionId = "6aa9a24a003116ab6a56";
  
  // Storage
  static const String serviceProofsBucketId = "6aaafd07000885e37e40";
}
