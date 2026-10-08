import { describe, expect, it } from 'vitest';
import { PlayerProfile, SeededRandomSource, SlotCatalog, SlotMachine, SlotMath, WalletError } from '../src/core';

describe('Slots', () => {
  it('definitions are complete', () => {
    for (const def of SlotCatalog.all) {
      expect(def.reelCount).toBe(5);
      expect(def.rows).toBe(3);
      expect(def.paylines.length).toBe(10);
      expect(def.paylines.every((l) => l.length === 5 && l.every((r) => r >= 0 && r < 3))).toBe(true);
      expect(def.symbols.filter((s) => s.kind === 'wild').length).toBe(1);
      expect(def.symbols.filter((s) => s.kind === 'scatter').length).toBe(1);
      for (let reel = 0; reel < def.reelCount; reel++) {
        for (const symbol of def.reelStrips[reel]!) expect(def.symbols.find((s) => s.id === symbol)).toBeDefined();
        const total = def.symbols.reduce((acc, s) => acc + def.probability(s.id, reel), 0);
        expect(Math.abs(total - 1), 'Wahrscheinlichkeiten je Walze summieren sich zu 1').toBeLessThan(1e-9);
      }
    }
  });

  it('reel strips are the fixed Swift strips', () => {
    const cs = SlotCatalog.crimsonSevens;
    expect(cs.reelStrips[0]!.length).toBe(33);
    expect(cs.count('seven', 0)).toBe(2);
    expect(cs.count('wild', 3)).toBe(1);
    expect(cs.probability('cherry', 2)).toBeCloseTo(7 / 33, 12);
    expect(SlotCatalog.midnightGems.reelStrips[4]!.length).toBe(33);
    expect(SlotCatalog.dragonFortune.reelStrips[1]!.length).toBe(31);
    // Streifen sind deterministisch und unterscheiden sich je Walze
    expect(SlotCatalog.makeStrip(0, [['a', 2], ['b', 1]])).toEqual(SlotCatalog.makeStrip(0, [['a', 2], ['b', 1]]));
    expect(cs.reelStrips[0]).not.toEqual(cs.reelStrips[1]);
  });

  /** Jede Symbolkombination (3, 4, 5 gleiche) zahlt genau den Wert der Gewinntabelle. */
  it('every winning combination pays table', () => {
    for (const def of SlotCatalog.all) {
      const machine = new SlotMachine(def);
      const regular = def.symbols.filter((s) => s.kind === 'regular');
      for (const symbol of regular) {
        const blocker = regular.find((s) => s.id !== symbol.id)!.id;
        for (let n = 3; n <= 5; n++) {
          const line = [...Array<string>(n).fill(symbol.id), ...Array<string>(5 - n).fill(blocker)];
          const win = machine.evaluateLine(line);
          expect(win?.symbol, `${def.name} ${symbol.id} ×${n}`).toBe(symbol.id);
          expect(win?.count).toBe(n);
          expect(win?.multiplier).toBe(symbol.payout(n));
        }
        expect(machine.evaluateLine([symbol.id, symbol.id, blocker, blocker, blocker]), 'Zwei gleiche zahlen nicht').toBeNull();
      }
      const wild = def.symbols.find((s) => s.kind === 'wild')!;
      const scatter = def.symbols.find((s) => s.kind === 'scatter')!;
      for (let n = 3; n <= 5; n++) {
        const line = [...Array<string>(n).fill(wild.id), ...Array<string>(5 - n).fill(scatter.id)];
        expect(machine.evaluateLine(line)?.multiplier).toBe(wild.payout(n));
      }
    }
  });

  it('wild substitution and no wins', () => {
    const machine = new SlotMachine(SlotCatalog.crimsonSevens);
    expect(machine.evaluateLine(['wild', 'seven', 'seven', 'seven', 'bar'])?.symbol).toBe('seven');
    expect(machine.evaluateLine(['wild', 'seven', 'seven', 'seven', 'bar'])?.count).toBe(4);
    expect(machine.evaluateLine(['seven', 'wild', 'seven', 'bar', 'bar'])?.count).toBe(3);
    expect(machine.evaluateLine(['wild', 'wild', 'wild', 'cherry', 'lemon'])?.symbol, 'Höherer Gewinn (Wild-Kette) wird gezahlt').toBe('wild');
    expect(machine.evaluateLine(['cherry', 'lemon', 'cherry', 'cherry', 'cherry']), 'Nur von links').toBeNull();
    expect(machine.evaluateLine(['scatter', 'scatter', 'scatter', 'cherry', 'cherry']), 'Scatter zahlt nicht auf Linien').toBeNull();
    expect(machine.evaluateLine(['wild', 'scatter', 'seven', 'seven', 'seven']), 'Wild ersetzt keinen Scatter').toBeNull();
  });

  it('scatter pays anywhere', () => {
    for (const def of SlotCatalog.all) {
      const machine = new SlotMachine(def);
      const scatter = def.symbols.find((s) => s.kind === 'scatter')!;
      const withScatter: number[] = [];
      const without: number[] = [];
      for (let reel = 0; reel < 5; reel++) {
        const n = def.reelStrips[reel]!.length;
        const stops = Array.from({ length: n }, (_, i) => i);
        withScatter.push(stops.find((s) => machine.window(reel, s).filter((x) => x === scatter.id).length === 1)!);
        without.push(stops.find((s) => !machine.window(reel, s).includes(scatter.id))!);
      }
      for (let k = 0; k <= 5; k++) {
        const stops = [0, 1, 2, 3, 4].map((r) => (r < k ? withScatter[r]! : without[r]!));
        const result = machine.evaluate(stops, 2);
        expect(result.scatterCount).toBe(k);
        expect(result.scatterPayout).toBe(scatter.payout(k) * result.totalBet);
        expect(result.scatterPositions.length).toBe(result.scatterPayout > 0 ? k : 0);
      }
    }
  });

  it('payout scales linearly with bet', () => {
    const machine = new SlotMachine(SlotCatalog.dragonFortune);
    const random = new SeededRandomSource(12);
    for (let i = 0; i < 2_000; i++) {
      const r1 = machine.spin(1, random);
      const r7 = machine.evaluate(r1.stops, 7);
      expect(r7.totalPayout).toBe(r1.totalPayout * 7);
      expect(r7.totalBet).toBe(r1.totalBet * 7);
    }
  });

  it('no-win spins exist and pay zero', () => {
    const machine = new SlotMachine(SlotCatalog.midnightGems);
    const random = new SeededRandomSource(5);
    let losses = 0;
    for (let i = 0; i < 1_000; i++) {
      const r = machine.spin(2, random);
      expect(r).toEqual(machine.evaluate(r.stops, 2));
      if (!r.isWin) {
        losses += 1;
        expect(r.totalPayout).toBe(0);
        expect(r.lineWins.length).toBe(0);
      } else {
        expect(r.winMultiplier).toBeCloseTo(r.totalPayout / r.totalBet, 12);
      }
    }
    expect(losses).toBeGreaterThan(0);
  });

  it('line wins carry positions', () => {
    const machine = new SlotMachine(SlotCatalog.crimsonSevens);
    const random = new SeededRandomSource(2);
    let checked = 0;
    for (let i = 0; i < 2_000 && checked < 20; i++) {
      const r = machine.spin(1, random);
      for (const w of r.lineWins) {
        checked += 1;
        expect(w.positions.length).toBe(w.count);
        expect(w.id).toBe(w.lineIndex);
        w.positions.forEach((p, k) => {
          expect(p.reel).toBe(k);
          expect(p.row).toBe(SlotCatalog.standardPaylines[w.lineIndex]![k]);
        });
      }
    }
    expect(checked).toBeGreaterThan(0);
  });

  it('low balance cannot spin', () => {
    const profile = new PlayerProfile();
    profile.debit(profile.chips - 5);
    const totalBet = SlotCatalog.crimsonSevens.lineBetOptions[0]! * 10;
    expect(() => profile.debit(totalBet)).toThrow(WalletError);
    expect(profile.chips, 'Kontostand bleibt unverändert und nie negativ').toBe(5);
  });

  it('RTP exact and simulated', () => {
    const expected: Record<string, number> = { 'crimson-sevens': 0.951, 'midnight-gems': 0.942, 'dragon-fortune': 0.949 };
    for (const def of SlotCatalog.all) {
      const report = SlotMath.report(def);
      expect(report.rtp, def.name).toBeGreaterThan(0.92);
      expect(report.rtp, def.name).toBeLessThan(0.98);
      expect(Math.abs(report.rtp - expected[def.id]!), `${def.name} RTP ≈ ${expected[def.id]}`).toBeLessThan(0.0006);
      expect(report.lineReturn + report.scatterReturn).toBeCloseTo(report.rtp, 12);

      const machine = new SlotMachine(def);
      const random = new SeededRandomSource(77);
      let bet = 0;
      let won = 0;
      for (let i = 0; i < 300_000; i++) {
        const r = machine.spin(1, random);
        bet += r.totalBet;
        won += r.totalPayout;
      }
      expect(Math.abs(won / bet - report.rtp), def.name).toBeLessThanOrEqual(0.05);
    }
  }, 60_000);
});
