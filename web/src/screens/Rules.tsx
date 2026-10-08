import { useState } from 'preact/hooks'
import { Button, IconButton, NoCashValueNote, RuleList, SectionTitle, Sheet, SheetHeader } from '../ui/components'
import { Icon, type IconName } from '../ui/icons'
import { ChipFormat } from '../ui/format'

export type GameKind = 'blackjack' | 'poker' | 'slots'

export const GAME_TITLES: Record<GameKind, string> = { blackjack: 'Blackjack', poker: 'Poker', slots: 'Slots' }

export interface TableRulesInfo {
  minBet: number
  maxBet: number
  maxHands: number
}

/** Vollständiges, sichtbares Regelwerk für Blackjack und Poker. (Slot-Regeln stehen pro Automat in der Gewinntabelle.) */
export function RulesSheet({ game, blackjack, onClose }: { game: GameKind; blackjack?: TableRulesInfo; onClose: () => void }) {
  return (
    <Sheet onClose={onClose}>
      <div class="stack">
        <SheetHeader title={`RULES · ${GAME_TITLES[game].toUpperCase()}`}
          subtitle={game === 'blackjack' ? 'Regelwerk dieses Tisches' : "No-Limit Texas Hold'em"} onClose={onClose} />
        {game === 'blackjack' && blackjack && <BlackjackRules rules={blackjack} />}
        {game === 'poker' && <PokerRules />}
        <SectionTitle title="Zufall" />
        <RuleList items={[
          'Ablauf: Zufallsgenerator → Mischen → Kartenausgabe → Spielregeln → Ergebnis.',
          'Gemischt wird ein vollständiges 52-Karten-Deck mit dem Fisher-Yates-Verfahren und dem kryptografisch sicheren Zufallsgenerator des Browsers (Web Crypto).',
          'Keine Karte ist in einer Runde doppelt vorhanden.',
          'Ergebnisse hängen nicht von Kontostand, Einsatzhöhe, vorherigen Runden, Missionen, Erfolgen oder Daily Rewards ab.',
        ]} />
        <NoCashValueNote />
      </div>
    </Sheet>
  )
}

function BlackjackRules({ rules }: { rules: TableRulesInfo }) {
  return (
    <>
      <SectionTitle title="Tisch" />
      <RuleList items={[
        '1 Standard-Deck mit 52 Karten, vor jeder Runde vollständig neu gemischt.',
        `Einsatz: ${rules.minBet} bis ${ChipFormat.string(rules.maxBet)} Chips pro Hand.`,
        'Ausgabe: Spieler, Dealer (offen), Spieler, Dealer (verdeckt).',
      ]} />
      <SectionTitle title="Kartenwerte" />
      <RuleList items={[
        '2–10 zählen ihren Augenwert, Bube, Dame und König zählen 10.',
        'Ein Ass zählt 11 oder 1 – je nachdem, was die Hand nicht überkauft (Soft-Hand).',
        'Blackjack: Ass + 10er als erste zwei Karten (nicht nach einem Split).',
      ]} />
      <SectionTitle title="Spieler" />
      <RuleList items={[
        'Hit: weitere Karte · Stand: keine weitere Karte.',
        'Double Down: auf beliebige erste zwei Karten (auch nach Split) – Einsatz wird verdoppelt, genau eine weitere Karte.',
        `Split: zwei Karten gleichen Werts werden zu zwei Händen mit gleichem Einsatz, bis zu ${rules.maxHands} Hände.`,
        'Geteilte Asse erhalten je genau eine Karte und können nicht erneut geteilt werden.',
        'Bei 21 endet die Hand automatisch. Keine Insurance, kein Surrender.',
      ]} />
      <SectionTitle title="Dealer" />
      <RuleList items={[
        'Zeigt der Dealer ein Ass oder einen 10er, prüft er sofort auf Blackjack (Peek).',
        'Der Dealer zieht bis einschließlich 16 und steht auf allen 17 – auch auf Soft 17 (S17).',
        'Sind alle Spielerhände überkauft, zieht der Dealer keine weiteren Karten.',
      ]} />
      <SectionTitle title="Auszahlung" />
      <RuleList items={[
        'Blackjack zahlt 3:2 (Einsatz 100 → 250 zurück).',
        'Gewinn zahlt 1:1 · Push (Gleichstand) gibt den Einsatz zurück.',
        'Bust (über 21) verliert immer – auch wenn der Dealer danach überkaufen würde.',
        'Spieler- und Dealer-Blackjack gleichzeitig: Push.',
      ]} />
    </>
  )
}

