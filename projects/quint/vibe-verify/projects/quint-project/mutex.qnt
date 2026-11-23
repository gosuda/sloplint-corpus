// UC05-concurrent-code: interleavings. `mutexV1` splits check and
// acquire into two steps — the classic lost-update shape. `mutex`
// makes the pair atomic.
//
// Verify:
//   quint typecheck mutex.qnt
//   quint run mutex.qnt --main mutexV1 --invariant mutualExclusion   # violation
//   quint run mutex.qnt --main mutex --invariant mutualExclusion     # ok
//   quint verify mutex.qnt --main mutex --invariant mutualExclusion --max-steps 10
module mutexV1 {
  pure val THREADS = Set(0, 1)

  type Loc = Idle | Ready | Critical

  var pc: int -> Loc
  var locked: bool

  action init = all {
    pc' = THREADS.mapBy(_ => Idle),
    locked' = false,
  }

  // BUG: the check is one step ...
  action check(t: int): bool = all {
    pc.get(t) == Idle,
    not(locked),
    pc' = pc.set(t, Ready),
    locked' = locked,
  }

  // ... and the acquire is another. Both threads can pass the check
  // before either acquires.
  action acquire(t: int): bool = all {
    pc.get(t) == Ready,
    locked' = true,
    pc' = pc.set(t, Critical),
  }

  action release(t: int): bool = all {
    pc.get(t) == Critical,
    locked' = false,
    pc' = pc.set(t, Idle),
  }

  // One scheduler step: pick a thread, run one of its enabled actions.
  // The model checker plays every schedule; a test suite plays a few.
  action step = {
    nondet t = THREADS.oneOf()
    any { check(t), acquire(t), release(t) }
  }

  val mutualExclusion = THREADS.filter(t => pc.get(t) == Critical).size() <= 1
}

module mutex {
  pure val THREADS = Set(0, 1)

  type Loc = Idle | Critical

  var pc: int -> Loc
  var locked: bool

  action init = all {
    pc' = THREADS.mapBy(_ => Idle),
    locked' = false,
  }

  // FIX: test-and-set in a single atomic step.
  action acquire(t: int): bool = all {
    pc.get(t) == Idle,
    not(locked),
    locked' = true,
    pc' = pc.set(t, Critical),
  }

  action release(t: int): bool = all {
    pc.get(t) == Critical,
    locked' = false,
    pc' = pc.set(t, Idle),
  }

  action step = {
    nondet t = THREADS.oneOf()
    any { acquire(t), release(t) }
  }

  val mutualExclusion = THREADS.filter(t => pc.get(t) == Critical).size() <= 1
}
