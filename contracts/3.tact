import "@stdlib/deploy";

/*
  TASK 3 - DEX
  Create a simple jetton dex contract that trades one pair of jettons: A and B.
  The price of jettons depends on the amount of jettons that smart contract has.
  Therefore, the smart contract needs to keep track of how much jettons it has.
  
  Price for the jetton A in swap B->A should be calculated by formula "amountOfJettonAOnContract * decimal / amountOfJettonBOnContract".
  Token prices must be decimalized for accuracy, so it is the prices that must be adjusted to decimal 1e9.
  Decimals are only needed for price accuracy. It should be set as 1e9.
  So, if smart contract has 10 of jetton A and 2 of jetton B, then after sending 1 jetton B you should receive 5 of jettons A.

  Example formula for amountOfAJettonToSend in B->A swap will be
  (amountOfJettonAOnContract * decimal / amountOfJettonBOnContract) * amountOfTokenBToSwap / decimal

  If smart contract pool doesn't have enough jettons to trade,
  then it should send incoming jettons back to the user. For a clearer explanation,
  let's look at the example we described above (smart contract has 10 of jetton A and 2 of jetton B).
  If user will send 3 jettons B, smart contract should reject the message (because contract does not have 3 * 5 = 15 jettons A)
  and send 3 jettons B back to the user.

  If smart contract receives a different jetton (neither A nor B) then throw an error.

  Implement a getter that returns the number of jettons in the pool and
  one more to get the price of jetton A or jetton B.
  Getters' behavior with incorrect parameter (address other than that of jetton A or B)
  is undefined (there are no such tests).
  
  Note:
  Admin can add jettons A and B just by sending them to the smart contract (we need to add initial supply to the pool for it to be functional).
  To be exact: any jettons (A or B) received from the admin are "added". Admin can't swap.
*/

message(0x7362d09c) TokenNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    from: Address;
    forwardPayload: Slice as remaining;
}

message(0xf8a7ea5) TokenTransfer {
    queryId: Int as uint64;
    amount: Int as coins;
    destination: Address;
    responseDestination: Address?;
    customPayload: Cell?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

struct JettonInfo {
  amount: Int as coins;
  address: Address;
}

contract Task3 with Deployable {
  owner: Address;
  jettonInfoA: JettonInfo;
  jettonInfoB: JettonInfo;
  const decimal: Int = 1000000000;

  init(admin: Address, newJettonAddressA: Address, newJettonAddressB: Address) {
    self.owner = admin;
    self.jettonInfoA = JettonInfo{amount: 0, address: newJettonAddressA};
    self.jettonInfoB = JettonInfo{amount: 0, address: newJettonAddressB};
  }

  receive(msg: TokenNotification) {
    let sender: Address = context().sender;
    require(self.jettonInfoB.address == sender || self.jettonInfoA.address == sender, "token is not valid");
    let isFromA: Bool = self.jettonInfoA.address == sender;
    if(msg.from == self.owner) {
      self.addToPool(isFromA, msg.amount);
    } else {
      self.handleSwap(isFromA, msg);
    }
  }

  fun addToPool(isFromA: Bool, amount: Int) {
    if (isFromA) {
      self.jettonInfoA.amount = self.jettonInfoA.amount + amount;
    } else {
      self.jettonInfoB.amount = self.jettonInfoB.amount + amount;
    }
  }

  fun handleSwap(isFromA: Bool, msg: TokenNotification) {
    let swapOutput: Int = self.calculateSwapOutput(isFromA, msg.amount);
    
    if ((isFromA && swapOutput >= self.jettonInfoB.amount) || (!isFromA && swapOutput >= self.jettonInfoA.amount)) {
      self.rejectSwap(isFromA, msg);
    } else {
      self.performSwap(isFromA, msg, swapOutput);
    }
  }

  fun calculateSwapOutput(isFromA: Bool, amount: Int): Int {
    if (isFromA) {
      return self.price(self.jettonInfoA.address) * amount / self.decimal;
    } else {
      return self.price(self.jettonInfoB.address) * amount / self.decimal;
    }
  }

  fun performSwap(isFromA: Bool, msg: TokenNotification, swapOutput: Int) {
    let tokenTransfer: TokenTransfer = TokenTransfer{
      amount: swapOutput,
      queryId: msg.queryId,
      destination: msg.from,
      responseDestination: myAddress(),
      customPayload: null,
      forwardTonAmount: ton("0.01"),
      forwardPayload: emptySlice()
    };
    
    if (isFromA) {
      self.jettonInfoA.amount = self.jettonInfoA.amount + msg.amount;
      self.jettonInfoB.amount = self.jettonInfoB.amount - swapOutput;
      send(
        SendParameters{
          to: self.jettonInfoB.address,
          value: ton("0.01"),
          body: tokenTransfer.toCell(),
          mode: SendIgnoreErrors
        }
      );
    } else {
      self.jettonInfoB.amount = self.jettonInfoB.amount + msg.amount;
      self.jettonInfoA.amount = self.jettonInfoA.amount - swapOutput;
      send(
        SendParameters{
          to: self.jettonInfoA.address,
          value: ton("0.01"),
          body: tokenTransfer.toCell(),
          mode: SendIgnoreErrors
        }
      );
    }
  }

  fun rejectSwap(isFromA: Bool, msg: TokenNotification) {
    let tokenTransfer: TokenTransfer = TokenTransfer{
      amount: msg.amount,
      queryId: msg.queryId,
      destination: msg.from,
      responseDestination: myAddress(),
      customPayload: null,
      forwardTonAmount: ton("0.01"),
      forwardPayload: emptySlice()
    };
    
    send(
      SendParameters{
        to: sender(),
        value: ton("0.01"),
        body: tokenTransfer.toCell(),
        mode: SendIgnoreErrors
      }
    );
  }
  
  get fun price(jetton: Address): Int {
    if (self.jettonInfoA.address == jetton) {
      return self.jettonInfoB.amount * self.decimal / self.jettonInfoA.amount;
    } else {
      return self.jettonInfoA.amount * self.decimal / self.jettonInfoB.amount;
    }
  }
  
  get fun balance(jetton: Address): Int {
    if (self.jettonInfoA.address == jetton) {
      return self.jettonInfoA.amount;
    } else {
      return self.jettonInfoB.amount;
    }
  }
}