function PokerRules() {
  return (
    <>
      <SectionTitle title="Ablauf einer Hand" />
      <RuleList items={[
        'Der Dealer-Button wandert pro Hand einen Platz weiter. Links davon zahlen Small Blind und Big Blind.',
        'Jeder Spieler erhält zwei verdeckte Hole Cards, reihum eine nach der anderen.',
        'Preflop: Setzrunde, beginnend links vom Big Blind (heads-up beginnt der Button).',
        'Flop: drei Gemeinschaftskarten, Turn: eine, River: eine – jeweils mit Burn-Karte und Setzrunde, beginnend links vom Button.',
        'Showdown: Die beste 5-Karten-Hand aus 2 Hole Cards und 5 Gemeinschaftskarten gewinnt.',
      ]} />
      <SectionTitle title="Aktionen" />
      <RuleList items={[
        'Fold: aussteigen · Check: schieben, wenn kein Einsatz offen ist · Call: offenen Einsatz bezahlen.',
        'Bet: erster Einsatz einer Runde (mindestens Big Blind) · Raise: erhöhen, mindestens um die letzte Erhöhung.',
        'All-in: alle verbleibenden Chips. Wer All-in ist, kann nur den Teil des Pots gewinnen, den er abgedeckt hat (Side-Pots).',
        'Eine Setzrunde endet, wenn alle aktiven Spieler gehandelt und gleich viel gesetzt haben.',
      ]} />
      <SectionTitle title="Handrangfolge (höchste zuerst)" />
      <RuleList numbered items={[
        'Royal Flush – A K Q J 10 einer Farbe',
        'Straight Flush – fünf aufeinanderfolgende Karten einer Farbe',
        'Four of a Kind (Vierling)',
        'Full House – Drilling + Paar',
        'Flush – fünf Karten einer Farbe',
        'Straight (Straße) – fünf aufeinanderfolgende Karten; A-2-3-4-5 ist die niedrigste',
        'Three of a Kind (Drilling)',
        'Two Pair (Zwei Paare)',
        'One Pair (Ein Paar)',
        'High Card',
      ]} />
      <SectionTitle title="Gleichstand" />
      <RuleList items={[
        'Bei gleicher Kategorie entscheiden die Kartenwerte (Kicker) in Rangfolge; Farben zählen nie.',
        'Sind die besten fünf Karten gleichwertig, wird der Pot geteilt. Ein unteilbarer Rest-Chip geht an den ersten Gewinner links vom Button.',
      ]} />
      <SectionTitle title="KI-Gegner" />
      <RuleList items={[
        'Die KI sieht nur ihre eigenen Karten, das Board, den Pot und die Einsätze.',
        'Sie schätzt ihre Chancen durch Simulation mit unbekannten Karten. Ihr Spielstil (vorsichtig, ausgewogen, aggressiv, Calling Station) beeinflusst nur ihre Entscheidungen – nie die Kartenverteilung.',
      ]} />
    </>
  )
}

// ---------- Tutorials ----------

interface TutorialPage { icon: IconName; title: string; text: string }

