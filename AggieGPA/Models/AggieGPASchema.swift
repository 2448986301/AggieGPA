import SwiftData

enum AggieGPASchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            AcademicTerm.self, CourseRecord.self, PlannerScenario.self,
            SimulatedCourse.self, GradeCategory.self, CourseGradePlan.self,
            UserPreferences.self, BackupSnapshot.self
        ]
    }
}

enum AggieGPASchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 1, 0)
    static var models: [any PersistentModel.Type] {
        AggieGPASchemaV1.models + [
            CourseGradingPolicy.self, GradingCategory.self, GradeItem.self,
            GradeScale.self, ForecastScenario.self, SiriAccessSettings.self
        ]
    }
}

enum AggieGPASchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 3, 0)
    static var models: [any PersistentModel.Type] {
        AggieGPASchemaV2.models + [CourseTemplate.self]
    }
}

enum AggieGPASchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 4, 0)
    static var models: [any PersistentModel.Type] {
        AggieGPASchemaV3.models + [CourseReminderDefaults.self]
    }
}

enum AggieGPAMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AggieGPASchemaV1.self, AggieGPASchemaV2.self, AggieGPASchemaV3.self, AggieGPASchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AggieGPASchemaV1.self, toVersion: AggieGPASchemaV2.self),
            .lightweight(fromVersion: AggieGPASchemaV2.self, toVersion: AggieGPASchemaV3.self),
            .lightweight(fromVersion: AggieGPASchemaV3.self, toVersion: AggieGPASchemaV4.self)
        ]
    }
}
