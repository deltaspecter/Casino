import Foundation

/// Zentrale Zufallsquelle für alle Spiele.
///
/// Produktiv wird ausschließlich `SystemRandomSource` verwendet. Sie basiert auf
/// `SystemRandomNumberGenerator`, der auf Apple-Plattformen den kryptografisch
/// sicheren Systemgenerator (`arc4random_buf` / CSPRNG des Kernels) nutzt.
///
/// Es gibt bewusst **keine** Stellschraube, um Ergebnisse zu beeinflussen:
/// keine Gewinnquoten-Steuerung, keine Abhängigkeit vom Kontostand, keine
/// „Near-Miss“-Logik. Jede Ziehung ist unabhängig von allen vorherigen.
///
/// `SeededRandomSource` existiert nur, damit Unit-Tests reproduzierbar sind.
public protocol RandomSource: AnyObject {
    func next() -> UInt64
}

public extension RandomSource {
    /// Gleichverteilte ganze Zahl in `0..<upperBound` (ohne Modulo-Bias,
    /// die Standardbibliothek verwendet Lemires Verfahren).
    func uniform(_ upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound muss positiv sein")
        var generator = RandomSourceGenerator(source: self)
        return Int.random(in: 0..<upperBound, using: &generator)
    }

    /// Gleichverteilte Gleitkommazahl in `0..<1`.
    func unitDouble() -> Double {
        var generator = RandomSourceGenerator(source: self)
        return Double.random(in: 0..<1, using: &generator)
    }

    /// `true` mit Wahrscheinlichkeit `p`.
    func chance(_ p: Double) -> Bool {
        unitDouble() < p
    }

    /// Fisher-Yates-Mischung (Durstenfeld-Variante) – jede Permutation ist gleich wahrscheinlich.
    func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = uniform(i + 1)
            if i != j { array.swapAt(i, j) }
        }
    }

    func pick<T>(_ array: [T]) -> T? {
        array.isEmpty ? nil : array[uniform(array.count)]
    }
}

/// Adapter, damit eine `RandomSource` überall dort genutzt werden kann,
/// wo die Standardbibliothek einen `RandomNumberGenerator` erwartet.
public struct RandomSourceGenerator: RandomNumberGenerator {
    public let source: RandomSource
    public init(source: RandomSource) { self.source = source }
    public mutating func next() -> UInt64 { source.next() }
}

/// Produktive Zufallsquelle (kryptografisch sicherer Systemgenerator).
public final class SystemRandomSource: RandomSource {
    private var generator = SystemRandomNumberGenerator()
    private let lock = NSLock()

    public init() {}

    public func next() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generator.next()
    }
}

/// Deterministische Quelle (SplitMix64) – **nur für Tests**.
public final class SeededRandomSource: RandomSource {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
