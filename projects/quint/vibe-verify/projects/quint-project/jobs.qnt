// Q02-state-machines: sum-type states, records, maps for per-entity state.
//
// Verify:
//   quint typecheck jobs.qnt
//   quint run jobs.qnt --invariant sane --seed 0x1
module jobs {
  // A sum type makes the set of states closed. A string cannot.
  type Status =
    | Pending
    | Running(str)      // carries the worker id
    | Done(int)         // carries the exit code
    | Failed(str)       // carries the reason

  pure val JOBS = Set("build", "test", "deploy")
  pure val WORKERS = Set("w1", "w2")

  // Per-entity state: one map from id to status.
  var status: str -> Status

  pure def isRunning(s: Status): bool = match s {
    | Running(_) => true
    | _ => false
  }

  action init = status' = JOBS.mapBy(_ => Pending)

  action start = {
    nondet j = JOBS.oneOf()
    nondet w = WORKERS.oneOf()
    all {
      status.get(j) == Pending,
      status' = status.set(j, Running(w)),
    }
  }

  action finish = {
    nondet j = JOBS.oneOf()
    all {
      isRunning(status.get(j)),
      status' = status.set(j, Done(0)),
    }
  }

  action crash = {
    nondet j = JOBS.oneOf()
    all {
      isRunning(status.get(j)),
      status' = status.set(j, Failed("worker lost")),
    }
  }

  action step = any { start, finish, crash }

  // The invariant pattern-matches, so the checker sees every case.
  val sane = JOBS.forall(j => match status.get(j) {
    | Running(w) => WORKERS.contains(w)
    | Done(code) => code == 0
    | _ => true
  })

  run lifecycleTest = init
    .then(start)
    .expect(JOBS.exists(j => isRunning(status.get(j))))
}
