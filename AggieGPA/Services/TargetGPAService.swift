import Foundation

struct TargetGPAResult: Equatable {
    let requiredFutureGPA: Decimal?
    let maximumFinalGPA: Decimal
    let isReachable: Bool
    let minimumTotalFutureUnits: Decimal?
    let additionalUnitsNeeded: Decimal?
}

enum TargetGPAService {
    static func calculate(currentGPA: Decimal, currentUnits: Decimal,
                          targetGPA: Decimal, futureUnits: Decimal,
                          maximumFutureGPA: Decimal = 4) -> TargetGPAResult? {
        guard (0...4).contains(currentGPA), (0...4).contains(targetGPA),
              currentUnits >= 0, futureUnits > 0, maximumFutureGPA > 0 else { return nil }

        let currentPoints = currentGPA * currentUnits
        let totalUnits = currentUnits + futureUnits
        let required = (targetGPA * totalUnits - currentPoints) / futureUnits
        let maximumFinal = (currentPoints + maximumFutureGPA * futureUnits) / totalUnits
        let reachable = required <= maximumFutureGPA && required >= 0

        var minimum: Decimal?
        var additional: Decimal?
        if targetGPA > currentGPA {
            let denominator = maximumFutureGPA - targetGPA
            if denominator > 0 {
                let needed = (targetGPA * currentUnits - currentPoints) / denominator
                minimum = max(0, needed)
                additional = max(0, needed - futureUnits)
            }
        }

        return TargetGPAResult(requiredFutureGPA: required, maximumFinalGPA: maximumFinal,
                               isReachable: reachable, minimumTotalFutureUnits: minimum,
                               additionalUnitsNeeded: additional)
    }
}

