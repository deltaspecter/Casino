/**
 * Zentrale Zufallsquelle für alle Spiele (Port von `RandomSource.swift`).
 *
 * Produktiv wird ausschließlich `SystemRandomSource` verwendet. Sie basiert auf
 * `crypto.getRandomValues` (kryptografisch sicherer Generator des Browsers / von Node).
 *
 * Es gibt bewusst **keine** Stellschraube, um Ergebnisse zu beeinflussen:
 * keine Gewinnquoten-Steuerung, keine Abhängigkeit vom Kontostand, keine
 * „Near-Miss“-Logik. Jede Ziehung ist unabhängig von allen vorherigen.
 *
 * `SeededRandomSource` (SplitMix64, bitgleich zur Swift-Version) existiert nur,
 * damit Unit-Tests reproduzierbar sind.
 *
 * Die Ableitungen (`uniform`, `unitDouble`, `shuffle`) folgen exakt den Algorithmen der
 * Swift-Standardbibliothek (Lemire-Verfahren ohne Modulo-Bias für `Int.random(in:)`,
 * 53 Zufallsbits für `Double.random(in: 0..<1)`), damit gleiche Seeds gleiche Ergebnisse liefern.
 */

const TWO_32 = 0x1_0000_0000;

export interface RandomSource {
  /** Nächste 64 Zufallsbits als BigInt (wie `next() -> UInt64` in Swift). */
  next(): bigint;
  /** Gleichverteilte ganze Zahl in `0..<upperBound` ohne Modulo-Bias (Swift: `uniform`). */
  uniform(upperBound: number): number;
  /** Alias für `uniform`. */
  nextInt(upperBound: number): number;
  /** Gleichverteilte Gleitkommazahl in `0..<1`. */
  unitDouble(): number;
  /** `true` mit Wahrscheinlichkeit `p`. */
  chance(p: number): boolean;
  /** Fisher-Yates-Mischung (Durstenfeld-Variante), mischt das Array an Ort und Stelle. */
  shuffle<T>(array: T[]): void;
  /** Zufälliges Element oder `null` bei leerem Array. */
  pick<T>(array: readonly T[]): T | null;
}

/**
 * Gemeinsame Ableitungen für alle Quellen. Unterklassen liefern nur 64 Zufallsbits
 * über `fill64()` in `hi` / `lo` (jeweils vorzeichenlose 32 Bit).
 */
export abstract class BaseRandomSource implements RandomSource {
  protected hi = 0;
  protected lo = 0;

  /** Erzeugt die nächsten 64 Bit und legt sie in `this.hi` / `this.lo` ab. */
  protected abstract fill64(): void;

  next(): bigint {
    this.fill64();
    return (BigInt(this.hi) << 32n) | BigInt(this.lo);
  }

  uniform(upperBound: number): number {
    if (!Number.isInteger(upperBound) || upperBound <= 0) {
      throw new RangeError('upperBound muss positiv sein');
    }
    if (upperBound > 0xffff_ffff) return this.uniformLarge(upperBound);
    // Lemire: m = random * upperBound (128 Bit); Ergebnis = obere 64 Bit.
    const n = upperBound;
    let threshold = -1;
    for (;;) {
      this.fill64();
      const [high, lowHi, lowLo] = mulFull(this.hi, this.lo, n);
      // m.low < upperBound?
      if (lowHi !== 0 || lowLo >= n) return high;
      if (threshold < 0) threshold = Number((1n << 64n) % BigInt(n)); // (0 &- n) % n
      if (lowLo >= threshold) return high;
    }
  }

  nextInt(upperBound: number): number {
    return this.uniform(upperBound);
  }

  unitDouble(): number {
    // Swift: Double(next() & (2^53 - 1)) * 2^-53
    this.fill64();
    return ((this.hi & 0x1f_ffff) * TWO_32 + this.lo) * 2 ** -53;
  }

  chance(p: number): boolean {
    return this.unitDouble() < p;
  }

  shuffle<T>(array: T[]): void {
    shuffle(array, this);
  }

  pick<T>(array: readonly T[]): T | null {
    return array.length === 0 ? null : array[this.uniform(array.length)]!;
  }

  /** Seltener Pfad für sehr große Obergrenzen (> 2^32 - 1), exakt per BigInt. */
  private uniformLarge(upperBound: number): number {
    const n = BigInt(upperBound);
    const mask = (1n << 64n) - 1n;
    const t = (1n << 64n) % n;
    for (;;) {
      const m = this.next() * n;
      const low = m & mask;
      if (low >= n || low >= t) return Number(m >> 64n);
    }
  }
}

/**
 * Multipliziert die 64-Bit-Zahl (hi, lo) mit n < 2^32.
 * Liefert [obere 64 Bit (passen in eine Zahl < n), untere 64 Bit hi32, untere 64 Bit lo32].
 */
