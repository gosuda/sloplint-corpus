// Q01-language-essentials: modules, var, pure def vs def, action,
// init/step, nondet, any/all.
//
// Verify:
//   quint typecheck counter.qnt
//   quint run counter.qnt --invariant bounded --seed 0x1
module counter {
  // State: declared with `var`. Everything else is derived.
  var n: int
  var seen: Set[int]

  // A pure def only sees its arguments. Same input, same output.
  pure def double(x: int): int = 2 * x

  // A stateless-looking val without `pure` may read the state.
  val atLimit = n == 10

  // An action assigns every state variable exactly once, with `'`.
  action init = all {
    n' = 0,
    seen' = Set(0),
  }

  // `nondet x = S.oneOf()` picks an arbitrary element of S.
  // The simulator picks at random; the model checker tries all.
  action bump = {
    nondet delta = 1.to(3).oneOf()
    all {
      n + delta <= 10, // guard: the action is enabled only if this holds
      n' = n + delta,
      seen' = seen.union(Set(n + delta)),
    }
  }

  action reset = all {
    atLimit,
    n' = 0,
    seen' = seen,
  }

  // `any` is a nondeterministic choice among enabled actions.
  // `all` is conjunction: every line must hold in the same step.
  action step = any {
    bump,
    reset,
  }

  // An invariant is a plain boolean over the state.
  val bounded = 0 <= n and n <= 10
}
