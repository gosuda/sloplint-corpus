// Door and Lock Speifications

module door_and_lock {

   type DoorAccess       = Open | Closed
   type LockCondition    = Locked | Unlocked
   type Ops              = OpenTheDoor | CloseTheDoor | LockTheDoor | UnlockTheDoor
   type RealDoor         = { door_access :DoorAccess, lock_condition :LockCondition }

   val door_is_stable = 
               not (physical_door.door_access == Open and physical_door.lock_condition == Locked)


     var physical_door: RealDoor

     var input_ops: List[Ops]

     val valid_ops: Set[Ops] = Set(OpenTheDoor , CloseTheDoor , LockTheDoor , UnlockTheDoor)

  action init = all {
     
          physical_door' = { door_access: Closed, lock_condition: Locked },
	  input_ops' = List()

   }

   action openDoor = all {
          length(input_ops) > 0,
          input_ops.head() == OpenTheDoor,
          physical_door.door_access == Closed and physical_door.lock_condition == Unlocked,
	  physical_door' = {door_access: Open, lock_condition: Unlocked},
	  input_ops' = input_ops.tail()
   }

   action closeDoor = all {
            length(input_ops) > 0,
            input_ops.head() == CloseTheDoor,
            physical_door.door_access == Open and physical_door.lock_condition == Unlocked,
            physical_door' = {door_access: Closed, lock_condition: Unlocked},
            input_ops' = input_ops.tail()
   }


   action lockDoor = all {
            length(input_ops) > 0,
            input_ops.head() == LockTheDoor,
            physical_door.door_access == Closed and physical_door.lock_condition == Unlocked,
            physical_door' = {door_access: Closed, lock_condition: Locked},
            input_ops' = input_ops.tail()
   }
 

   action unlockDoor = all {
            length(input_ops) > 0,
            input_ops.head() == UnlockTheDoor,
            physical_door.door_access == Closed and physical_door.lock_condition == Locked,
            physical_door' = {door_access: Closed, lock_condition: Unlocked},
            input_ops' = input_ops.tail()
   }

   action gen_ops = {
            nondet next_op = valid_ops.oneOf() {
	           all {
	              input_ops' = input_ops.append(next_op),
                      physical_door' = physical_door
		   }
	    }
   }

   action step = any {
                  openDoor,
                  closeDoor,
		  lockDoor,
		  unlockDoor,
		  gen_ops
           
   }
}



