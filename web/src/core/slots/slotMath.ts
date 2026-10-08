import { SlotMachine, type SlotMachineDefinition } from './slotMachine';

export interface SlotMathReport {
  /** Return to Player (z. B. 0.95 = 95 %) */
  readonly rtp: number;
  readonly lineReturn: number;
  readonly scatterReturn: number;
}

/**
 * Exakte (nicht simulierte) Berechnung der theoretischen Auszahlungsquote.
 * Dient der Transparenz: Die angezeigte Quote ergibt sich allein aus
 * Walzenstreifen und Auszahlungstabelle.
 */
export const SlotMath = {
  report(definition: SlotMachineDefinition): SlotMathReport {
    const machine = new SlotMachine(definition);

    // Wahrscheinlichkeit je Symbol und Walze an einer festen Zeile
    const probabilities: [string, number][][] = definition.reelStrips.map((strip) => {
      const counts = new Map<string, number>();
      for (const s of strip) counts.set(s, (counts.get(s) ?? 0) + 1);
      return [...counts.entries()]
        .map(([k, v]): [string, number] => [k, v / strip.length])
        .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
    });

    // Erwartungswert einer Linie (in Linieneinsätzen) über alle Symbolkombinationen
    let lineEV = 0;
    const current: string[] = [];
    const recurse = (reel: number, p: number): void => {
      if (reel === probabilities.length) {
        const win = machine.evaluateLine(current);
        if (win) lineEV += p * win.multiplier;
        return;
      }
      for (const [symbol, q] of probabilities[reel]!) {
        current.push(symbol);
        recurse(reel + 1, p * q);
        current.pop();
      }
    };
    recurse(0, 1);

    // Scatter: Verteilung der Scatter-Anzahl je Walzenfenster, dann Faltung
    let scatterEV = 0;
    const scatter = definition.symbols.find((s) => s.kind === 'scatter');
    if (scatter) {
      let distribution: number[] = [1];
      definition.reelStrips.forEach((strip, reel) => {
        const perReel = new Array<number>(definition.rows + 1).fill(0);
        for (let stop = 0; stop < strip.length; stop++) {
          const n = machine.window(reel, stop).filter((s) => s === scatter.id).length;
          perReel[n] = perReel[n]! + 1 / strip.length;
        }
        const next = new Array<number>(distribution.length + definition.rows).fill(0);
        distribution.forEach((pa, a) => {
          if (pa <= 0) return;
          perReel.forEach((pb, b) => {
            if (pb > 0) next[a + b] = next[a + b]! + pa * pb;
          });
        });
        distribution = next;
      });
      distribution.forEach((p, n) => {
        scatterEV += p * scatter.payout(Math.min(n, 5));
      });
    }
    return { rtp: lineEV + scatterEV, lineReturn: lineEV, scatterReturn: scatterEV };
  },
};
