import "@stdlib/deploy";

/*
  TASK 5 - NFT random swap 
  The smart contract contains a bunch of different NFTs.
  A user brings his NFT (sends it to the smart contract), with 2.1 TON (2 for admin's profit, 0.1 for gas) in attachment (as fee for swap).
  The smart contract randomly chooses some NFT from the available NFTs (including the newly incoming one) and gives it to the user in exchange for the brought NFT (but occasionally just returns user's NFT in some cases).
  Admin can deposit NFTs without swap logic. Any NFT received from the admin is considered deposited. Admin can't swap.
  Admin can withdraw all NFTs at once, and also all TONs collected from users as fees.
  Implement getter that will return NFT addresses held by the smart contract.
  Implement getter that will return the amount of admin`s profit collected.

  In details, the smart contract (later: SC) should have this logic:
  Messages
  * AdminWithdrawalProfit 
   - SC should check that sender is the admin / otherwise throw "Insufficient privelegies"
   - SC should send all collected fees to admin except 0.1 TON (use AdminFetchProfit message as body)
     In other words: after each such operation, the contract's balance should be equal to 0.1 TON (which are reserved for storage) and the rest should be sent to the admin
  * AdminWithdrawalAllNFTs
   - SC should check that incoming tx TON value is enough for NFT withdrawal. Specifically, at least: (1 + totalNftsHeld * 0.08) TONs. Otherwise throw "Insufficent funds"
   - SC should check that sender is the admin, throw "Invalid sender" otherwise
   - If all checks pass, SC should send NFTs one by one to the admin 
   - SC should be able to withdraw all NFTs by a single message from admin
  * OwnershipAssigned 
   - if prevOwner is the owner's (admin) address, then add NFT to the collection
   - if value of TON attached is less then 2.1 TON then stop execution and return NFT back,
     but only in case that TON attached is enough to process refund without losing TONs on the SC's balance
   - randomly select NFT to send from all the NFTs that smart contract has
   - send the selected NFT to the sender with all remaining balance (except for admin profit = fees collected from this and other swaps)
     In other words: the contract's balance should increase by exactly 2 TON, some incoming TONs will be consumed for gas and the remainings of the incoming TONs should be refunded to the sender
  
  Getters
  * profit
   - returns how much collected fees is available to withdraw for the admin (all fees minus 0.1 TON)
  * nfts
   - returns dict of held NFTs with NFT indexes (sequential numbers from 0, 1, 2 ... and up to 'totalNftsHeld-1') as keys and NFT address as values 
     the order of NFTs in this dictionary doesn't matter
*/

message AdminWithdrawalProfit {
  queryId: Int as uint64;
}

message AdminWithdrawalAllNFTs {
  queryId: Int as uint64;
}

message AdminFetchProfit {
  queryId: Int as uint64;
}

message FetchNFTs {
  queryId: Int as uint64;
}

message(0x05138d91) OwnershipAssigned {
    queryId: Int as uint64;
    prevOwner: Address;
    forwardPayload: Slice as remaining; 
}

message(0x5fcc3d14) Transfer { 
    queryId: Int as uint64;            
    newOwner: Address; 
    responseDestination: Address; 
    customPayload: Cell?; 
    forwardAmount: Int as coins; 
    forwardPayload: Slice as remaining; 
}