function mulFull(hi: number, lo: number, n: number): [number, number, number] {
  const nl = n & 0xffff;
  const nh = n >>> 16;
  // a = lo * n
  const [aLo, aHi] = mul32x32(lo, nl, nh);
  // b = hi * n
  const [bLo, bHi] = mul32x32(hi, nl, nh);
  // Produkt = b * 2^32 + a
  const mid = aHi + bLo;
  const midLo = mid % TWO_32;
  const carry = Math.floor(mid / TWO_32);
  return [bHi + carry, midLo, aLo];
}

/** x (32 Bit) * n (als nl + nh*2^16) → [lo32, hi32] exakt. */
function mul32x32(x: number, nl: number, nh: number): [number, number] {
  const p0 = x * nl; // < 2^48
  const p1 = x * nh; // < 2^48
  const p0Lo = p0 % TWO_32;
  const p0Hi = Math.floor(p0 / TWO_32);
  const p1Lo16 = p1 % 0x1_0000;
  const p1Hi = Math.floor(p1 / 0x1_0000);
  const sum = p0Lo + p1Lo16 * 0x1_0000;
  const lo = sum % TWO_32;
  const carry = Math.floor(sum / TWO_32);
  return [lo, p0Hi + p1Hi + carry];
}

/** Fisher-Yates-Mischung (Durstenfeld-Variante) – jede Permutation ist gleich wahrscheinlich. */
export function shuffle<T>(array: T[], random: RandomSource): void {
  if (array.length <= 1) return;
  for (let i = array.length - 1; i > 0; i--) {
    const j = random.uniform(i + 1);
    if (i !== j) {
      const tmp = array[i]!;
      array[i] = array[j]!;
      array[j] = tmp;
    }
  }
}

/** Produktive Zufallsquelle (kryptografisch sicherer Systemgenerator, `crypto.getRandomValues`). */
export class SystemRandomSource extends BaseRandomSource {
  private readonly buffer = new Uint32Array(256);
  private cursor = 256;

  protected fill64(): void {
    if (this.cursor >= this.buffer.length) {
      globalThis.crypto.getRandomValues(this.buffer);
      this.cursor = 0;
    }
    this.hi = this.buffer[this.cursor]!;
    this.lo = this.buffer[this.cursor + 1]!;
    this.cursor += 2;
  }
}

/** Deterministische Quelle (SplitMix64, bitgleich zu Swift) – **nur für Tests**. */
export class SeededRandomSource extends BaseRandomSource {
  private sHi: number;
  private sLo: number;

  constructor(seed: number | bigint) {
    super();
    const s = BigInt.asUintN(64, BigInt(seed));
    this.sHi = Number(s >> 32n);
    this.sLo = Number(s & 0xffff_ffffn);
  }

  protected fill64(): void {
    // state &+= 0x9E3779B97F4A7C15
    let lo = this.sLo + 0x7f4a_7c15;
    const carry = lo >= TWO_32 ? 1 : 0;
    lo = lo >>> 0;
    const hi = (this.sHi + 0x9e37_79b9 + carry) >>> 0;
    this.sHi = hi;
    this.sLo = lo;

    let zh = hi;
    let zl = lo;
    // z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    [zh, zl] = xorShiftRight(zh, zl, 30);
    [zh, zl] = mul64(zh, zl, 0xbf58_476d, 0x1ce4_e5b9);
    // z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    [zh, zl] = xorShiftRight(zh, zl, 27);
    [zh, zl] = mul64(zh, zl, 0x94d0_49bb, 0x1331_11eb);
    // z ^ (z >> 31)
    [zh, zl] = xorShiftRight(zh, zl, 31);
    this.hi = zh;
    this.lo = zl;
  }
}

/** z ^ (z >> k) für 0 < k < 32. */
function xorShiftRight(hi: number, lo: number, k: number): [number, number] {
  const sHi = hi >>> k;
  const sLo = ((lo >>> k) | (hi << (32 - k))) >>> 0;
  return [(hi ^ sHi) >>> 0, (lo ^ sLo) >>> 0];
}

/** (ah, al) * (bh, bl) mod 2^64. */
function mul64(ah: number, al: number, bh: number, bl: number): [number, number] {
  const a0 = al & 0xffff;
  const a1 = al >>> 16;
  const b0 = bl & 0xffff;
  const b1 = bl >>> 16;
  const t = a0 * b0;
  const m = a1 * b0 + a0 * b1;
  const low = t + (m % 0x1_0000) * 0x1_0000;
  const lo = low % TWO_32;
  const carry = Math.floor(low / TWO_32);
  const hiFromLow = a1 * b1 + Math.floor(m / 0x1_0000) + carry;
  const hi = (hiFromLow + Math.imul(ah, bl) + Math.imul(al, bh)) >>> 0;
  return [hi, lo >>> 0];
}
