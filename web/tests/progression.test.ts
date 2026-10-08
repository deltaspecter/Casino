import { describe, expect, it } from 'vitest';
import {
  ClaimError, makeCalendar, MemoryStorage, PlayerProfile, ProfileStore, RewardTable, SeededRandomSource, WalletError,
} from '../src/core';

const calendar = makeCalendar('Europe/Berlin');
const date = (day: number, hour = 12): Date => calendar.date(2026, 3, day, hour);

function expectClaimError(fn: () => unknown, kind?: ClaimError['kind']): void {
  try {
    fn();
    expect.unreachable();
  } catch (e) {
    expect(e).toBeInstanceOf(ClaimError);
    if (kind) expect((e as ClaimError).kind).toBe(kind);
  }
}

describe('Calendar', () => {
  it('computes day boundaries in a time zone', () => {
    expect(date(1).toISOString()).toBe('2026-03-01T11:00:00.000Z');
    expect(calendar.startOfDay(date(1)).toISOString()).toBe('2026-02-28T23:00:00.000Z');
    // Sommerzeit beginnt am 29.03.2026 in Berlin
    expect(calendar.startOfDayAdding(1, date(29)).toISOString()).toBe('2026-03-29T22:00:00.000Z');
    expect(calendar.isDateInSameDayAs(date(1, 0), date(1, 23))).toBe(true);
    expect(calendar.daysBetween(date(1, 23), date(2, 0))).toBe(1);
    expect(calendar.daysBetween(date(1), date(5))).toBe(4);
  });
});

