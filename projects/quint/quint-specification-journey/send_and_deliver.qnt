// Unordered message delivery: environment chooses which action
// runs next, and which message is involved.

module send_and_deliver {

   type Msg = { seq: int, value: int }

   var generated:  Set[Msg]
   var in_transit: Set[Msg]
   var received:   Set[Msg]

   val msg0: Msg = { seq: 0, value: 100 }
   val msg1: Msg = { seq: 1, value: 200 }
   val msg3: Msg = { seq: 3, value: 150 }

   action init = all {
          generated'  = Set(msg0, msg1, msg3),
          in_transit' = Set(),
          received'   = Set()
   }

   action sendMessage = {
          nondet m = generated.oneOf()
          all {
             generated'  = generated.exclude(Set(m)),
             in_transit' = in_transit.union(Set(m)),
             received'   = received
          }
   }

   action deliverMessage = {
          nondet m = in_transit.oneOf()
          all {
             generated'  = generated,
             in_transit' = in_transit.exclude(Set(m)),
             received'   = received.union(Set(m))
          }
   }

   action step = any {
          sendMessage,
          deliverMessage
   }
}