contract Task5 with Deployable {
  seed: Int as uint128;
  owner: Address;
  collection: map<Int as uint16, Address>;
  collectionLength: Int = 0;
  lockBalance: Int = 0;

  const SmartContractFee: Int = ton("2");
  const SmartContractFullFeeForProcess: Int = ton("2.1");
  const WithdrawMinTon: Int = ton("1");
  const SmartContractMinFeeForProcess: Int = ton("0.1");
  const WithdrawMinTonForOneNFT: Int = ton("0.08");
  const MinTonForStorage: Int = ton("0.01");

  init(seed: Int, owner: Address) {
    self.owner = owner;
    self.seed = seed; // needed to deploy multiple smart contracts copies from one admin address
  }

  receive(msg: OwnershipAssigned) {
    let sender: Address = sender();
    if (msg.prevOwner == self.owner) {
      self.collection.set(self.collectionLength, sender);
      self.collectionLength = self.collectionLength + 1;
    } else {
      if (context().value < self.SmartContractFullFeeForProcess) {
        // require(self.SmartContractMinFeeForProcess <= context().value, "Insufficient balance");
        // if (self.SmartContractMinFeeForProcess <= context().value) {
          // self.collection.set(self.collectionLength, sender);
          // self.collectionLength = self.collectionLength + 1;
        // }

        nativeReserve(myBalance() - context().value, 0);
        self.changeNFTOwner(sender, msg.queryId, msg.prevOwner);
      } else {
        let randomIndex: Int = random(0, self.collectionLength);
        if (randomIndex == self.collectionLength) {
          self.changeNFTOwnerAndDecreaseFee(sender, msg.queryId, msg.prevOwner);
        } else {
          let randomNFTAddress: Address? = self.collection.get(randomIndex);
          self.changeNFTOwnerAndDecreaseFee(randomNFTAddress!!, msg.queryId, msg.prevOwner);
          self.collection.set(randomIndex, sender);
        }
      }
    }
  }

  receive(msg: AdminWithdrawalProfit) {
    let sender: Address = sender();
    require(sender == self.owner, "Insufficient privelegies");

    self.lockBalance = 0;
    nativeReserve(self.lockBalance, 0);
    
    send(
      SendParameters{
        to: sender,
        bounce: true,
        value: myBalance() - context().value - self.MinTonForStorage,
        body: AdminFetchProfit{
          queryId: msg.queryId
        }.toCell(),
        mode: SendRemainingValue + SendIgnoreErrors
      }
    );
  }

  receive(msg: AdminWithdrawalAllNFTs) {
    let sender: Address = sender();
    let requireBalance: Int = ton("1") + (ton("0.08") * self.collectionLength);
    if (sender != myAddress()) {
      require(context().value >= requireBalance, "Insufficent funds");
      require(sender == self.owner, "Invalid sender");
    }
    
    let repeatValue: Int = min(100, self.collectionLength);
    repeat (repeatValue) {
      let nftAddress: Address? = self.collection.get(self.collectionLength - 1);
      send(
        SendParameters{
          to: nftAddress!!,
          value: ton("0.08"),
          body: Transfer{
            queryId: msg.queryId,
            newOwner: self.owner,
            responseDestination: self.owner,
            customPayload: null,
            forwardAmount: ton("0.08"),
            forwardPayload: emptySlice()
          }.toCell(),
          mode: 0
        }
      );
      self.collectionLength = self.collectionLength - 1;
    }
    if (self.collectionLength > 0) {
      send(
        SendParameters{
          to: myAddress(),
          value: 0,
          body: AdminWithdrawalAllNFTs{queryId: msg.queryId}.toCell(),
          mode: SendRemainingValue
        }
      );
    }
  }

  fun changeNFTOwner(nftAddress: Address, queryId: Int, newOwner: Address) {
    send(
      SendParameters{
        to: nftAddress,
        value: 0,
        body: Transfer{
          queryId: queryId,
          newOwner: newOwner,
          responseDestination: newOwner,
          customPayload: null,
          forwardAmount: 0,
          forwardPayload: emptySlice()
        }.toCell(),
        mode: SendRemainingValue
      }
    );
  }

  fun changeNFTOwnerWithValue(nftAddress: Address, queryId: Int, newOwner: Address) {
    send(
      SendParameters{
        to: nftAddress,
        value: ton("0.08"),
        body: Transfer{
          queryId: queryId,
          newOwner: self.owner,
          responseDestination: self.owner,
          customPayload: null,
          forwardAmount: ton("0.08"),
          forwardPayload: emptySlice()
        }.toCell(),
        mode: 0
      }
    );
  }

  fun changeNFTOwnerAndDecreaseFee(nftAddress: Address, queryId: Int, newOwner: Address) {
    self.lockBalance = self.lockBalance + self.SmartContractFee;
    nativeReserve(self.lockBalance, 0);
    send(
      SendParameters{
        to: nftAddress,
        value: 0,
        body: Transfer{
          queryId: queryId,
          newOwner: newOwner,
          responseDestination: newOwner,
          customPayload: null,
          forwardAmount: 0,
          forwardPayload: emptySlice()
        }.toCell(),
        mode: SendRemainingBalance
      }
    );
  }

  get fun profit(): Int { 
    let balance: Int = myBalance() - self.MinTonForStorage;
    return balance;
  }
  
  get fun nfts(): map<Int as uint16, Address> { 
    return self.collection;
  }
}
