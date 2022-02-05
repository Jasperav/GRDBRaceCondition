import Foundation
import GRDB

/// Simplified class which shows how GRDB and a separate dispatch queue will perform a race condition
class RaceCondition {
    /// Stupid counter which will show the final count is not equal when both the dispatchQueue and grdbQueue are performing work
    private var counter = 0
    
    /// This is my shared queue which my app uses for synchronization across multiple classes
    private let dispatchQueue = DispatchQueue(label: "serial")
    
    /// This is the database
    private let grbdQueue = DatabaseQueue()
    
    init() {}
    
    /// How to create a race condition
    func demonstrateRaceCondition() {
        // Network requests are processed inside the dispachQueue, so let's say I receive 10_000 network calls which increases the counter
        // This happens async some time in the future, because I receive data from a websocket
        dispatchQueue.async { [unowned self] in
            addToWork()
        }
        
        // While receiving data through the websocket, users continue to click around in my appliation
        // Because I need to do database related stuff, I need a DatabaseQueue for writing
        // To stimulate a real situation, also perform a lot of work on the GRDB queue, so eventually the user clicks at the exact same
        // moment when a network request comes in
        // and both methods will call work()
        try! grbdQueue.write { [unowned self] _ in
            addToWork()
        }
        
        // Sleep a little so the tasks can finish
        sleep(5)
        
        print("Final count unsafe: \(counter)")
    }
    
    /// Current expensive solution, which I now use
    func demonstrateSafeCondition() {
        
        /// A wrapper around the DatabaseQueue which will check if the user is on the serial queue
        /// If not, sync on the current queue and retry
        class Wrapper {
            private let database: DatabaseQueue
            private let queue: DispatchQueue
            
            init(database: DatabaseQueue, queue: DispatchQueue) {
                self.database = database
                self.queue = queue
            }
            
            func dispatchQueueLabel() -> String? {
                String(
                    cString: __dispatch_queue_get_label(nil),
                    encoding: .utf8
                )
            }
            
            /// Race condition free method
            func write(work: () -> ()) {
                if
                    let dispatchQueue = dispatchQueueLabel(),
                    dispatchQueue == "serial" {
                    // Already on the serial queue, just run the block
                    try! database.write { _ in
                        work()
                    }
                } else {
                    return queue.sync {
                        write(work: work)
                    }
                }
            }
        }
        
        let wrapper = Wrapper(database: grbdQueue, queue: dispatchQueue)
        
        dispatchQueue.async { [unowned self] in
            addToWork()
        }
        
        wrapper.write { [unowned self] in
            addToWork()
        }
        
        sleep(5)
        
        print("Final count safe: \(counter)")
    }
    
    private func addToWork() {
        var add = 100_000
        
        while add > 0 {
            work()
            
            add -= 1
        }
    }

    /// This is a method which can be called at any time but needs to be synchronized
    /// I have multiple classes which have a method like this, I can not make this an Actor class since they have their own independent queue
    /// Ideally, I want this method to be only called from one queue
    /// In my application, this method can update the currentUser variable, it is really important that at any moment in time, this method is only ever called from 1 queue
    func work() {
        counter += 1
    }

}
