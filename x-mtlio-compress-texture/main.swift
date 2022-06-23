import Foundation
import Metal
import MetalKit

let TOTAL_BYTES = 1024
let COMPRESSION_METHOD = MTLIOCompressionMethod.lz4;
let UNCOMPRESSED_FILE_URL = URL(filePath: "/tmp/uncompressed.dat")
let COMPRESSED_FILE_URL = URL(filePath: "/tmp/compressed.lz4")

let device = MTLCreateSystemDefaultDevice()!
var dataBytes: [UInt8] = Array<UInt8>.init(repeating: 123, count: TOTAL_BYTES)

// Write raw data to an uncompressed file
try Data(bytes: &dataBytes, count: TOTAL_BYTES).write(to: UNCOMPRESSED_FILE_URL)

// Write raw data to a compressed file
let context = MTLIOCreateCompressionContext(COMPRESSED_FILE_URL.path(percentEncoded: false), COMPRESSION_METHOD, kMTLIOCompressionContextDefaultChunkSize)
MTLIOCompressionContextAppendData(context, &dataBytes, TOTAL_BYTES)
assert(MTLIOFlushAndDestroyCompressionContext(context) == MTLIOCompressionStatus.complete, "Failed to write \(COMPRESSED_FILE_URL)")

// Check loading raw pixel texture data from file (created above).
func loadBufferWithMTLIO(fileURL: URL, compressionMethod: MTLIOCompressionMethod?) throws {
    let fileHandle: MTLIOFileHandle;
    if let compressionMethod {
        fileHandle = try device.makeIOHandle(url: fileURL, compressionMethod: compressionMethod)
    } else {
        fileHandle = try device.makeIOHandle(url: fileURL)
    }

    let buffer = device.makeBuffer(length: TOTAL_BYTES)!
    let cmdQueue = try device.makeIOCommandQueue(descriptor: MTLIOCommandQueueDescriptor())
    let cmdBuffer = cmdQueue.makeCommandBuffer()

    cmdBuffer.load(buffer, offset: 0, size: TOTAL_BYTES, sourceHandle: fileHandle, sourceHandleOffset: 0)
    cmdBuffer.commit()
    cmdBuffer.waitUntilCompleted()
    assert(memcmp(buffer.contents(), dataBytes, TOTAL_BYTES) == 0, "Data is not the same")
}

print("Loading uncompressed file as texture...")
try loadBufferWithMTLIO(fileURL: UNCOMPRESSED_FILE_URL, compressionMethod: nil)
print("... success!")

print("Loading compressed file as texture, get ready for an error...")
try loadBufferWithMTLIO(fileURL: COMPRESSED_FILE_URL, compressionMethod: COMPRESSION_METHOD)
print("... success!")
