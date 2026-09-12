import Foundation

struct FixedCapacityRingBuffer<Element> {
    let capacity: Int
    private var storage: [Element?]
    private var startIndex = 0
    private(set) var count = 0
    private(set) var droppedCount: UInt64 = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: Element) {
        if count < capacity {
            storage[(startIndex + count) % capacity] = element
            count += 1
        } else {
            droppedCount += 1
            storage[startIndex] = element
            startIndex = (startIndex + 1) % capacity
        }
    }

    var elements: [Element] {
        (0..<count).compactMap { offset in
            storage[(startIndex + offset) % capacity]
        }
    }
}