const TUTORIALS: Record<GameKind, TutorialPage[]> = {
  blackjack: [
    { icon: 'target', title: 'Ziel', text: 'Komm näher an 21 als der Dealer, ohne 21 zu überschreiten. Bildkarten zählen 10, Asse 1 oder 11.' },
    { icon: 'hand', title: 'Aktionen', text: 'Hit: weitere Karte · Stand: stehen bleiben · Double: Einsatz verdoppeln, genau eine Karte · Split: Paar in zwei Hände teilen.' },
    { icon: 'person', title: 'Dealer-Regeln', text: 'Der Dealer zieht bis 17 und steht auf allen 17. Ein Blackjack (Ass + 10er) zahlt 3:2.' },
    { icon: 'shuffle', title: 'Fair & zufällig', text: 'Gespielt wird mit einem 52-Karten-Deck, das vor jeder Runde per Fisher-Yates mit einem kryptografisch sicheren Zufallsgenerator neu gemischt wird. Nichts ist vorherbestimmt.' },
  ],
  poker: [
    { icon: 'spade', title: "Texas Hold'em", text: 'Du erhältst zwei verdeckte Karten. Fünf Gemeinschaftskarten kommen in drei Schritten: Flop, Turn, River.' },
    { icon: 'list', title: 'Handränge', text: 'Royal Flush › Straight Flush › Vierling › Full House › Flush › Straße › Drilling › Zwei Paare › Paar › High Card.' },
    { icon: 'sliders', title: 'Setzen', text: 'Fold: aussteigen · Check: schieben · Call: mitgehen · Raise: erhöhen. Der Schieberegler bestimmt die Höhe.' },
    { icon: 'cpu', title: 'Faire KI', text: 'Die Gegner sehen nur ihre eigenen Karten und das Board – genau wie du. Jeder hat einen eigenen Spielstil.' },
  ],
  slots: [
    { icon: 'grid', title: '5 Walzen, 10 Linien', text: 'Gewinne zählen von links nach rechts auf aktiven Linien – ab drei gleichen Symbolen.' },
    { icon: 'star', title: 'Wild & Scatter', text: 'Wild ersetzt alle normalen Symbole. Scatter zahlen überall auf den Walzen, multipliziert mit dem Gesamteinsatz.' },
    { icon: 'dice', title: 'Unabhängige Drehungen', text: 'Jede Walze stoppt an einer zufälligen Position. Keine Serien, keine Steuerung – die Auszahlungsquote ist offen einsehbar.' },
  ],
}

export function TutorialSheet({ game, completed, reward, onComplete, onClose }: {
  game: GameKind
  completed: boolean
  reward: number
  onComplete: () => void
  onClose: () => void
}) {
  const pages = TUTORIALS[game]
  const [index, setIndex] = useState(0)
  const page = pages[index]
  return (
    <Sheet onClose={onClose}>
      <div class="stack" style={{ gap: 28 }}>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div class="section-title" style={{ flex: 1, fontSize: 16 }}>SO FUNKTIONIERT {GAME_TITLES[game].toUpperCase()}</div>
          <IconButton icon="close" size={40} label="Schließen" onClick={onClose} />
        </div>
        <div class="tutorial-page" key={index} style={{ animation: 'rise .35s ease-out' }}>
          <div class="ic"><Icon name={page.icon} size={54} stroke={2.2} /></div>
          <h2 class="display">{page.title}</h2>
          <p>{page.text}</p>
        </div>
        <div class="dots">{pages.map((_, i) => <span class={i === index ? 'on' : ''} onClick={() => setIndex(i)} />)}</div>
        <div style={{ display: 'flex', justifyContent: 'center' }}>
          {index === pages.length - 1
            ? <Button kind="gold" size="large" onClick={() => { onComplete(); onClose() }}>
                {completed ? "LOS GEHT'S" : `VERSTANDEN · +${ChipFormat.string(reward)} CHIPS`}
              </Button>
            : <Button kind="primary" size="large" onClick={() => setIndex(index + 1)}>WEITER</Button>}
        </div>
      </div>
    </Sheet>
  )
}