describe('Progression', () => {
  it('starting chips', () => {
    expect(new PlayerProfile().chips).toBe(10_000);
    expect(new PlayerProfile().stats.peakChips).toBe(10_000);
  });

  it('reward table values', () => {
    expect(RewardTable.dailyReward).toBe(1_000);
    expect(RewardTable.rescueAmount).toBe(2_500);
    expect(RewardTable.rescueThreshold).toBe(100);
    expect(RewardTable.rescueCooldown).toBe(3_600);
    expect(RewardTable.tutorialReward).toBe(1_000);
    expect(RewardTable.missionsPerDay).toBe(3);
    expect([1, 2, 3, 4, 5, 6, 7, 8, 14].map((d) => RewardTable.loginReward(d)))
      .toEqual([500, 750, 1_000, 1_500, 2_000, 2_500, 5_000, 500, 5_000]);
    expect(RewardTable.loginReward(0)).toBe(500);
    expect(RewardTable.missionPool.length).toBe(7);
    expect(RewardTable.achievements.length).toBe(11);
    expect(RewardTable.achievement('loyal')?.title).toBe('Treue Woche');
    expect(RewardTable.mission('games-20')?.title).toBe('Spiele 20 Runden in beliebigen Spielen');
  });

  it('wallet', () => {
    const p = new PlayerProfile();
    p.debit(1_000);
    expect(p.chips).toBe(9_000);
    try {
      p.debit(20_000);
      expect.unreachable();
    } catch (e) {
      expect(e).toBeInstanceOf(WalletError);
      expect(e).toMatchObject({ kind: 'insufficientChips', needed: 20_000, available: 9_000 });
    }
    expect(() => p.debit(0)).toThrow(WalletError);
    p.credit(500);
    expect(p.chips).toBe(9_500);
  });

  it('table escrow', () => {
    const p = new PlayerProfile();
    p.moveToTable(1_000);
    expect(p.chips).toBe(9_000);
    expect(p.tableEscrow).toBe(1_000);
    p.releaseFromTable(1_000, 2_000);
    expect(p.chips).toBe(11_000);
    expect(p.tableEscrow).toBe(0);

    p.moveToTable(500);
    expect(p.refundTableEscrow()).toBe(500);
    expect(p.chips).toBe(11_000);
    p.setTableEscrow(-5);
    expect(p.tableEscrow).toBe(0);
  });

  it('login streak', () => {
    const p = new PlayerProfile();
    expect(p.claimLoginBonus(date(1), calendar).streakDay).toBe(1);
    expect(p.loginBonusOffer(date(1, 23), calendar)).toBeNull();
    expect(p.claimLoginBonus(date(2, 0), calendar).streakDay).toBe(2);
    expect(p.claimLoginBonus(date(3), calendar).amount).toBe(1_000);
    // Tag ausgelassen → Serie beginnt neu
    expect(p.claimLoginBonus(date(5), calendar).streakDay).toBe(1);
    expectClaimError(() => p.claimLoginBonus(date(5, 20), calendar), 'alreadyClaimed');
  });

  it('daily reward once per day', () => {
    const p = new PlayerProfile();
    expect(p.claimDailyReward(date(1), calendar)).toBe(RewardTable.dailyReward);
    expectClaimError(() => p.claimDailyReward(date(1, 20), calendar), 'alreadyClaimed');
    expect(p.nextDailyReward(date(1, 20), calendar)?.toISOString()).toBe(calendar.startOfDay(date(2)).toISOString());
    expect(() => p.claimDailyReward(date(2, 1), calendar)).not.toThrow();
    expect(p.nextDailyReward(date(3), calendar)).toBeNull();
  });

  it('statistics track wins and losses', () => {
    const p = new PlayerProfile();
    p.record({ type: 'blackjackRound', stake: 100, payout: 250, handsWon: 1, pushes: 0, blackjacks: 1, hands: 1 });
    p.record({ type: 'blackjackRound', stake: 200, payout: 200, handsWon: 0, pushes: 1, blackjacks: 0, hands: 2 });
    p.record({ type: 'pokerHand', contributed: 300, won: 0 });
    p.record({ type: 'slotSpin', bet: 10, payout: 50 });
    p.record({ type: 'slotSpin', bet: 10, payout: 0 });
    expect(p.stats.blackjackRounds).toBe(2);
    expect(p.stats.blackjackHands).toBe(3);
    expect(p.stats.blackjackPushes).toBe(1);
    expect(p.stats.pokerHands).toBe(1);
    expect(p.stats.pokerWins).toBe(0);
    expect(p.stats.slotSpins).toBe(2);
    expect(p.stats.slotWins).toBe(1);
    expect(p.stats.gamesPlayed).toBe(5);
    expect(p.stats.roundsWon).toBe(2);
    expect(p.stats.totalWon).toBe(190);
    expect(p.stats.totalLost).toBe(310);
    expect(p.stats.netResult).toBe(-120);
    expect(p.stats.biggestWin).toBe(150);
    expect(p.stats.totalWagered).toBe(620);
    expect(p.chips, 'Statistik bewegt keine Chips').toBe(PlayerProfile.startingChips);
  });

  it('missions progress and claim', () => {
    const p = new PlayerProfile();
    p.refreshDailyMissions(date(1), new SeededRandomSource(1), calendar);
    expect(p.dailyMissions.length).toBe(3);

    // Alle Spiele so lange spielen, bis jede Mission erfüllt ist
    let completed = 0;
    for (let i = 0; i < 40; i++) {
      const notes = [
        ...p.record({ type: 'blackjackRound', stake: 600, payout: 1_500, handsWon: 1, pushes: 0, blackjacks: 1, hands: 1 }),
        ...p.record({ type: 'pokerHand', contributed: 600, won: 1_000 }),
        ...p.record({ type: 'slotSpin', bet: 600, payout: 100 }),
      ];
      completed += notes.filter((n) => n.type === 'missionCompleted').length;
    }
    expect(completed).toBe(3);
    for (const m of p.dailyMissions) {
      expect(p.isMissionComplete(m)).toBe(true);
      const before = p.chips;
      expect(() => p.claimMission(m.missionID)).not.toThrow();
      expect(p.chips - before).toBe(RewardTable.mission(m.missionID)!.rewardChips);
      expectClaimError(() => p.claimMission(m.missionID), 'alreadyClaimed');
    }
    expectClaimError(() => p.claimMission('gibt-es-nicht'), 'notAvailable');
    // Gleicher Tag → gleiche Missionen
    const ids = p.dailyMissions.map((m) => m.missionID);
    p.refreshDailyMissions(date(1, 22), new SeededRandomSource(2), calendar);
    expect(p.dailyMissions.map((m) => m.missionID)).toEqual(ids);
    // Neuer Tag → neue Missionen
    p.refreshDailyMissions(date(2), new SeededRandomSource(2), calendar);
    expect(p.dailyMissions.every((m) => m.progress === 0 && !m.isClaimed)).toBe(true);
  });

  it('incomplete mission cannot be claimed', () => {
    const p = new PlayerProfile();
    p.refreshDailyMissions(date(1), new SeededRandomSource(3), calendar);
    expectClaimError(() => p.claimMission(p.dailyMissions[0]!.missionID), 'notAvailable');
  });

  it('achievements unlock and claim once', () => {
    const p = new PlayerProfile();
    const notes = p.record({ type: 'blackjackRound', stake: 100, payout: 250, handsWon: 1, pushes: 0, blackjacks: 1, hands: 1 });
    const unlocked = notes.flatMap((n) => (n.type === 'achievementUnlocked' ? [n.achievement.id] : []));
    expect(unlocked).toContain('natural');
    expect(unlocked).toContain('first-win');
    expect(p.claimAchievement('natural')).toBe(500);
    expectClaimError(() => p.claimAchievement('natural'), 'alreadyClaimed');
    expectClaimError(() => p.claimAchievement('high-roller'), 'notAvailable');
  });

  it('tutorial reward only once', () => {
    const p = new PlayerProfile();
    expect(p.completeTutorial('slots')).toBe(1_000);
    expect(p.completeTutorial('slots')).toBe(0);
  });

  it('rescue', () => {
    const p = new PlayerProfile();
    expect(p.canClaimRescue(date(1))).toBe(false);
    p.debit(p.chips - 50);
    expect(p.canClaimRescue(date(1))).toBe(true);
    p.claimRescue(date(1));
    expect(p.chips).toBe(2_550);
    p.debit(p.chips - 10);
    expect(p.canClaimRescue(new Date(date(1).getTime() + 60_000))).toBe(false);
    expectClaimError(() => p.claimRescue(new Date(date(1).getTime() + 60_000)), 'notAvailable');
    expect(p.canClaimRescue(new Date(date(1).getTime() + 3_600_000))).toBe(true);
  });

  it('persistence round trip and corruption recovery', () => {
    const storage = new MemoryStorage();
    const store = new ProfileStore(storage);
    expect(store.load().outcome).toEqual({ type: 'created' });

    const p = new PlayerProfile();
    p.credit(1_234);
    p.completeTutorial('poker');
    p.claimDailyReward(date(1), calendar);
    p.refreshDailyMissions(date(1), new SeededRandomSource(4), calendar);
    p.record({ type: 'slotSpin', bet: 10, payout: 50 });
    p.displayName = 'Kim';
    p.settings.reducedMotion = true;
    store.save(p);
    const { profile: loaded, outcome } = store.load();
    expect(outcome).toEqual({ type: 'loaded' });
    expect(loaded.chips).toBe(p.chips);
    expect([...loaded.completedTutorials]).toEqual([...p.completedTutorials]);
    expect(loaded.displayName).toBe('Kim');
    expect(loaded.settings).toEqual({ hapticsEnabled: true, reducedMotion: true });
    expect(loaded.lastDailyRewardDate?.toISOString()).toBe(date(1).toISOString());
    expect(loaded.dailyMissions).toEqual(p.dailyMissions);
    expect(loaded.stats.toJSON()).toEqual((p.stats as typeof loaded.stats).toJSON());
    expect([...loaded.unlockedAchievements].sort()).toEqual([...p.unlockedAchievements].sort());
    // Swift-kompatibles Format: sortierte Schlüssel, ISO-8601 ohne Millisekunden
    const raw = JSON.parse(storage.getItem(ProfileStore.defaultKey)!) as Record<string, unknown>;
    expect(Object.keys(raw)).toEqual([...Object.keys(raw)].sort());
    expect(raw.lastDailyRewardDate).toBe('2026-03-01T11:00:00Z');
    expect(raw.version).toBe(2);
    expect(raw).not.toHaveProperty('xp');
    expect(raw).not.toHaveProperty('level');

    storage.setItem(ProfileStore.defaultKey, 'kaputt');
    const { profile: fresh, outcome: outcome2 } = store.load();
    expect(fresh.chips).toBe(PlayerProfile.startingChips);
    expect(outcome2.type).toBe('recoveredFromCorruption');
    if (outcome2.type === 'recoveredFromCorruption') expect(storage.getItem(outcome2.backupKey)).toBe('kaputt');
    expect(store.load().outcome.type, 'Beschädigter Eintrag wurde beiseitegelegt').toBe('created');

    store.save(p);
    store.reset();
    expect(store.load().outcome.type).toBe('created');
  });

  it('works with a storage that only has getItem/setItem', () => {
    const map = new Map<string, string>();
    const store = new ProfileStore({ getItem: (k) => map.get(k) ?? null, setItem: (k, v) => { map.set(k, v); } }, 'k');
    store.save(new PlayerProfile());
    expect(store.load().outcome.type).toBe('loaded');
    map.set('k', '{');
    expect(store.load().outcome.type).toBe('recoveredFromCorruption');
    expect(store.load().outcome.type).toBe('created');
  });

  it('loads older or incomplete save files', () => {
    const storage = new MemoryStorage();
    const store = new ProfileStore(storage);

    // Alte Version mit XP/Level-Feldern und unbekannter Mission → wird bereinigt übernommen
    const old = `{"version":1,"chips":12345,"xp":300,"level":4,"displayName":"Kim",
      "dailyMissions":[{"missionID":"gibt-es-nicht","progress":2,"isClaimed":false}],
      "unlockedAchievements":["natural","unbekannt"],"claimedAchievements":["unbekannt"],
      "stats":{"slotSpins":7}}`;
    storage.setItem(ProfileStore.defaultKey, old);
    const { profile: p, outcome } = store.load();
    expect(outcome).toEqual({ type: 'loaded' });
    expect(p.chips).toBe(12_345);
    expect(p.displayName).toBe('Kim');
    expect(p.stats.slotSpins).toBe(7);
    expect(p.stats.peakChips).toBe(12_345);
    expect(p.version).toBe(2);
    expect(p.dailyMissions.length).toBe(0);
    expect([...p.unlockedAchievements]).toEqual(['natural']);
    expect(p.claimedAchievements.size).toBe(0);
    expect(p.toJSON()).not.toHaveProperty('xp');

    // Negativer Kontostand (manipulierte Datei) wird auf 0 korrigiert
    storage.setItem(ProfileStore.defaultKey, '{"chips":-500,"tableEscrow":-3}');
    const fixed = store.load().profile;
    expect(fixed.chips).toBe(0);
    expect(fixed.tableEscrow).toBe(0);

    // Datei ohne Kontostand ist unbrauchbar → neues Profil
    storage.setItem(ProfileStore.defaultKey, '{"displayName":"X"}');
    const { profile: fresh, outcome: outcome3 } = store.load();
    expect(fresh.chips).toBe(PlayerProfile.startingChips);
    expect(outcome3.type).toBe('recoveredFromCorruption');
  });

  it('tolerates wrong types in optional fields', () => {
    const p = PlayerProfile.decode({
      chips: 50, displayName: '   ', stats: 'x', settings: { hapticsEnabled: 'ja' }, loginStreak: -4,
      lastRescueDate: 12, completedTutorials: ['poker', 3], dailyMissions: [{ missionID: 'games-20' }],
      createdAt: 'kein Datum',
    });
    expect(p.displayName).toBe('Spieler');
    expect(p.stats.peakChips).toBe(50);
    expect(p.settings).toEqual({ hapticsEnabled: true, reducedMotion: false });
    expect(p.loginStreak).toBe(0);
    expect(p.lastRescueDate).toBeNull();
    expect(p.completedTutorials.size).toBe(0);
    expect(p.dailyMissions.length).toBe(0);
    expect(p.createdAt).toBeInstanceOf(Date);
    expect(PlayerProfile.decode({ chips: 1, displayName: 'A'.repeat(30) }).displayName).toBe('A'.repeat(20));
    expect(() => PlayerProfile.decode({ chips: 1.5 })).toThrow();
    expect(() => PlayerProfile.decode([1])).toThrow();
  });

  it('balance never negative', () => {
    const p = new PlayerProfile();
    expect(() => p.debit(-10)).toThrow(WalletError);
    expect(() => p.moveToTable(p.chips + 1)).toThrow(WalletError);
    p.moveToTable(p.chips);
    expect(p.chips).toBe(0);
    expect(() => p.debit(1)).toThrow(WalletError);
    p.credit(-100);
    expect(p.chips).toBe(0);
    p.releaseFromTable(999_999, 0);
    expect(p.tableEscrow).toBe(0);
    expect(p.chips).toBeGreaterThanOrEqual(0);
  });

  it('clone is independent', () => {
    const p = new PlayerProfile();
    const q = p.clone();
    q.debit(100);
    q.record({ type: 'slotSpin', bet: 10, payout: 0 });
    expect(p.chips).toBe(10_000);
    expect(p.stats.slotSpins).toBe(0);
  });
});
