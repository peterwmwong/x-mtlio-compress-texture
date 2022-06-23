import Foundation
import Metal
import MetalKit

let COMPRESSION_METHOD = MTLIOCompressionMethod.lz4
let UNCOMPRESSED_FILE_URL = URL(filePath: "/tmp/uncompressed.dat")
let COMPRESSED_FILE_URL = URL(filePath: "/tmp/compressed.lz4")

let BYTES_PER_PIXEL = MemoryLayout<SIMD4<UInt8>>.size

assert(ProcessInfo.processInfo.arguments.count == 2, "No image file path provided")

let imagePath = ProcessInfo.processInfo.arguments[1]

assert(FileManager.default.fileExists(atPath: imagePath), "\(imagePath) does not exist")

let device = MTLCreateSystemDefaultDevice()!

print("Load image bytes from file \(imagePath) using MTKTextureLoader and MTLTexture.getBytes()...")
let sourceTexture = try MTKTextureLoader(device: device).newTexture(URL: URL(filePath: imagePath))

assert([.bgra8Unorm_srgb, .bgra8Unorm, .rgba8Unorm_srgb, .rgba8Unorm].contains(sourceTexture.pixelFormat), "Unexpected texture pixel format from loading image")
let bytesPerRow = sourceTexture.width * BYTES_PER_PIXEL
let totalBytes = bytesPerRow * sourceTexture.height
var originalImageBytes: [UInt8] = Array<UInt8>.init(repeating: 0, count: totalBytes)

sourceTexture.getBytes(&originalImageBytes,
                       bytesPerRow: bytesPerRow,
                       from: MTLRegion(
                        origin: MTLOrigin(x: 0, y: 0, z: 0),
                        size: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1)
                       ),
                       mipmapLevel: 0)

print("Writing image bytes (uncompressed) to \(UNCOMPRESSED_FILE_URL)...")
try Data(bytes: &originalImageBytes, count: totalBytes).write(to: UNCOMPRESSED_FILE_URL)

print("Writing image bytes (compressed) to \(COMPRESSED_FILE_URL)...")
let context = MTLIOCreateCompressionContext(COMPRESSED_FILE_URL.path(percentEncoded: false), COMPRESSION_METHOD, kMTLIOCompressionContextDefaultChunkSize)
MTLIOCompressionContextAppendData(context, &originalImageBytes, totalBytes)
let compressionStatus = MTLIOFlushAndDestroyCompressionContext(context)
assert(compressionStatus == MTLIOCompressionStatus.complete, "Failed to write \(COMPRESSED_FILE_URL)")

func loadTextureUsingMTLIO(width: Int, height: Int, fileURL: URL, compressionMethod: MTLIOCompressionMethod?) throws {
    let fileHandle: MTLIOFileHandle
    if let compressionMethod {
        fileHandle = try device.makeIOHandle(url: fileURL, compressionMethod: compressionMethod)
    } else {
        fileHandle = try device.makeIOHandle(url: fileURL)
    }

    let textureDesc = MTLTextureDescriptor()
    textureDesc.width = sourceTexture.width
    textureDesc.height = sourceTexture.height
    textureDesc.pixelFormat = sourceTexture.pixelFormat
    let texture = device.makeTexture(descriptor: textureDesc)!

    let cmdQueue = try device.makeIOCommandQueue(descriptor: MTLIOCommandQueueDescriptor())
    let cmdBuffer = cmdQueue.makeCommandBuffer()

    cmdBuffer.load(
        texture,
        slice: 0,
        level: 0,
        size: MTLSize(width: texture.width, height: texture.height, depth: texture.depth),
        sourceBytesPerRow: bytesPerRow,
        sourceBytesPerImage: totalBytes,
        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceHandle: fileHandle,
        sourceHandleOffset: 0
    )
    cmdBuffer.commit()
    cmdBuffer.waitUntilCompleted()

    print("  Verifying loaded image from texture...")
    var imageBytes: [UInt8] = Array<UInt8>.init(repeating: 0, count: totalBytes)
    texture.getBytes(&imageBytes,
                     bytesPerRow: bytesPerRow,
                     from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                     size: MTLSize(width: texture.width,
                                                   height: texture.height,
                                                   depth: texture.depth)),
                     mipmapLevel: 0)
    assert(memcmp(imageBytes, originalImageBytes, totalBytes) == 0, "Image is not the same")

}

print("Loading uncompressed file as texture...")
try loadTextureUsingMTLIO(width: sourceTexture.width, height: sourceTexture.height, fileURL: UNCOMPRESSED_FILE_URL, compressionMethod: nil)
print("... success!")

print("Loading compressed file as texture, get ready for an error...")
try loadTextureUsingMTLIO(width: sourceTexture.width, height: sourceTexture.height, fileURL: COMPRESSED_FILE_URL, compressionMethod: COMPRESSION_METHOD)
print("... success!")
