import "@stdlib/deploy";

/*
  TASK 1 - Counter 
  Implement a counter contract that will have 2 opcodes ('Add' / 'Subtract'),
  which adds or subtracts the received number (int32) from the number that is stored in the state (and stores the result back in the state).
  You also need to implement one getter with the name "counter" to get the current number from the state.
*/

extends mutates fun add(self: Int, addedValue: Int) {
  self = self + addedValue;
}
extends mutates fun sub(self: Int, subValue: Int) {
  self = self - subValue;
}

message Add {
  queryId: Int as uint64;
  number: Int as uint32;
}

message Subtract {
  queryId: Int as uint64;
  number: Int as uint32;
}

contract Task1 with Deployable {
    counter: Int as int32;

    init() {
      self.counter = 0;
    }

    receive(msg: Add) {
      self.counter.add(msg.number);
    }
    
    receive(msg: Subtract) {
      self.counter.sub(msg.number);
    }

    get fun counter(): Int {
      return self.counter;
    }
}
