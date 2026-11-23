// Gemini tutorial, Stage II

module bank_transactions {

   pure val ACCOUNTS = Set("Alice", "Bob", "Charlie")

   var balances: str -> int

   var total_money_supply: int

   var total_withdrawal_amount: int

   var total_deposit_amount: int

   def accum_wealth: int = ACCOUNTS.fold(0, (sum, k) => sum + balances.get(k)) // Zero param function is a value definition

   def money_is_conserved: bool = accum_wealth ==  (total_money_supply + total_deposit_amount - total_withdrawal_amount)

   action init = all {

       balances' = ACCOUNTS.map(n => (n , 100)).setToMap(), // <---- this comma is important in a group action expression
       total_money_supply' = ACCOUNTS.size() * 100,
       total_withdrawal_amount' = 0,
       total_deposit_amount'    = 0,

   }

   action withdrawal = 
     nondet from_account = ACCOUNTS.oneOf()
     nondet w = 1.to(50).oneOf()

    all {
       balances.get(from_account) >= w,

       balances.get(from_account) - w >= 0,

       balances' = balances.set(from_account, balances.get(from_account) - w),

       total_withdrawal_amount' = total_withdrawal_amount + w,

       total_deposit_amount' = total_deposit_amount,

       total_money_supply' = total_money_supply,

       accum_wealth <= total_money_supply  // invoke accum_wealth as value and the result of a function call
        
   }

   action deposit = 
       nondet to_account = ACCOUNTS.oneOf()
       nondet d = 1.to(50).oneOf()
       all {

           
	   balances' = balances.set(to_account, balances.get(to_account) + d) ,
	   total_deposit_amount' = total_deposit_amount + d,
	   total_withdrawal_amount' = total_withdrawal_amount,
	   total_money_supply' = total_money_supply

       }

   action transfer = 
       nondet from_account = ACCOUNTS.oneOf()
       nondet to_account   = ACCOUNTS.oneOf()
       nondet w = 1.to(50).oneOf()
       all {
              not (to_account == from_account),
              balances.get(from_account) >= w,      // To, inject a bug, comment this line
              balances.get(from_account) - w >= 0,  // and, this line too.
	      // Updating a map in Quint is non-mutating (creates a new map transition)
              balances' = balances.set(from_account, balances.get(from_account) - w).set(to_account,   balances.get(to_account)   + w),
              accum_wealth <= total_money_supply,  // invoke accum_wealth as value and the result of a function call
	      total_withdrawal_amount' = total_withdrawal_amount, 
	      total_deposit_amount' = total_deposit_amount,
	      total_money_supply' = total_money_supply 

	   }

    action step = any {
                     withdrawal,
	             deposit,
	             transfer
	      }

     // The following invariant doesn't proceed beyond State 0, because the condition fails, just after initialization
     // Example: 
     // [Frame 0]
     //     q::initAndInvariant => false
     //      └─ init => true

     // [State 0] { balances: Map("Alice" -> 100, "Bob" -> 100, "Charlie" -> 100), total_deposit_amount: 0, total_money_supply: 300, total_withdrawal_amount: 0 }
     // val no_negative_balance: bool = balances.keys().map(k => balances.get(k)).filter(v => v >= 0) == Set()

     val no_negative_balance: bool = ACCOUNTS.forall(a => balances.get(a) >= 0)

}
 
