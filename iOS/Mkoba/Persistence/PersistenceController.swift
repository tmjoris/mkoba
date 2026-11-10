import CoreData

struct PersistenceController {
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Mkoba")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        // Ledger events are financial records: protect the file until first unlock.
        container.persistentStoreDescriptions.first?.setOption(
            FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
            forKey: NSPersistentStoreFileProtectionKey)
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data store failed to load: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        // Events are immutable and unique by id, so a duplicate insert is a no-op, not a conflict.
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }
}
