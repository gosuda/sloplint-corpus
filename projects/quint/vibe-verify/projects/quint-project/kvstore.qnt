// Q06-abstraction-refinement: nondeterminism as underspecification,
// then a refinement that explains it.
//
// Verify:
//   quint typecheck kvstore.qnt
//   quint run kvstore.qnt --main kvCoarse --invariant inRange --seed 0x1
//   quint run kvstore.qnt --main kvRefined --invariant inRange --seed 0x1
//   quint verify kvstore.qnt --main kvRefined --invariant inRange --max-steps 10
module kvCoarse {
  pure val KEYS = Set("a", "b")

  var store: str -> int

  action init = store' = KEYS.mapBy(_ => 0)

  // Underspecification: a write is applied or lost. The model does not
  // say why. `any` keeps both futures open; the checker explores both.
  action write = {
    nondet k = KEYS.oneOf()
    nondet v = 1.to(3).oneOf()
    any {
      store' = store.set(k, v), // applied
      store' = store,           // lost
    }
  }

  action step = write

  val inRange = KEYS.forall(k => 0 <= store.get(k) and store.get(k) <= 3)
}

module kvRefined {
  pure val KEYS = Set("a", "b")

  // The refinement explains "lost": a write sits in a log until the
  // store applies it; a crash drops the log.
  type Pending = NoWrite | Write({ key: str, value: int })

  var store: str -> int
  var log: Pending

  action init = all {
    store' = KEYS.mapBy(_ => 0),
    log' = NoWrite,
  }

  action submit = {
    nondet k = KEYS.oneOf()
    nondet v = 1.to(3).oneOf()
    all {
      log == NoWrite,
      log' = Write({ key: k, value: v }),
      store' = store,
    }
  }

  action apply = all {
    log != NoWrite,
    store' = match log {
      | Write(w) => store.set(w.key, w.value)
      | NoWrite => store
    },
    log' = NoWrite,
  }

  action crash = all {
    log != NoWrite,
    log' = NoWrite, // the pending write is gone; the store is unchanged
    store' = store,
  }

  action step = any { submit, apply, crash }

  // The abstraction function: what the coarse model calls `store`.
  val abstractStore = store

  val inRange = KEYS.forall(k => 0 <= store.get(k) and store.get(k) <= 3)
}
