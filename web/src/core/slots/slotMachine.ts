import type { RandomSource } from '../random';

export type SlotSymbolKind = 'regular' | 'wild' | 'scatter';

export class SlotSymbol {
  readonly id: string;
  readonly kind: SlotSymbolKind;
  /** Auszahlung pro Linieneinsatz für 3, 4 bzw. 5 Treffer (Scatter: × Gesamteinsatz). */
  readonly pays: Readonly<Record<number, number>>;

  constructor(id: string, pays: Record<number, number>, kind: SlotSymbolKind = 'regular') {
    this.id = id;
    this.kind = kind;
    this.pays = Object.freeze({ ...pays });
  }

  payout(count: number): number {
    return this.pays[count] ?? 0;
  }
}

export interface SlotMachineDefinitionInit {
  id: string;
  name: string;
  tagline: string;
  symbols: readonly SlotSymbol[];
  reelStrips: readonly (readonly string[])[];
  paylines: readonly (readonly number[])[];
  rows: number;
  lineBetOptions: readonly number[];
}

/** Konfiguration eines Automaten: Walzenstreifen, Gewinnlinien und Auszahlungstabelle. */
export class SlotMachineDefinition {
  readonly id: string;
  readonly name: string;
  readonly tagline: string;
  readonly symbols: readonly SlotSymbol[];
  /** Pro Walze die physische Symbolfolge (Symbol-IDs). */
  readonly reelStrips: readonly (readonly string[])[];
  /** Jede Linie: Zeilenindex (0 = oben) je Walze. */
  readonly paylines: readonly (readonly number[])[];
  readonly rows: number;
  readonly lineBetOptions: readonly number[];

  constructor(init: SlotMachineDefinitionInit) {
    this.id = init.id;
    this.name = init.name;
    this.tagline = init.tagline;
    this.symbols = Object.freeze([...init.symbols]);
    this.reelStrips = Object.freeze(init.reelStrips.map((s) => Object.freeze([...s])));
    this.paylines = Object.freeze(init.paylines.map((l) => Object.freeze([...l])));
    this.rows = init.rows;
    this.lineBetOptions = Object.freeze([...init.lineBetOptions]);
  }

  get reelCount(): number { return this.reelStrips.length; }

  symbol(id: string): SlotSymbol {
    const s = this.symbols.find((x) => x.id === id);
    if (!s) throw new Error(`Unbekanntes Symbol ${id}`);
    return s;
  }

  /**
   * Wahrscheinlichkeit, dass `symbolID` an einer beliebigen festen Position von Walze `reel` erscheint.
   * Ergibt sich direkt aus dem Walzenstreifen: Anzahl des Symbols / Streifenlänge.
   */
  probability(symbolID: string, reel: number): number {
    const strip = this.reelStrips[reel]!;
    return this.count(symbolID, reel) / strip.length;
  }

  /** Anzahl eines Symbols auf einer Walze. */
  count(symbolID: string, reel: number): number {
    return this.reelStrips[reel]!.filter((s) => s === symbolID).length;
  }
}

export interface SlotPosition {
  readonly reel: number;
  readonly row: number;
}

export interface LineWin {
  readonly lineIndex: number;
  readonly symbolID: string;
  readonly count: number;
  readonly payout: number;
  /** Positionen (Walze, Zeile) der gewinnenden Symbole. */
  readonly positions: readonly SlotPosition[];
  /** = lineIndex */
  readonly id: number;
}

export interface SpinResult {
  /** Stoppposition je Walze auf ihrem Streifen. */
  readonly stops: readonly number[];
  /** Sichtbares Raster `[walze][zeile]` als Symbol-IDs. */
  readonly grid: readonly (readonly string[])[];
  readonly lineWins: readonly LineWin[];
  readonly scatterCount: number;
  readonly scatterPayout: number;
  /** Nur gefüllt, wenn der Scatter etwas zahlt. */
  readonly scatterPositions: readonly SlotPosition[];
  readonly totalBet: number;
  /** Summe aller Linien- und Scatter-Gewinne. */
  readonly totalPayout: number;
  readonly isWin: boolean;
  /** totalPayout / totalBet */
  readonly winMultiplier: number;
}

export interface LineEvaluation {
  readonly symbol: string;
  readonly count: number;
  readonly multiplier: number;
}

