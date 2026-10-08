import { SlotMachineDefinition, SlotSymbol } from './slotMachine';

/** Erzeugt einen festen, gleichmäßig verteilten Walzenstreifen (identisch zu Swift). */
function makeStrip(reel: number, weights: readonly (readonly [string, number])[]): string[] {
  const length = weights.reduce((s, w) => s + w[1], 0);
  const slots: (string | null)[] = new Array<string | null>(length).fill(null);
  // Seltene Symbole zuerst platzieren, damit sie gut verteilt sind (stabile Sortierung wie Swift)
  const indexed = weights.map((w, index) => ({ index, symbol: w[0], count: w[1] }));
  indexed.sort((a, b) => a.count - b.count);
  for (const { index, symbol, count } of indexed) {
    const spacing = length / count;
    const offset = (reel * 7 + index * 3) % length;
    for (let k = 0; k < count; k++) {
      let position = Math.round(offset + k * spacing) % length;
      while (slots[position] !== null) position = (position + 1) % length;
      slots[position] = symbol;
    }
  }
  return slots.map((s) => s!);
}

/** 10 Gewinnlinien für ein 5×3-Raster (Zeile 0 = oben). */
const standardPaylines: readonly (readonly number[])[] = [
  [1, 1, 1, 1, 1],
  [0, 0, 0, 0, 0],
  [2, 2, 2, 2, 2],
  [0, 1, 2, 1, 0],
  [2, 1, 0, 1, 2],
  [1, 0, 0, 0, 1],
  [1, 2, 2, 2, 1],
  [0, 0, 1, 2, 2],
  [2, 2, 1, 0, 0],
  [1, 2, 1, 0, 1],
];

const lineBetOptions = [1, 2, 5, 10, 25, 50, 100];
const reels = (weights: readonly (readonly [string, number])[]): string[][] =>
  [0, 1, 2, 3, 4].map((reel) => makeStrip(reel, weights));

const crimsonSevens = new SlotMachineDefinition({
  id: 'crimson-sevens',
  name: 'Crimson Sevens',
  tagline: 'Der rote Klassiker',
  symbols: [
    new SlotSymbol('cherry', { 3: 7, 4: 20, 5: 65 }),
    new SlotSymbol('lemon', { 3: 7, 4: 20, 5: 65 }),
    new SlotSymbol('plum', { 3: 10, 4: 34, 5: 100 }),
    new SlotSymbol('bell', { 3: 17, 4: 60, 5: 170 }),
    new SlotSymbol('bar', { 3: 30, 4: 100, 5: 340 }),
    new SlotSymbol('seven', { 3: 65, 4: 250, 5: 1250 }),
    new SlotSymbol('wild', { 3: 125, 4: 500, 5: 3000 }, 'wild'),
    new SlotSymbol('scatter', { 3: 2, 4: 10, 5: 50 }, 'scatter'),
  ],
  reelStrips: reels([
    ['cherry', 7], ['lemon', 7], ['plum', 6], ['bell', 5],
    ['bar', 4], ['seven', 2], ['wild', 1], ['scatter', 1],
  ]),
  paylines: standardPaylines,
  rows: 3,
  lineBetOptions,
});

const midnightGems = new SlotMachineDefinition({
  id: 'midnight-gems',
  name: 'Midnight Gems',
  tagline: 'Edelsteine im Mondlicht',
  symbols: [
    new SlotSymbol('topaz', { 3: 6, 4: 16, 5: 56 }),
    new SlotSymbol('amethyst', { 3: 8, 4: 22, 5: 72 }),
    new SlotSymbol('emerald', { 3: 11, 4: 35, 5: 112 }),
    new SlotSymbol('sapphire', { 3: 16, 4: 56, 5: 176 }),
    new SlotSymbol('ruby', { 3: 29, 4: 112, 5: 400 }),
    new SlotSymbol('diamond', { 3: 56, 4: 224, 5: 960 }),
    new SlotSymbol('wild', { 3: 100, 4: 400, 5: 2400 }, 'wild'),
    new SlotSymbol('scatter', { 3: 2, 4: 12, 5: 60 }, 'scatter'),
  ],
  reelStrips: reels([
    ['topaz', 8], ['amethyst', 7], ['emerald', 6], ['sapphire', 5],
    ['ruby', 3], ['diamond', 2], ['wild', 1], ['scatter', 1],
  ]),
  paylines: standardPaylines,
  rows: 3,
  lineBetOptions,
});

const dragonFortune = new SlotMachineDefinition({
  id: 'dragon-fortune',
  name: 'Dragon Fortune',
  tagline: 'Hohe Volatilität, große Momente',
  symbols: [
    new SlotSymbol('coin', { 3: 5, 4: 15, 5: 45 }),
    new SlotSymbol('lantern', { 3: 6, 4: 18, 5: 60 }),
    new SlotSymbol('fan', { 3: 9, 4: 30, 5: 90 }),
    new SlotSymbol('koi', { 3: 15, 4: 60, 5: 190 }),
    new SlotSymbol('tiger', { 3: 38, 4: 150, 5: 600 }),
    new SlotSymbol('dragon', { 3: 90, 4: 450, 5: 2250 }),
    new SlotSymbol('wild', { 3: 150, 4: 750, 5: 7500 }, 'wild'),
    new SlotSymbol('scatter', { 3: 3, 4: 15, 5: 100 }, 'scatter'),
  ],
  reelStrips: reels([
    ['coin', 8], ['lantern', 7], ['fan', 6], ['koi', 4],
    ['tiger', 3], ['dragon', 1], ['wild', 1], ['scatter', 1],
  ]),
  paylines: standardPaylines,
  rows: 3,
  lineBetOptions,
});

/**
 * Die Automaten von BlackCasino. Alle Werte sind fest definiert und öffentlich einsehbar;
 * die theoretische Auszahlungsquote wird mit `SlotMath` exakt berechnet und im Spiel angezeigt.
 */
export const SlotCatalog = {
  crimsonSevens,
  midnightGems,
  dragonFortune,
  all: [crimsonSevens, midnightGems, dragonFortune] as readonly SlotMachineDefinition[],
  standardPaylines,
  makeStrip,
  byID(id: string): SlotMachineDefinition | null {
    return [crimsonSevens, midnightGems, dragonFortune].find((d) => d.id === id) ?? null;
  },
};
