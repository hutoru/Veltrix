import Foundation

protocol LedgerStore: AnyObject {
    func load() throws -> Ledger?
    func save(_ ledger: Ledger) throws
}

struct SimulationBackup: Codable {
    private static let currentLabel = "VELTRIX Backup"

    let label: String
    let createdAt: Date
    let ledger: Ledger

    static func export(_ ledger: Ledger) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Self(label: currentLabel, createdAt: Date(), ledger: ledger))
    }

    static func load(_ data: Data) throws -> Ledger {
        do {
            let backup = try JSONDecoder().decode(Self.self, from: data)
            guard backup.label == currentLabel || backup.label == "VELTRIX · Simulation" else {
                throw SimulationError.invalidBackup
            }
            try backup.ledger.validate(assets: Asset.ids)
            return backup.ledger
        } catch {
            throw SimulationError.invalidBackup
        }
    }
}

#if canImport(CoreData)
import CoreData

final class CoreDataLedgerStore: LedgerStore {
    private let context: NSManagedObjectContext

    init(inMemory: Bool = false, url: URL? = nil, onSet: Bool = false) throws {
        let entity = NSEntityDescription()
        entity.name = "SimulationState"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let key = NSAttributeDescription()
        key.name = "key"
        key.attributeType = .stringAttributeType
        key.isOptional = false
        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        payload.isOptional = false
        entity.properties = [key, payload]
        entity.uniquenessConstraints = [["key"]]
        let model = NSManagedObjectModel()
        model.entities = [entity]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let diskURL: URL?
        if inMemory {
            diskURL = nil
        } else {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            diskURL = url ?? directory.appendingPathComponent(onSet ? "VeltrixOnSet.sqlite" : "Veltrix.sqlite")
        }
        #if os(iOS)
        let options: [AnyHashable: Any]? = inMemory ? nil : [
            NSPersistentStoreFileProtectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        #else
        let options: [AnyHashable: Any]? = nil
        #endif
        try coordinator.addPersistentStore(ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType,
                                           configurationName: nil, at: diskURL, options: options)
        context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
    }

    func load() throws -> Ledger? {
        try context.performAndWait {
            guard let data = try state()?.value(forKey: "payload") as? Data else { return nil }
            let ledger = try JSONDecoder().decode(Ledger.self, from: data)
            try ledger.validate(assets: Asset.ids)
            return ledger
        }
    }

    func save(_ ledger: Ledger) throws {
        let data = try JSONEncoder().encode(ledger)
        try context.performAndWait {
            do {
                let row = try state() ?? NSEntityDescription.insertNewObject(forEntityName: "SimulationState", into: context)
                row.setValue("main", forKey: "key")
                row.setValue(data, forKey: "payload")
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func state() throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SimulationState")
        request.predicate = NSPredicate(format: "key == %@", "main")
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
#endif
