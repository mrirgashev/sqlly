import Foundation

/// The existing fixture tables used by an authored exercise, in display order.
/// This metadata is independent of grading and never inspects submitted SQL.
/// A task that creates its own table, uses only expressions, or inspects a
/// catalog may have no existing fixture table to display.
public struct PracticeTableContext: Sendable, Equatable {
    public let tables: [String]
    public var primaryTable: String? { tables.first }
    public var defaultSQL: String? { primaryTable.map(Self.selectSQL(for:)) }

    public static func forExercise(_ exercise: Exercise) -> Self {
        forExerciseID(exercise.id)
    }

    public static func forExerciseID(_ exerciseID: String) -> Self {
        Self(tables: tablesByExercise[exerciseID] ?? [])
    }

    /// Quoting treats the table name as one identifier, including embedded
    /// quotation marks. Dataset browsing always reads the public fixture.
    public static func selectSQL(for table: String) -> String {
        let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
        return "SELECT * FROM public.\"\(quoted)\";"
    }

    static var exerciseIDs: Set<String> { Set(tablesByExercise.keys) }

    // Each row is one stable lesson ID, followed by an entry for every exercise
    // in its published order. Commas join multiple relevant fixture tables.
    // A dash explicitly records that no existing fixture table is required.
    // Keep new IDs here when adding exercises. Tests require full bilingual
    // coverage and verify every table against each exercise's starting fixture.
    private static let tableRows = """
        l001 customers products orders employees bookings
        l002 customers orders order_items events inventory
        l003 - products order_items products accounts
        l004 products customers orders employees bookings
        l005 products customers orders inventory bookings
        l006 products products orders employees orders
        l007 products orders products accounts bookings
        l008 products employees orders customers products
        l009 products products orders - orders employees
        l010 customers orders customers - orders customers
        l011 products customers customers customers products
        l012 customers customers customers customers customers
        l013 products orders customers products orders
        l014 customers products customers orders products
        l015 - products events products -
        l016 customers customers customers orders orders
        l017 products orders products bookings employees
        l018 orders orders customers products orders
        l019 products orders employees inventory orders
        l020 products orders orders inventory employees
        l021 products orders employees orders inventory
        l022 orders,customers order_items,products inventory,products orders,customers order_items,products
        l023 customers,orders customers,orders customers,orders customers,events products,order_items
        l024 customers,orders customers,orders products,inventory customers,events products,accounts
        l025 employees employees employees employees employees
        l026 orders,customers,order_items,products products,order_items,orders orders,order_items products,order_items,orders customers,orders,order_items,products
        l027 customers,orders customers,orders products,order_items,orders customers,orders employees
        l028 products orders products products employees
        l029 products employees customers,orders orders products
        l030 orders customers,orders products customers,orders employees
        l031 orders orders products,order_items,orders products orders
        l032 customers,inventory customers orders,bookings customers,employees orders
        l033 orders customers,orders order_items,orders customers,orders products,order_items
        l034 products customers orders events products
        l035 products products products,inventory orders inventory
        l036 customers,orders documents events events order_items,orders
        l037 inventory customers inventory inventory customers
        l038 accounts accounts accounts accounts products
        l039 products documents products products order_items,orders
        l040 - customers products - customers
        l041 - - - - -
        l042 customers customers customers - products
        l043 bookings orders orders bookings customers
        l044 events - events - -
        l045 orders events events events orders
        l046 products products products products products
        l047 products products events events products
        l048 products products products products products
        l049 customers products customers customers orders
        l050 - - products - -
        l051 - - - - -
        l052 customers,products customers products products customers,orders,order_items
        l053 customers - - products -
        l054 customers products orders products orders
        l055 employees products orders employees orders
        l056 products employees employees - employees orders
        l057 orders orders employees events inventory
        l058 orders orders orders orders orders
        l059 products orders employees products employees
        l060 orders products events employees products
        l061 orders products customers,orders orders products,order_items,orders
        l062 products products orders orders orders
        l063 - orders bookings products orders
        l064 - orders products - orders
        l065 - - bookings - -
        l066 products accounts inventory products order_items,orders
        l067 customers inventory products customers events
        l068 products events customers products order_items
        l069 documents documents documents documents documents
        l070 orders customers products orders products
        l071 products bookings events products orders
        l072 orders customers orders products products
        l073 products products orders customers,orders orders
        l074 products orders order_items orders products
        l075 customers,orders customers,orders orders customers,orders events
        l076 products orders orders products products
        l077 products documents - - -
        l078 orders products,order_items,orders products customers,products order_items
        l079 - accounts accounts - accounts accounts
        l080 accounts inventory orders accounts orders
        l081 accounts - accounts accounts -
        l082 products - products - -
        l083 customers products customers - customers products
        l084 customers products accounts customers customers
        l085 accounts accounts orders,customers orders products
        l086 - accounts,orders orders products -
        l087 orders orders - products,order_items,orders inventory
        l088 - employees employees employees employees
        l089 employees employees - - employees
        l090 employees employees employees employees employees
        l091 bookings bookings bookings bookings bookings
        l092 - products - accounts -
        l093 products orders - products -
        l094 bookings events orders customers,events bookings
        l095 customers,orders,order_items,products orders,order_items,products products customers,products,orders,order_items customers,orders
        l096 products employees orders products products,order_items
        l097 customers,orders orders products,order_items,orders customers,orders orders
        l098 products products,order_items,orders inventory,products products,order_items,orders inventory
        l099 bookings bookings bookings bookings bookings
        l100 accounts accounts accounts accounts accounts
        l101 events events customers,orders events events
        l102 orders orders orders,order_items - orders orders,order_items
        """

    private static let tablesByExercise: [String: [String]] = {
        var result: [String: [String]] = [:]
        for row in tableRows.split(separator: "\n") {
            let entries = row.split(separator: " ")
            guard let lessonID = entries.first else { continue }
            for (index, entry) in entries.dropFirst().enumerated() {
                let exerciseID = "\(lessonID)-e\(index + 1)"
                result[exerciseID] = entry == "-" ? [] : entry.split(separator: ",").map(String.init)
            }
        }
        return result
    }()
}
