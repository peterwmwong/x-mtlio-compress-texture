import Foundation
import Metal
import MetalKit

let COMPRESSION_METHOD = MTLIOCompressionMethod.lz4;
let UNCOMPRESSED_FILE_URL = URL(filePath: "/tmp/uncompressed.dat")
let COMPRESSED_FILE_URL = URL(filePath: "/tmp/compressed.lz4")

let BYTES_PER_RGBA_PIXEL = MemoryLayout<SIMD4<UInt8>>.size;

if ProcessInfo.processInfo.arguments.count < 2 {
    print("No image file path provided")
    exit(1)
}
let imagePath = ProcessInfo.processInfo.arguments[1]

if !FileManager.default.fileExists(atPath: imagePath) {
    print("\(imagePath) does not exist")
    exit(1)
}

print("Loading image file \(imagePath)")
let device = MTLCreateSystemDefaultDevice()!

// Load image bytes (assumed RGBA 8-bit per channel) using MTKTextureLoader and MTLTexture.getBytes()
let sourceTexture = try MTKTextureLoader(device: device).newTexture(URL: URL(filePath: imagePath))
let bytesPerRow = sourceTexture.width * BYTES_PER_RGBA_PIXEL;
let totalBytes = bytesPerRow * sourceTexture.height
var imageBytes: [UInt8] = Array<UInt8>.init(repeating: 0, count: totalBytes)

// Assumption: MTLTexture getBytes() will load imageBytes as an RGBA 8-bit format
sourceTexture.getBytes(&imageBytes,
                       bytesPerRow: bytesPerRow,
                       from: MTLRegion(
                        origin: MTLOrigin(x: 0, y: 0, z: 0),
                        size: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1)
                       ),
                       mipmapLevel: 0)

// Write raw pixels to an uncompressed file
try Data(bytes: &imageBytes, count: totalBytes).write(to: UNCOMPRESSED_FILE_URL)

// Write raw pixels to a compressed file
let context = MTLIOCreateCompressionContext(COMPRESSED_FILE_URL.absoluteString, COMPRESSION_METHOD, 64 * 1024)
MTLIOCompressionContextAppendData(context, &imageBytes, totalBytes)
MTLIOFlushAndDestroyCompressionContext(context)

// Check loading raw pixel texture data from file (created above).
func loadTextureUsingMTLIO(width: Int, height: Int, fileURL: URL, compressionMethod: MTLIOCompressionMethod?) throws {
    let fileHandle: MTLIOFileHandle;
    if let compressionMethod {
        // IMPORTANT
        // IMPORTANT
        // IMPORTANT
        // Specifying `compressionMethod:` here causes the below `load()` to throw "unrecognized selector sent to instance 0x600000164450".
        fileHandle = try device.makeIOHandle(url: fileURL, compressionMethod: compressionMethod)
    } else {
        fileHandle = try device.makeIOHandle(url: fileURL)
    }

    let textureDesc = MTLTextureDescriptor()
    textureDesc.width = width
    textureDesc.height = height
    textureDesc.pixelFormat = .bgra8Unorm
    let texture = device.makeTexture(descriptor: textureDesc)!
    let bytesPerRow = texture.width * BYTES_PER_RGBA_PIXEL;
    let bytesPerImage = bytesPerRow * texture.height

    let cmdQueue = try device.makeIOCommandQueue(descriptor: MTLIOCommandQueueDescriptor())
    let cmdBuffer = cmdQueue.makeCommandBuffer()

    // IMPORTANT
    // IMPORTANT
    // IMPORTANT
    // This line throws "unrecognized selector sent to instance 0x600000164450" when `compressionMethod:` is specified for `makeIOHandle()` above.
    cmdBuffer.load(
        texture,
        slice: 0,
        level: 0,
        size: MTLSize(width: texture.width, height: texture.height, depth: texture.depth),
        sourceBytesPerRow: bytesPerRow,
        sourceBytesPerImage: bytesPerImage,
        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceHandle: fileHandle,
        sourceHandleOffset: 0
    )
    cmdBuffer.commit()
    cmdBuffer.waitUntilCompleted()
}

print("Loading uncompressed file as texture...")
try loadTextureUsingMTLIO(width: sourceTexture.width, height: sourceTexture.height, fileURL: UNCOMPRESSED_FILE_URL, compressionMethod: nil)
print("... success!")

print("Loading compressed file as texture, get ready for an error...")
try loadTextureUsingMTLIO(width: sourceTexture.width, height: sourceTexture.height, fileURL: COMPRESSED_FILE_URL, compressionMethod: COMPRESSION_METHOD)
print("... success!") // Unfortunately, never gets here...
