import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - Optimized Concurrent Processing Utilities
/// Provides optimized concurrent processing with debouncing and batching

// MARK: - Debouncer
/// Debounces rapid user actions to prevent unnecessary processing
@MainActor
final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue
    private let delay: TimeInterval
    
    init(delay: TimeInterval = 0.3, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }
    
    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        
        let workItem = DispatchWorkItem(block: action)
        self.workItem = workItem
        
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    func cancel() {
        workItem?.cancel()
    }
}

// MARK: - Async Debouncer
/// Async/await compatible debouncer
actor AsyncDebouncer {
    private var task: Task<Void, Never>?
    private let delay: TimeInterval
    
    init(delay: TimeInterval = 0.3) {
        self.delay = delay
    }
    
    func debounce(action: @Sendable @escaping () async -> Void) {
        task?.cancel()
        
        task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await action()
            } catch {
                // Task was cancelled
            }
        }
    }
    
    func cancel() {
        task?.cancel()
    }
}

// MARK: - Batch Processor
/// Processes items in optimized batches to minimize context switches
@MainActor
final class BatchProcessor<Input, Output> {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "BatchProcessor")
    
    typealias ProcessingClosure = (Input) async throws -> Output
    
    private let batchSize: Int
    private let maxConcurrency: Int
    private var pendingItems: [Input] = []
    private var isProcessing = false
    
    init(batchSize: Int = 10, maxConcurrency: Int = 4) {
        self.batchSize = batchSize
        self.maxConcurrency = maxConcurrency
    }
    
    /// Add items for batch processing
    func addItems(_ items: [Input]) {
        pendingItems.append(contentsOf: items)
    }
    
    /// Process all pending items in optimized batches
    func processBatches(
        using processor: @escaping ProcessingClosure,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> [Output] {
        guard !isProcessing else {
            logger.warning("Batch processing already in progress")
            return []
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let items = pendingItems
        pendingItems.removeAll()
        
        return try await processItemsConcurrently(
            items,
            processor: processor,
            onProgress: onProgress
        )
    }
    
    private func processItemsConcurrently(
        _ items: [Input],
        processor: @escaping ProcessingClosure,
        onProgress: ((Double) -> Void)?
    ) async throws -> [Output] {
        guard !items.isEmpty else { return [] }
        
        var results: [Output] = []
        results.reserveCapacity(items.count)
        
        // Process in batches
        for batchStart in stride(from: 0, to: items.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, items.count)
            let batch = Array(items[batchStart..<batchEnd])
            
            // Process batch concurrently with limited concurrency
            let batchResults = try await withThrowingTaskGroup(of: (Int, Output).self) { group in
                // Limit concurrent tasks
                var activeTasks = 0
                var nextIndex = 0
                var collectedResults: [(Int, Output)] = []
                
                while nextIndex < batch.count || activeTasks > 0 {
                    // Add tasks up to concurrency limit
                    while activeTasks < maxConcurrency && nextIndex < batch.count {
                        let index = nextIndex
                        let item = batch[index]
                        
                        group.addTask {
                            let result = try await processor(item)
                            return (index, result)
                        }
                        
                        activeTasks += 1
                        nextIndex += 1
                    }
                    
                    // Collect completed results
                    if let result = try await group.next() {
                        collectedResults.append(result)
                        activeTasks -= 1
                        
                        // Update progress
                        let totalProgress = Double(batchStart + collectedResults.count) / Double(items.count)
                        onProgress?(totalProgress)
                    }
                }
                
                // Sort by original index to maintain order
                return collectedResults.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            
            results.append(contentsOf: batchResults)
        }
        
        return results
    }
}

// MARK: - UI Update Batcher
/// Batches UI updates to minimize main actor context switches
@MainActor
final class UIUpdateBatcher {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "UIUpdateBatcher")
    
    private var pendingUpdates: [() -> Void] = []
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval
    
    init(updateInterval: TimeInterval = 0.016) { // ~60 FPS
        self.updateInterval = updateInterval
    }
    
    /// Add a UI update to the batch
    func addUpdate(_ update: @escaping () -> Void) {
        pendingUpdates.append(update)
        
        if updateTimer == nil {
            scheduleFlush()
        }
    }
    
    /// Flush all pending updates immediately
    func flush() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        guard !pendingUpdates.isEmpty else { return }
        
        let updates = pendingUpdates
        pendingUpdates.removeAll()
        
        // Execute all updates in a single main actor call
        updates.forEach { $0() }
        
        logger.debug("Flushed \(updates.count) UI updates")
    }
    
    private func scheduleFlush() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: false) { _ in
            Task { @MainActor in
                self.flush()
            }
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}

// MARK: - Optimized Task Group
/// Enhanced TaskGroup with better error handling and cancellation
struct OptimizedTaskGroup<Input, Output> {
    let maxConcurrency: Int
    let logger = Logger(subsystem: "com.snapzify.app", category: "OptimizedTaskGroup")
    
