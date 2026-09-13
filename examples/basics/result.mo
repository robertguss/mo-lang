module Basics.Result
expose Account, BankError, withdraw, remaining

intent "Return failure as an Error value, and pass it up to the caller with try."

struct Account
  balance: UInt64
  frozen: Bool
end

enum BankError
  Frozen
  Short(by: UInt64)
end

fn check(account: Account) : Result(Account, BankError)
  return Error(Frozen) if account.frozen
  Ok(account)
end

fn withdraw(account: Account, amount: UInt64) : Result(Account, BankError)
  open = try check(account)
  return Error(Short(by: amount - open.balance)) if amount > open.balance
  Ok(Account(balance: open.balance - amount, frozen: open.frozen))
end

fn remaining(account: Account, amount: UInt64) : Result(UInt64, BankError)
  after = try withdraw(account, amount)
  Ok(after.balance)
end

test "a withdrawal within the balance succeeds"
  assert remaining(Account(balance: 100, frozen: false), 30) is Ok(70)
end

test "an error passes up through both calls"
  assert remaining(Account(balance: 100, frozen: true), 30) is Error(Frozen)
  assert remaining(Account(balance: 10, frozen: false), 30) is Error(Short(20))
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
