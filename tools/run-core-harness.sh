#!/bin/sh
# Compileert en draait de UI-vrije kernlogica op de Mac — geen simulator,
# geen Xcode-project. Zie CLAUDE.md ("Verifiëren").
#
#   ./tools/run-core-harness.sh
#   UPDATE_GOLDENS=1 ./tools/run-core-harness.sh   # alleen na een bewuste wijziging
set -e

cd "$(dirname "$0")/.."
BUILD_DIR="${TMPDIR:-/tmp}/km-core-harness"
mkdir -p "$BUILD_DIR"

# Alleen bronnen zonder CoreLocation/UIKit/SwiftUI: die compileren op de host.
# SwiftData werkt wél op de Mac, dus modellen, repositories, de schrijfservice
# en de migratie kunnen hier getest worden — zonder simulator.
SOURCES="
Kilometerregistratie/Models/TripCategory.swift
Kilometerregistratie/Models/RoutePoint.swift
Kilometerregistratie/Models/Trip.swift
Kilometerregistratie/Models/Vehicle.swift
Kilometerregistratie/Models/AppSettings.swift
Kilometerregistratie/Models/CachedAddress.swift
Kilometerregistratie/Models/ClassificationRule.swift
Kilometerregistratie/Models/TripRevision.swift
Kilometerregistratie/Models/AppSchema.swift
Kilometerregistratie/Models/Migrations/AppSchemaV1.swift
Kilometerregistratie/Models/Migrations/AppMigrationPlan.swift
Kilometerregistratie/Repositories/TripRepository.swift
Kilometerregistratie/Repositories/VehicleRepository.swift
Kilometerregistratie/Repositories/ClassificationRuleRepository.swift
Kilometerregistratie/Repositories/LogValidationRepository.swift
Kilometerregistratie/Services/TripWriteService.swift
Kilometerregistratie/Core/TripAuditField.swift
Kilometerregistratie/Core/CountedText.swift
Kilometerregistratie/Core/LogValidation.swift
Kilometerregistratie/Core/TripClassifier.swift
Kilometerregistratie/Core/TripMerge.swift
Kilometerregistratie/Core/GeoDistance.swift
Kilometerregistratie/Core/MileageStatistics.swift
Kilometerregistratie/Core/PeriodFilter.swift
Kilometerregistratie/Core/ReportGenerator.swift
Kilometerregistratie/Core/ReportDocumentPlan.swift
Kilometerregistratie/Core/XlsxBuilder.swift
Kilometerregistratie/Core/ZipArchive.swift
"

# Alle regio-bestanden meenemen zodra ze bestaan (fase 1 en later).
if [ -d Kilometerregistratie/Core/Region ]; then
  SOURCES="$SOURCES $(find Kilometerregistratie/Core/Region -name '*.swift' | sort)"
fi

HARNESS="$(find tools/CoreHarness -name '*.swift' ! -name 'main.swift' | sort) tools/CoreHarness/main.swift"

# shellcheck disable=SC2086
swiftc -o "$BUILD_DIR/harness" $SOURCES $HARNESS

GOLDEN_DIR="$(pwd)/tools/goldens" "$BUILD_DIR/harness"
