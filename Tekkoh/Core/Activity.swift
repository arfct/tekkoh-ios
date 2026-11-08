import Foundation
import HealthKit

/// How the day moved, from Apple Health: steps, distance, flights, active
/// energy, exercise minutes and workouts. Read-only.
@MainActor
final class Activity {
    static let shared = Activity()
    private let store = HKHealthStore()

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private let quantities: [HKQuantityTypeIdentifier] = [
        .stepCount, .distanceWalkingRunning, .flightsClimbed, .activeEnergyBurned, .appleExerciseTime,
    ]

    func requestPermission() async {
        guard available else { return }
        var read: Set<HKObjectType> = Set(quantities.map { HKQuantityType($0) })
        read.insert(HKObjectType.workoutType())
        try? await store.requestAuthorization(toShare: [], read: read)
    }

    /// The day's totals, or nil when Health has nothing (or isn't allowed).
    func snapshot(for day: String) async -> Health? {
        guard available else { return nil }
        let span = Day.interval(day)
        let pred = HKQuery.predicateForSamples(withStart: span.start, end: span.end, options: .strictStartDate)
        func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double? {
            let d = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(id), predicate: pred), options: .cumulativeSum)
            return (try? await d.result(for: store))??.sumQuantity()?.doubleValue(for: unit)
        }
        var h = Health()
        h.steps = await sum(.stepCount, .count()).map { Int($0) }
        h.meters = await sum(.distanceWalkingRunning, .meter())
        h.flights = await sum(.flightsClimbed, .count()).map { Int($0) }
        h.activeKcal = await sum(.activeEnergyBurned, .kilocalorie())
        h.exerciseMinutes = await sum(.appleExerciseTime, .minute())
        let wq = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor(\.startDate)])
        if let ws = try? await wq.result(for: store) {
            h.workouts = ws.map { w in
                Workout(kind: w.workoutActivityType.label, minutes: w.duration / 60,
                        kcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                        meters: w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                            ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter()))
            }
        }
        return h.isEmpty && (h.flights ?? 0) == 0 ? nil : h
    }
}

extension HKWorkoutActivityType {
    var label: String {
        switch self {
        case .walking: return "Walk"
        case .running: return "Run"
        case .cycling: return "Ride"
        case .swimming: return "Swim"
        case .hiking: return "Hike"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Row"
        case .elliptical: return "Elliptical"
        case .dance: return "Dance"
        case .pilates: return "Pilates"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .soccer: return "Football"
        case .basketball: return "Basketball"
        case .mindAndBody: return "Mind & body"
        default: return "Workout"
        }
    }
}
