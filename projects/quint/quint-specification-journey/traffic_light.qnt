// Traffic-light specifications

module traffic_light_spec {

type SIGNAL_COLORS = RED | GREEN | YELLOW
type MESSAGES = TIMER | RESET

// val on_message(m: MESSAGES, s: SIGNAL_COLORS): SIGNAL_COLORS = if (m == RESET) RED else s



var traffic_light: SIGNAL_COLORS
var message: MESSAGES

val no_invalid_color() = traffic_light == RED or traffic_light == GREEN or traffic_light == YELLOW

action init = all {

        traffic_light' = RED,
	message'       = TIMER
}

 action on_timer = all {
     traffic_light' = 
        
          if (traffic_light == RED) { GREEN }
          else 
	    if (traffic_light == GREEN) { YELLOW }
            else 
	       if (traffic_light == YELLOW) { RED }
	       else { RED }
    ,
     message' = message
 }


// action on_timer = all {
    // traffic_light' = GREEN,
    // message' = message
// }


action on_reset = all {
       traffic_light' = RED,
       message' = message
       }

action step = any {
                on_timer,
	        on_reset
	      }


}
