/// TODO
public protocol _Relation {
    /// TODO
    @warn_unused_result
    func fork() -> Self
    
    /// TODO
    @warn_unused_result
    func aliased(alias: String) -> Relation
    
    /// TODO
    @warn_unused_result
    func numberOfColumns(db: Database) throws -> Int
    
    /// TODO
    var name: String { get }
    
    /// TODO
    var referencedSources: [_SQLSource] { get }
    
    /// TODO
    var rightSource: _SQLSource { get }
    
    /// TODO
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?], leftSourceName: String) throws -> String
    
    /// TODO
    func selection(included included: Bool) -> [_SQLSelectable]
    
    /// TODO
    func adapter(included included: Bool, inout selectionIndex: Int, columnIndexForSelectionIndex: [Int: Int]) -> RowAdapter?
}

/// TODO
public protocol Relation : _Relation {
}

extension Relation {
    /// TODO
    /// extension Method
    @warn_unused_result
    public func include(relations: Relation...) -> Relation {
        return include(relations)
    }
    
    /// TODO
    /// extension Method
    @warn_unused_result
    public func include(relations: [Relation]) -> Relation {
        return ChainedRelation(baseRelation: self, joinedRelations: relations.map { JoinedRelation(included: true, relation: $0.fork()) })
    }
    
    /// TODO
    /// extension Method
    @warn_unused_result
    public func join(relations: Relation...) -> Relation {
        return join(relations)
    }
    
    /// TODO
    /// extension Method
    @warn_unused_result
    public func join(relations: [Relation]) -> Relation {
        return ChainedRelation(baseRelation: self, joinedRelations: relations.map { JoinedRelation(included: false, relation: $0.fork()) })
    }
}

struct JoinedRelation {
    let included: Bool
    let relation: Relation
    
    func fork() -> JoinedRelation {
        return JoinedRelation(included: included, relation: relation.fork())
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        if included {
            return try relation.numberOfColumns(db)
        } else {
            return 0
        }
    }
}

struct ChainedRelation {
    let baseRelation: Relation
    let joinedRelations: [JoinedRelation]
}

extension ChainedRelation : Relation {
    /// TODO
    func fork() -> ChainedRelation {
        return ChainedRelation(baseRelation: baseRelation.fork(), joinedRelations: joinedRelations.map { $0.fork() })
    }
    
    /// TODO
    func aliased(alias: String) -> Relation {
        return ChainedRelation(baseRelation: baseRelation.aliased(alias), joinedRelations: joinedRelations)
    }
    
    /// TODO
    @warn_unused_result
    func numberOfColumns(db: Database) throws -> Int {
        return try joinedRelations.reduce(baseRelation.numberOfColumns(db)) { try $0 + $1.numberOfColumns(db) }
    }
    
    /// TODO
    var name: String {
        return baseRelation.name
    }
    
    /// TODO
    var referencedSources: [_SQLSource] {
        return joinedRelations.reduce(baseRelation.referencedSources) { $0 + $1.relation.referencedSources }
    }
    
    /// TODO
    var rightSource: _SQLSource {
        return baseRelation.rightSource
    }
    
    /// TODO
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?], leftSourceName: String) throws -> String {
        var sql = try baseRelation.sql(db, &bindings, leftSourceName: leftSourceName)
        if !joinedRelations.isEmpty {
            sql += " "
            sql += try joinedRelations.map {
                try $0.relation.sql(db, &bindings, leftSourceName: baseRelation.rightSource.name!)
                }.joinWithSeparator(" ")
        }
        return sql
    }
    
    /// TODO
    func selection(included included: Bool) -> [_SQLSelectable] {
        return joinedRelations.reduce(baseRelation.selection(included: included)) { (selection, joinedRelation) in
            selection + joinedRelation.relation.selection(included: joinedRelation.included)
        }
    }
    
    /// TODO
    func adapter(included included: Bool, inout selectionIndex: Int, columnIndexForSelectionIndex: [Int: Int]) -> RowAdapter? {
        let baseAdapter = baseRelation.adapter(included: included, selectionIndex: &selectionIndex, columnIndexForSelectionIndex: columnIndexForSelectionIndex)
        
        var variants: [String: RowAdapter] = [:]
        for joinedRelation in joinedRelations {
            if let adapter = joinedRelation.relation.adapter(included: joinedRelation.included, selectionIndex: &selectionIndex, columnIndexForSelectionIndex: columnIndexForSelectionIndex) {
                variants[joinedRelation.relation.name] = adapter
            }
        }
        
        if baseAdapter == nil && variants.isEmpty {
            return nil
        }
        
        return (baseAdapter ?? ColumnMapping([:])).adapterWithVariants(variants)
    }
}

