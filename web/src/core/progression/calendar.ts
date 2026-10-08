/**
 * Minimaler Kalender (Ersatz für Foundation `Calendar`): Tagesgrenzen in einer Zeitzone.
 * `Calendar.current` nutzt die lokale Zeitzone des Geräts; `makeCalendar('Europe/Berlin')`
 * eine feste IANA-Zeitzone (z. B. für Tests).
 */
export interface Calendar {
  /** IANA-Zeitzone oder `null` für die lokale Zeitzone. */
  readonly timeZone: string | null;
  /** Fortlaufende Tagesnummer des Kalendertags von `date` (Tage seit 1970-01-01 in dieser Zeitzone). */
  dayNumber(date: Date): number;
  /** Beginn (00:00) des Kalendertags von `date`. */
  startOfDay(date: Date): Date;
  /** Beginn des Kalendertags `days` Tage nach dem Tag von `date`. */
  startOfDayAdding(days: number, date: Date): Date;
  isDateInSameDayAs(a: Date, b: Date): boolean;
  /** Ganze Kalendertage zwischen den Tagen von `from` und `to`. */
  daysBetween(from: Date, to: Date): number;
  /** Datum aus Komponenten (Monat 1–12) in dieser Zeitzone. */
  date(year: number, month: number, day: number, hour?: number, minute?: number, second?: number): Date;
}

const DAY_MS = 86_400_000;

interface Parts { year: number; month: number; day: number; hour: number; minute: number; second: number }

function localParts(date: Date): Parts {
  return {
    year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(),
    hour: date.getHours(), minute: date.getMinutes(), second: date.getSeconds(),
  };
}

function makeZonedParts(timeZone: string): (date: Date) => Parts {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
    hour: 'numeric', minute: 'numeric', second: 'numeric',
  });
  return (date: Date): Parts => {
    const p: Record<string, number> = {};
    for (const part of fmt.formatToParts(date)) {
      if (part.type !== 'literal') p[part.type] = Number(part.value);
    }
    return {
      year: p.year!, month: p.month!, day: p.day!,
      hour: p.hour! % 24, minute: p.minute!, second: p.second!,
    };
  };
}

export function makeCalendar(timeZone: string | null = null): Calendar {
  const partsOf = timeZone ? makeZonedParts(timeZone) : localParts;

  /** Instant für eine Wanduhrzeit in der Zeitzone. */
  const instant = (year: number, month: number, day: number, hour = 0, minute = 0, second = 0): Date => {
    if (!timeZone) return new Date(year, month - 1, day, hour, minute, second);
    const wall = Date.UTC(year, month - 1, day, hour, minute, second);
    let guess = wall;
    for (let i = 0; i < 3; i++) {
      const p = partsOf(new Date(guess));
      const asWall = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
      const diff = asWall - wall;
      if (diff === 0) break;
      guess -= diff;
    }
    return new Date(guess);
  };

  const dayNumber = (date: Date): number => {
    const p = partsOf(date);
    return Math.round(Date.UTC(p.year, p.month - 1, p.day) / DAY_MS);
  };

  const fromDayNumber = (n: number): Date => {
    const d = new Date(n * DAY_MS);
    return instant(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
  };

  return {
    timeZone,
    dayNumber,
    startOfDay: (date) => fromDayNumber(dayNumber(date)),
    startOfDayAdding: (days, date) => fromDayNumber(dayNumber(date) + days),
    isDateInSameDayAs: (a, b) => dayNumber(a) === dayNumber(b),
    daysBetween: (from, to) => dayNumber(to) - dayNumber(from),
    date: instant,
  };
}

/** Swift-ähnlicher Zugriff: `Calendar.current` (lokale Zeitzone). */
export const Calendar = {
  get current(): Calendar { return makeCalendar(null); },
  make: makeCalendar,
};