    init(maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.maxConcurrency = maxConcurrency
    }
    
    /// Process items with optimized concurrency control
    func process(
        items: [Input],
        priority: TaskPriority = .userInitiated,
        processor: @escaping (Input) async throws -> Output
    ) async throws -> [Output] {
        guard !items.isEmpty else { return [] }
        
        return try await withThrowingTaskGroup(
            of: (Int, Result<Output, Error>).self,
            returning: [Output].self
        ) { group in
            // Semaphore for concurrency control
            let semaphore = AsyncSemaphore(value: maxConcurrency)
            
            // Add all tasks
            for (index, item) in items.enumerated() {
                group.addTask(priority: priority) {
                    await semaphore.wait()
                    defer { semaphore.signal() }
                    
                    do {
                        let result = try await processor(item)
                        return (index, .success(result))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            
            // Collect results
            var results: [(Int, Result<Output, Error>)] = []
            results.reserveCapacity(items.count)
            
            for try await result in group {
                results.append(result)
                
                // Check for cancellation
                if Task.isCancelled {
                    group.cancelAll()
                    throw CancellationError()
                }
            }
            
            // Sort by index and extract results
            results.sort { $0.0 < $1.0 }
            
            var outputs: [Output] = []
            var errors: [Error] = []
            
            for (_, result) in results {
                switch result {
                case .success(let output):
                    outputs.append(output)
                case .failure(let error):
                    errors.append(error)
                }
            }
            
            // Log errors but don't fail if some succeeded
            if !errors.isEmpty {
                logger.warning("Processing completed with \(errors.count) errors out of \(items.count) items")
            }
            
            return outputs
        }
    }
}

// MARK: - Async Semaphore
/// Async/await compatible semaphore for concurrency control
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int) {
        self.value = value
    }
    
    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            value += 1
        }
    }
}

// MARK: - Processing Coordinator
/// Coordinates all concurrent processing with optimizations
@MainActor
final class ProcessingCoordinator {
    static let shared = ProcessingCoordinator()
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "ProcessingCoordinator")
    private let debouncer = AsyncDebouncer(delay: 0.5)
    private let uiUpdateBatcher = UIUpdateBatcher()
    private var activeProcessors: Set<UUID> = []
    
    private init() {}
    
    /// Process media with optimized concurrency and debouncing
    func processMedia(
        _ input: MediaInput,
        debounced: Bool = true,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> ProcessingResult {
        let processorId = UUID()
        
        if debounced {
            // Debounce rapid requests
            await debouncer.debounce {
                await self.performProcessing(
                    processorId: processorId,
                    input: input,
                    onProgress: onProgress
                )
            }
            
            // Wait for processing to complete
            while activeProcessors.contains(processorId) {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            // Return a placeholder for now
            throw MediaProcessingError.cancelled
        } else {
            return try await performProcessingWithResult(
                processorId: processorId,
                input: input,
                onProgress: onProgress
            )
        }
    }
    
    private func performProcessing(
        processorId: UUID,
        input: MediaInput,
        onProgress: @escaping (Double, String) -> Void
    ) async {
        activeProcessors.insert(processorId)
        defer { activeProcessors.remove(processorId) }
        
        do {
            _ = try await performProcessingWithResult(
                processorId: processorId,
                input: input,
                onProgress: onProgress
            )
        } catch {
            logger.error("Processing failed: \(error)")
        }
    }
    
    private func performProcessingWithResult(
        processorId: UUID,
        input: MediaInput,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> ProcessingResult {
        activeProcessors.insert(processorId)
        defer { activeProcessors.remove(processorId) }
        
        // Use the unified processor with batched UI updates
        let processor = UnifiedMediaProcessor(
            ocrService: ServiceContainer.shared.ocrService,
            scriptConversionService: ServiceContainer.shared.scriptConversionService,
            chineseProcessingService: ServiceContainer.shared.chineseProcessingService,
            streamingChineseProcessingService: ServiceContainer.shared.streamingChineseProcessingService,
            mediaStorage: MediaStorageService.shared,
            documentStore: ServiceContainer.shared.documentStore
        )
        
        // Wrap progress updates in batching
        processor.onProgress = { [weak self] progress, message in
            self?.uiUpdateBatcher.addUpdate {
                onProgress(progress, message)
            }
        }
        
        let result = try await processor.process(input, configuration: .default)
        
        // Flush any remaining UI updates
        uiUpdateBatcher.flush()
        
        return result
    }
    
    /// Cancel all active processing
    func cancelAll() {
        logger.info("Cancelling all active processors")
        debouncer.cancel()
        activeProcessors.removeAll()
        uiUpdateBatcher.flush()
    }
}