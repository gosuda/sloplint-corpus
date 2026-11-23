// UC06-distributed-system: per-node state as a map, the message-soup
// pattern, and faults for free. `leaderV1` decides too early; `leader`
// waits until it has heard from every node.
//
// Verify:
//   quint typecheck leader.qnt
//   quint run leader.qnt --main leaderV1 --invariant electedIsMax   # violation
//   quint run leader.qnt --main leader --invariant electedIsMax    # ok
//   quint verify leader.qnt --main leader --invariant electedIsMax --max-steps 10
module leaderV1 {
  pure val NODES = Set(1, 2, 3)

  type Msg = { from: int }
  type Decision = Undecided | Elected(int)

  // The message soup: everything ever sent. A receive does not remove
  // the message (duplication is free); a message nobody ever receives
  // is a lost message (loss is free). No fault actions are needed.
  var soup: Set[Msg]
  var heard: int -> Set[int]
  var decision: int -> Decision

  pure def maxOf(s: Set[int]): int =
    s.fold(-1, (acc, x) => if (x > acc) x else acc)

  action init = all {
    soup' = Set(),
    heard' = NODES.mapBy(n => Set(n)), // every node has heard itself
    decision' = NODES.mapBy(_ => Undecided),
  }

  action announce = {
    nondet n = NODES.oneOf()
    all {
      soup' = soup.union(Set({ from: n })),
      heard' = heard,
      decision' = decision,
    }
  }

  action receive = {
    nondet n = NODES.oneOf()
    nondet m = soup.oneOf()
    all {
      soup.size() > 0,
      soup' = soup,
      heard' = heard.setBy(n, h => h.union(Set(m.from))),
      decision' = decision,
    }
  }

  // BUG: a node decides as soon as it has heard anyone at all.
  action decide = {
    nondet n = NODES.oneOf()
    all {
      decision.get(n) == Undecided,
      soup' = soup,
      heard' = heard,
      decision' = decision.set(n, Elected(maxOf(heard.get(n)))),
    }
  }

  action step = any { announce, receive, decide }

  // Safety: an elected leader is the maximum node id.
  val electedIsMax = NODES.forall(n => match decision.get(n) {
    | Elected(l) => l == maxOf(NODES)
    | Undecided => true
  })

  // Safety: no two decided nodes disagree.
  val agreement = NODES.forall(a => NODES.forall(b =>
    match decision.get(a) {
      | Elected(x) => match decision.get(b) {
          | Elected(y) => x == y
          | Undecided => true
        }
      | Undecided => true
    }))
}

module leader {
  pure val NODES = Set(1, 2, 3)

  type Msg = { from: int }
  type Decision = Undecided | Elected(int)

  var soup: Set[Msg]
  var heard: int -> Set[int]
  var decision: int -> Decision

  pure def maxOf(s: Set[int]): int =
    s.fold(-1, (acc, x) => if (x > acc) x else acc)

  action init = all {
    soup' = Set(),
    heard' = NODES.mapBy(n => Set(n)),
    decision' = NODES.mapBy(_ => Undecided),
  }

  action announce = {
    nondet n = NODES.oneOf()
    all {
      soup' = soup.union(Set({ from: n })),
      heard' = heard,
      decision' = decision,
    }
  }

  action receive = {
    nondet n = NODES.oneOf()
    nondet m = soup.oneOf()
    all {
      soup.size() > 0,
      soup' = soup,
      heard' = heard.setBy(n, h => h.union(Set(m.from))),
      decision' = decision,
    }
  }

  // FIX: decide only after hearing from every node.
  action decide = {
    nondet n = NODES.oneOf()
    all {
      decision.get(n) == Undecided,
      heard.get(n) == NODES,
      soup' = soup,
      heard' = heard,
      decision' = decision.set(n, Elected(maxOf(heard.get(n)))),
    }
  }

  action step = any { announce, receive, decide }

  val electedIsMax = NODES.forall(n => match decision.get(n) {
    | Elected(l) => l == maxOf(NODES)
    | Undecided => true
  })

  val agreement = NODES.forall(a => NODES.forall(b =>
    match decision.get(a) {
      | Elected(x) => match decision.get(b) {
          | Elected(y) => x == y
          | Undecided => true
        }
      | Undecided => true
    }))
}
