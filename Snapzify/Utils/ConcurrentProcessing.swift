import Foundation
import UIKit

// MARK: - Task Coordinator
/// Manages concurrent tasks with proper resource management
actor TaskCoordinator {
    private var activeTasks: [UUID: Task<Void, Error>] = [:]
    private let maxConcurrentTasks: Int
    private var pendingTasks: [(id: UUID, work: () async throws -> Void)] = []
    private var isProcessing = false
    
    init(maxConcurrentTasks: Int = Constants.Performance.concurrentOperationLimit) {
        self.maxConcurrentTasks = maxConcurrentTasks
    }
    
    // MARK: - Task Management
    
    func submit(
        id: UUID = UUID(),
        priority: TaskPriority = .medium,
        work: @escaping () async throws -> Void
    ) async throws {
        // If under limit, execute immediately
        if activeTasks.count < maxConcurrentTasks {
            let task = Task(priority: priority) {
                try await work()
            }
            activeTasks[id] = task
            
            // Clean up when done
            Task {
                _ = try? await task.value
                await self.removeTask(id)
                await self.processNextPending()
            }
        } else {
            // Queue the task
            pendingTasks.append((id: id, work: work))
        }
    }
    
    func cancel(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        pendingTasks.removeAll { $0.id == id }
    }
    
    func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        pendingTasks.removeAll()
    }
    
    func waitForAll() async {
        for task in activeTasks.values {
            _ = try? await task.value
        }
    }
    
    // MARK: - Private Methods
    
    private func removeTask(_ id: UUID) {
        activeTasks.removeValue(forKey: id)
    }
    
    private func processNextPending() async {
        guard !pendingTasks.isEmpty,
              activeTasks.count < maxConcurrentTasks else { return }
        
        let next = pendingTasks.removeFirst()
        try? await submit(id: next.id, work: next.work)
    }
}

// MARK: - Batch Processor
/// Processes items in optimized batches
struct BatchProcessor<Input, Output> {
    let batchSize: Int
    let maxConcurrency: Int
    let processor: ([Input]) async throws -> [Output]
    
    init(
        batchSize: Int = 10,
        maxConcurrency: Int = Constants.Performance.concurrentOperationLimit,
        processor: @escaping ([Input]) async throws -> [Output]
    ) {
        self.batchSize = batchSize
        self.maxConcurrency = maxConcurrency
        self.processor = processor
    }
    
    func process(
        _ items: [Input],
        progress: ((Double) -> Void)? = nil
    ) async throws -> [Output] {
        guard !items.isEmpty else { return [] }
        
        // Create batches
        let batches = items.chunked(into: batchSize)
        var allResults: [Output] = []
        var processedCount = 0
        
        // Process batches with controlled concurrency
        try await withThrowingTaskGroup(of: (Int, [Output]).self) { group in
            var batchIndex = 0
            var activeBatches = 0
            
            for batch in batches {
                // Wait if we've hit concurrency limit
                while activeBatches >= maxConcurrency {
                    if let result = try await group.next() {
                        allResults.append(contentsOf: result.1)
                        processedCount += result.1.count
                        progress?(Double(processedCount) / Double(items.count))
                        activeBatches -= 1
                    }
                }
                
                // Add new batch
                let currentIndex = batchIndex
                group.addTask {
                    let results = try await self.processor(batch)
                    return (currentIndex, results)
                }
                activeBatches += 1
                batchIndex += 1
            }
            
            // Collect remaining results
            for try await result in group {
                allResults.append(contentsOf: result.1)
                processedCount += result.1.count
                progress?(Double(processedCount) / Double(items.count))
            }
        }
        
        return allResults
    }
}

