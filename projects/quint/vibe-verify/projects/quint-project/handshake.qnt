// UC03-state-machine-protocol: a two-phase handshake, first drafted with
// a real bug (`handshakeV1`), then fixed (`handshake`).
//
// Verify:
//   quint typecheck handshake.qnt
//   quint run handshake.qnt --main handshakeV1 --invariant serverTrustsClient   # violation
//   quint run handshake.qnt --main handshake --invariant serverTrustsClient     # ok
//   quint verify handshake.qnt --main handshake --invariant serverTrustsClient --max-steps 10
//   quint test handshake.qnt --main handshake
//   quint run handshake.qnt --main handshake --out-itf trace.itf.json --seed 0x1   # T08
module handshakeV1 {
  type ClientState = CIdle | SynSent | CEstablished
  type ServerState = Listen | SynReceived | SEstablished
  type Msg = Syn | SynAck | Ack

  var client: ClientState
  var server: ServerState
  // The network is a set: messages are unordered and may be duplicated.
  var network: Set[Msg]

  action init = all {
    client' = CIdle,
    server' = Listen,
    network' = Set(),
  }

  action clientSendSyn = all {
    client == CIdle,
    client' = SynSent,
    network' = network.union(Set(Syn)),
    server' = server,
  }

  // BUG: the server declares the connection established as soon as it
  // answers the Syn. It does not wait for the client's Ack.
  action serverRecvSyn = all {
    server == Listen,
    network.contains(Syn),
    server' = SEstablished,
    network' = network.union(Set(SynAck)),
    client' = client,
  }

  action clientRecvSynAck = all {
    client == SynSent,
    network.contains(SynAck),
    client' = CEstablished,
    network' = network.union(Set(Ack)),
    server' = server,
  }

  action step = any { clientSendSyn, serverRecvSyn, clientRecvSynAck }

  // Safety: the server never believes in a connection the client
  // has not confirmed.
  val serverTrustsClient = server == SEstablished implies client == CEstablished
}

module handshake {
  type ClientState = CIdle | SynSent | CEstablished
  type ServerState = Listen | SynReceived | SEstablished
  type Msg = Syn | SynAck | Ack

  var client: ClientState
  var server: ServerState
  var network: Set[Msg]

  action init = all {
    client' = CIdle,
    server' = Listen,
    network' = Set(),
  }

  action clientSendSyn = all {
    client == CIdle,
    client' = SynSent,
    network' = network.union(Set(Syn)),
    server' = server,
  }

  // FIX: answering a Syn only moves the server to SynReceived.
  action serverRecvSyn = all {
    server == Listen,
    network.contains(Syn),
    server' = SynReceived,
    network' = network.union(Set(SynAck)),
    client' = client,
  }

  action clientRecvSynAck = all {
    client == SynSent,
    network.contains(SynAck),
    client' = CEstablished,
    network' = network.union(Set(Ack)),
    server' = server,
  }

  // The server establishes only on the client's Ack.
  action serverRecvAck = all {
    server == SynReceived,
    network.contains(Ack),
    server' = SEstablished,
    network' = network,
    client' = client,
  }

  // A terminal state must loop, or the model checker reports a
  // deadlock: a state where no action is enabled.
  action done = all {
    client == CEstablished,
    server == SEstablished,
    client' = client,
    server' = server,
    network' = network,
  }

  action step = any { clientSendSyn, serverRecvSyn, clientRecvSynAck, serverRecvAck, done }

  val serverTrustsClient = server == SEstablished implies client == CEstablished

  run happyPathTest = init
    .then(clientSendSyn)
    .then(serverRecvSyn)
    .then(clientRecvSynAck)
    .then(serverRecvAck)
    .expect(client == CEstablished and server == SEstablished)

  // The server cannot establish before the Ack exists.
  run noEarlyEstablishTest = init
    .then(clientSendSyn)
    .then(serverRecvSyn)
    .then(serverRecvAck.fail())
}
