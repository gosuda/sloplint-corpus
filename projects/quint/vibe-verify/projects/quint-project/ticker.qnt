// Q04-temporal-properties: liveness, fairness, and where each backend stops.
//
// Verify:
//   quint typecheck ticker.qnt
//   quint verify ticker.qnt --temporal reachesMax --backend tlc      # counterexample: stutter forever
//   quint verify ticker.qnt --temporal fairReachesMax --backend tlc  # holds
//   (Apalache rejects fairness: "Handling fairness is not supported yet!")
module ticker {
  pure val MAX = 3

  var n: int

  action init = n' = 0

  action inc = all { n < MAX, n' = n + 1 }

  action stay = n' = n

  action step = any { inc, stay }

  val bounded = 0 <= n and n <= MAX

  // Liveness without fairness. False: the system may `stay` forever.
  temporal reachesMax = eventually(n == MAX)

  // Weak fairness on `inc`: if `inc` stays enabled forever, it fires.
  // Under that assumption the property holds.
  temporal fairReachesMax = weakFair(inc, n) implies eventually(n == MAX)

  // A safety phrasing of the same intent, checkable everywhere:
  // "n never exceeds MAX and never decreases below 0" is `bounded`.
}