// MARK: - Debouncer
/// Debounces rapid function calls
actor Debouncer {
    private var task: Task<Void, Never>?
    private let delay: TimeInterval
    
    init(delay: TimeInterval = 0.3) {
        self.delay = delay
    }
    
    func debounce(action: @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
    }
    
    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - Throttler
/// Throttles function calls to a maximum rate
actor Throttler {
    private var lastExecutionTime: Date?
    private let minimumInterval: TimeInterval
    private var pendingTask: Task<Void, Never>?
    
    init(minimumInterval: TimeInterval = 0.5) {
        self.minimumInterval = minimumInterval
    }
    
    func throttle(action: @escaping () async -> Void) async {
        let now = Date()
        
        if let lastTime = lastExecutionTime {
            let timeSinceLastExecution = now.timeIntervalSince(lastTime)
            if timeSinceLastExecution < minimumInterval {
                // Schedule for later
                let delay = minimumInterval - timeSinceLastExecution
                pendingTask?.cancel()
                pendingTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await action()
                    await self.updateLastExecutionTime()
                }
                return
            }
        }
        
        // Execute immediately
        await action()
        lastExecutionTime = now
    }
    
    private func updateLastExecutionTime() {
        lastExecutionTime = Date()
    }
}

// MARK: - Parallel Map
extension Sequence {
    /// Process elements in parallel with controlled concurrency
    func parallelMap<T>(
        maxConcurrency: Int = Constants.Performance.concurrentOperationLimit,
        transform: @escaping (Element) async throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(underestimatedCount)
        
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            var index = 0
            var iterator = makeIterator()
            var activeTaskCount = 0
            
            // Submit initial tasks up to maxConcurrency
            while activeTaskCount < maxConcurrency, let item = iterator.next() {
                let currentIndex = index
                group.addTask {
                    let result = try await transform(item)
                    return (currentIndex, result)
                }
                index += 1
                activeTaskCount += 1
            }
            
            // Process results and submit new tasks
            var resultsDict: [Int: T] = [:]
            
            for try await (resultIndex, result) in group {
                resultsDict[resultIndex] = result
                activeTaskCount -= 1
                
                // Submit next task if available
                if let nextItem = iterator.next() {
                    let currentIndex = index
                    group.addTask {
                        let result = try await transform(nextItem)
                        return (currentIndex, result)
                    }
                    index += 1
                    activeTaskCount += 1
                }
            }
            
            // Sort results by original index
            for i in 0..<index {
                if let result = resultsDict[i] {
                    results.append(result)
                }
            }
        }
        
        return results
    }
    
    /// Process elements in parallel and collect results as they complete
    func parallelForEach(
        maxConcurrency: Int = Constants.Performance.concurrentOperationLimit,
        operation: @escaping (Element) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = makeIterator()
            var activeTaskCount = 0
            
            // Submit initial tasks
            while activeTaskCount < maxConcurrency, let item = iterator.next() {
                group.addTask {
                    try await operation(item)
                }
                activeTaskCount += 1
            }
            
            // Process completions and submit new tasks
            while activeTaskCount > 0 {
                try await group.next()
                activeTaskCount -= 1
                
                if let nextItem = iterator.next() {
                    group.addTask {
                        try await operation(nextItem)
                    }
                    activeTaskCount += 1
                }
            }
        }
    }
}

// MARK: - Array Chunking
extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Async Semaphore
/// Async-safe semaphore for resource limiting
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(permits: Int) {
        self.permits = permits
    }
    
    func wait() async {
        if permits > 0 {
            permits -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
    
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            permits += 1
        }
    }
}

// MARK: - Resource Pool
/// Manages a pool of reusable resources
actor ResourcePool<Resource> {
    private var available: [Resource] = []
    private var inUse: Set<UUID> = []
    private var waiters: [CheckedContinuation<(UUID, Resource), Never>] = []
    private let factory: () async -> Resource
    private let maxResources: Int
    
    init(
        maxResources: Int,
        factory: @escaping () async -> Resource
    ) {
        self.maxResources = maxResources
        self.factory = factory
    }
    
    func acquire() async -> (id: UUID, resource: Resource) {
        // Try to get available resource
        if let resource = available.popLast() {
            let id = UUID()
            inUse.insert(id)
            return (id, resource)
        }
        
        // Create new resource if under limit
        if inUse.count < maxResources {
            let resource = await factory()
            let id = UUID()
            inUse.insert(id)
            return (id, resource)
        }
        
        // Wait for resource to become available
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func release(id: UUID, resource: Resource) {
        guard inUse.remove(id) != nil else { return }
        
        if let waiter = waiters.first {
            waiters.removeFirst()
            let newId = UUID()
            inUse.insert(newId)
            waiter.resume(returning: (newId, resource))
        } else {
            available.append(resource)
        }
    }
}