/**
 * Spielautomat. Jede Walze stoppt an einer **unabhängig und gleichverteilt**
 * gezogenen Position ihres Streifens. Es gibt keinen Zustand zwischen Drehungen,
 * keine Gewinnserien-Steuerung und keine Abhängigkeit vom Kontostand.
 */
export class SlotMachine {
  readonly definition: SlotMachineDefinition;
  private readonly wildID: string | null;
  private readonly scatter: SlotSymbol | null;

  constructor(definition: SlotMachineDefinition) {
    this.definition = definition;
    this.wildID = definition.symbols.find((s) => s.kind === 'wild')?.id ?? null;
    this.scatter = definition.symbols.find((s) => s.kind === 'scatter') ?? null;
  }

  spin(lineBet: number, random: RandomSource): SpinResult {
    const stops = this.definition.reelStrips.map((strip) => random.uniform(strip.length));
    return this.evaluate(stops, lineBet);
  }

  /** Sichtbare Symbole einer Walze, wenn sie an `stop` hält (oberste Zeile = `stop`). */
  window(reel: number, stop: number): string[] {
    const strip = this.definition.reelStrips[reel]!;
    const out: string[] = [];
    for (let row = 0; row < this.definition.rows; row++) out.push(strip[(stop + row) % strip.length]!);
    return out;
  }

  evaluate(stops: readonly number[], lineBet: number): SpinResult {
    const grid = stops.map((stop, reel) => this.window(reel, stop));
    const totalBet = lineBet * this.definition.paylines.length;

    const lineWins: LineWin[] = [];
    this.definition.paylines.forEach((line, lineIndex) => {
      const symbols = line.map((row, reel) => grid[reel]![row]!);
      const win = this.evaluateLine(symbols);
      if (win) {
        const positions: SlotPosition[] = [];
        for (let r = 0; r < win.count; r++) positions.push({ reel: r, row: line[r]! });
        lineWins.push({
          lineIndex, symbolID: win.symbol, count: win.count, payout: win.multiplier * lineBet, positions, id: lineIndex,
        });
      }
    });

    const scatterPositions: SlotPosition[] = [];
    let scatterPayout = 0;
    const scatter = this.scatter;
    if (scatter) {
      grid.forEach((column, reel) => {
        column.forEach((id, row) => {
          if (id === scatter.id) scatterPositions.push({ reel, row });
        });
      });
      scatterPayout = scatter.payout(Math.min(scatterPositions.length, 5)) * totalBet;
    }

    const totalPayout = lineWins.reduce((s, w) => s + w.payout, 0) + scatterPayout;
    return {
      stops: [...stops],
      grid,
      lineWins,
      scatterCount: scatterPositions.length,
      scatterPayout,
      scatterPositions: scatterPayout > 0 ? scatterPositions : [],
      totalBet,
      totalPayout,
      isWin: totalPayout > 0,
      winMultiplier: totalBet > 0 ? totalPayout / totalBet : 0,
    };
  }

  /**
   * Wertet eine Linie von links nach rechts aus. Wilds ersetzen alle regulären Symbole.
   * Gezahlt wird die höhere von „reiner Wild-Kette“ und „ersetztem Symbol“.
   */
  evaluateLine(symbols: readonly string[]): LineEvaluation | null {
    const wildID = this.wildID;
    const scatterID = this.scatter?.id ?? null;

    // Reine Wild-Kette
    let wildRun = 0;
    if (wildID !== null) {
      for (const s of symbols) {
        if (s === wildID) wildRun += 1; else break;
      }
    }
    let best: LineEvaluation | null = null;
    if (wildID !== null && wildRun >= 3) {
      const pay = this.definition.symbol(wildID).payout(wildRun);
      if (pay > 0) best = { symbol: wildID, count: wildRun, multiplier: pay };
    }

    // Erstes Nicht-Wild-Symbol bestimmt die Linie
    const target = symbols.find((s) => s !== wildID);
    if (target === undefined || target === scatterID) return best;
    let count = 0;
    for (const s of symbols) {
      if (s === target || s === wildID) count += 1; else break;
    }
    const pay = this.definition.symbol(target).payout(count);
    if (pay > 0 && pay > (best?.multiplier ?? 0)) {
      best = { symbol: target, count, multiplier: pay };
    }
    return best;
  }
}
