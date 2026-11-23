// Q03-invariants-safety and Q05-runs-and-tests.
//
// `bankV1` has a deliberate bug: withdraw checks that the balance is
// positive, not that it covers the amount.
//
// Verify:
//   quint typecheck bank.qnt
//   quint run bank.qnt --main bankV1 --invariant noOverdraft        # finds a violation
//   quint run bank.qnt --main bank --invariant noOverdraft          # no violation
//   quint verify bank.qnt --main bank --invariant noOverdraft --max-steps 10
//   quint test bank.qnt --main bank
module bankV1 {
  pure val ACCOUNTS = Set("alice", "bob")

  var balances: str -> int

  action init = balances' = ACCOUNTS.mapBy(_ => 10)

  action deposit(acct: str, amount: int): bool = all {
    amount > 0,
    balances' = balances.setBy(acct, old => old + amount),
  }

  action withdraw(acct: str, amount: int): bool = all {
    amount > 0,
    balances.get(acct) > 0, // BUG: does not compare against amount
    balances' = balances.setBy(acct, old => old - amount),
  }

  action step = {
    nondet acct = ACCOUNTS.oneOf()
    nondet amount = 1.to(20).oneOf()
    any {
      deposit(acct, amount),
      withdraw(acct, amount),
    }
  }

  val noOverdraft = ACCOUNTS.forall(a => balances.get(a) >= 0)
}

module bank {
  pure val ACCOUNTS = Set("alice", "bob")

  var balances: str -> int

  action init = balances' = ACCOUNTS.mapBy(_ => 10)

  action deposit(acct: str, amount: int): bool = all {
    amount > 0,
    balances' = balances.setBy(acct, old => old + amount),
  }

  action withdraw(acct: str, amount: int): bool = all {
    amount > 0,
    balances.get(acct) >= amount, // FIX: the guard covers the amount
    balances' = balances.setBy(acct, old => old - amount),
  }

  action step = {
    nondet acct = ACCOUNTS.oneOf()
    nondet amount = 1.to(20).oneOf()
    any {
      deposit(acct, amount),
      withdraw(acct, amount),
    }
  }

  val noOverdraft = ACCOUNTS.forall(a => balances.get(a) >= 0)

  // Q03: an inductive invariant for Apalache. Induction starts from an
  // arbitrary state that satisfies this predicate, so the predicate
  // must first pin the shape of every variable with `in`.
  val indNoOverdraft = and {
    balances.in(ACCOUNTS.setOfMaps(Int)),
    noOverdraft,
  }

  // Q05: runs are unit tests of the model. `quint test` executes them.
  run happyPathTest = init
    .then(deposit("alice", 5))
    .then(withdraw("alice", 12))
    .expect(balances.get("alice") == 3)

  // `A.fail()` succeeds when A is disabled. Guards become testable.
  run overdraftRejectedTest = init
    .then(withdraw("alice", 11).fail())

  // A randomized run: `reps` repeats an action; `step` explores.
  run randomWalkTest = init
    .then(20.reps(_ => step))
    .expect(noOverdraft)
}