/// TODO
public struct ForeignRelation {
    /// TODO
    public let name: String
    /// TODO
    public let foreignKey: [String: String] // [leftColumn: rightColumn]
    /// TODO
    public let rightSource: _SQLSource
    
    /// TODO
    public init(name: String, tableName: String, foreignKey: [String: String]) {
        // TODO: why this forced alias?
        // TODO: don't alias need to be validated?
        self.init(name: name, rightSource: _SQLSourceTable(tableName: tableName, alias: ((name == tableName) ? nil : name)), foreignKey: foreignKey)
    }
    
    init(name: String, rightSource: _SQLSource, foreignKey: [String: String]) {
        self.name = name
        self.rightSource = rightSource
        self.foreignKey = foreignKey
    }
}

extension ForeignRelation : Relation {
    /// TODO
    public func fork() -> ForeignRelation {
        return ForeignRelation(name: name, rightSource: rightSource.fork(), foreignKey: foreignKey)
    }
    
    /// TODO
    @warn_unused_result
    public func aliased(alias: String) -> Relation {
        let rightSource = self.rightSource.fork()
        rightSource.name = alias
        return ForeignRelation(name: name, rightSource: rightSource, foreignKey: foreignKey)
    }
    
    /// TODO
    @warn_unused_result
    public func numberOfColumns(db: Database) throws -> Int {
        return try rightSource.numberOfColumns(db)
    }
    
    /// TODO
    public var referencedSources: [_SQLSource] {
        return rightSource.referencedSources
    }
    
    /// TODO
    public func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?], leftSourceName: String) throws -> String {
        var sql = try "LEFT JOIN " + rightSource.sql(db, &bindings) + " ON "
        sql += foreignKey.map({ (leftColumn, rightColumn) -> String in
            "\(rightSource.name!.quotedDatabaseIdentifier).\(rightColumn.quotedDatabaseIdentifier) = \(leftSourceName.quotedDatabaseIdentifier).\(leftColumn.quotedDatabaseIdentifier)"
        }).joinWithSeparator(" AND ")
        return sql
    }
    
    /// TODO
    public func selection(included included: Bool) -> [_SQLSelectable] {
        guard included else {
            return []
        }
        return [_SQLResultColumn.Star(rightSource)]
    }
    
    /// TODO
    public func adapter(included included: Bool, inout selectionIndex: Int, columnIndexForSelectionIndex: [Int: Int]) -> RowAdapter? {
        guard included else {
            return nil
        }
        defer { selectionIndex += 1 }
        return SuffixRowAdapter(fromIndex: columnIndexForSelectionIndex[selectionIndex]!)
    }
}

extension QueryInterfaceRequest {
    /// TODO: doc
    @warn_unused_result
    public func include(relations: Relation...) -> QueryInterfaceRequest<T> {
        return include(relations)
    }
    
    /// TODO: doc
    /// TODO: test that request.include([assoc1, assoc2]) <=> request.include([assoc1]).include([assoc2])
    @warn_unused_result
    public func include(relations: [Relation]) -> QueryInterfaceRequest<T> {
        var query = self.query
        var source = query.source!
        for relation in relations {
            source = source.include(relation)
            query.selection.appendContentsOf(relation.selection(included: true))
        }
        query.source = source
        return QueryInterfaceRequest(query: query)
    }
    
    /// TODO: doc
    @warn_unused_result
    public func join(relations: Relation...) -> QueryInterfaceRequest<T> {
        return join(relations)
    }
    
    /// TODO: doc
    /// TODO: test that request.join([assoc1, assoc2]) <=> request.join([assoc1]).join([assoc2])
    @warn_unused_result
    public func join(relations: [Relation]) -> QueryInterfaceRequest<T> {
        var query = self.query
        var source = query.source!
        for relation in relations {
            source = source.join(relation)
            query.selection.appendContentsOf(relation.selection(included: false))
        }
        query.source = source
        return QueryInterfaceRequest(query: query)
    }
}

extension TableMapping {
    /// TODO: doc
    @warn_unused_result
    public static func include(relations: Relation...) -> QueryInterfaceRequest<Self> {
        return all().include(relations)
    }
    
    /// TODO: doc
    @warn_unused_result
    public static func include(relations: [Relation]) -> QueryInterfaceRequest<Self> {
        return all().include(relations)
    }
    
    /// TODO: doc
    @warn_unused_result
    public static func join(relations: Relation...) -> QueryInterfaceRequest<Self> {
        return all().join(relations)
    }
    
    /// TODO: doc
    @warn_unused_result
    public static func join(relations: [Relation]) -> QueryInterfaceRequest<Self> {
        return all().join(relations)
    }
}