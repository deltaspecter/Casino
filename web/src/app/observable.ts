import { useEffect, useReducer } from 'preact/hooks'

/** Minimaler beobachtbarer Zustand: Komponenten rendern neu, sobald `emit()` aufgerufen wird. */
export class Observable {
  private listeners = new Set<() => void>()

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  protected emit(): void {
    for (const l of [...this.listeners]) l()
  }
}

export interface Subscribable {
  subscribe(listener: () => void): () => void
}

/** Rendert die Komponente neu, wenn sich eines der Objekte meldet. */
export function useObserve(...targets: Array<Subscribable | null | undefined>): void {
  const [, force] = useReducer((n: number) => n + 1, 0)
  useEffect(() => {
    const offs = targets.filter(Boolean).map((t) => t!.subscribe(() => force(0)))
    return () => offs.forEach((off) => off())
  }, targets)
}

export const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
