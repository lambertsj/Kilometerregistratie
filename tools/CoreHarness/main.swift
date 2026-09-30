import Foundation

// Losse swiftc-harness voor de UI-vrije logica in `Core/` (zie CLAUDE.md):
// draait op de Mac, zonder simulator en zonder XCTest.
//
// Draaien:  ./tools/run-core-harness.sh
// Goldens bijwerken (alleen na een bewuste wijziging): UPDATE_GOLDENS=1 ./tools/run-core-harness.sh

setenv("TZ", "Europe/Amsterdam", 1)

GoldenExportTests.run()
ReportPlanTests.run()
RegionRuleSetTests.run()
ValidationTests.run()
AuditTrailTests.run()
MigrationTests.run()
GermanExportTests.run()
LogValidationRepositoryTests.run()

exit(Harness.report())
