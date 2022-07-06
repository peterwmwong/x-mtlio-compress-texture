import Foundation
import Metal
import MetalKit

let COMPRESSION_METHOD = MTLIOCompressionMethod.lz4
let BYTES_PER_PIXEL = MemoryLayout<SIMD4<UInt8>>.size
let TEXTURE_WIDTH = 2048;
let TEXTURE_HEIGHT = 2048;
let TEXTURE_BYTES_PER_ROW = 2048 * BYTES_PER_PIXEL;
let TEXTURE_TOTAL_BYTES = TEXTURE_BYTES_PER_ROW * TEXTURE_HEIGHT;
let CUBE_FACE_RANGE = 0...1;

assert(ProcessInfo.processInfo.arguments.count == 3, "No image bytes file and compressed image bytes file path provided")

let textureRawBytes = ProcessInfo.processInfo.arguments[1]
assert(FileManager.default.fileExists(atPath: textureRawBytes), "\(textureRawBytes) does not exist")

let compressedTextureRawBytesPath = ProcessInfo.processInfo.arguments[2]
let compressedTextureRawBytesPathURL = URL(filePath: compressedTextureRawBytesPath)
assert(FileManager.default.fileExists(atPath: compressedTextureRawBytesPath), "\(compressedTextureRawBytesPath) does not exist")

let textureRawBytesData = try Data(contentsOf: URL(fileURLWithPath: textureRawBytes))
assert(textureRawBytesData.count == TEXTURE_TOTAL_BYTES, "Image bytes does not match expected number of bytes")
var originalImageBytes: [UInt8] = Array.init(repeating: 0, count: TEXTURE_TOTAL_BYTES)
let numBytesCopied = originalImageBytes.withUnsafeMutableBufferPointer { buffer in
    textureRawBytesData.copyBytes(to: buffer)
}

let device = MTLCreateSystemDefaultDevice()!
let textureDesc = MTLTextureDescriptor()
textureDesc.textureType = .typeCube
textureDesc.width = TEXTURE_WIDTH
textureDesc.height = TEXTURE_HEIGHT
textureDesc.depth = 1
textureDesc.swizzle.red = MTLTextureSwizzle.red
textureDesc.swizzle.green = MTLTextureSwizzle.green
textureDesc.swizzle.blue = MTLTextureSwizzle.blue
textureDesc.swizzle.alpha = MTLTextureSwizzle.alpha
textureDesc.pixelFormat = .rgba8Unorm
let texture = device.makeTexture(descriptor: textureDesc)!


print("Loading compressed file as texture, get ready for an error...")
let fileHandle: MTLIOFileHandle = try device.makeIOHandle(url: compressedTextureRawBytesPathURL, compressionMethod: COMPRESSION_METHOD)
let cmdQueue = try device.makeIOCommandQueue(descriptor: MTLIOCommandQueueDescriptor())
let cmdBuffer = cmdQueue.makeCommandBuffer()
print(
    texture.swizzle.red == MTLTextureSwizzle.red &&
    texture.swizzle.green == MTLTextureSwizzle.green &&
    texture.swizzle.blue == MTLTextureSwizzle.blue &&
    texture.swizzle.alpha == MTLTextureSwizzle.alpha
);
for i in CUBE_FACE_RANGE {
    cmdBuffer.load(
        texture,
        slice: i,
        level: 0,
        size: MTLSize(width: texture.width, height: texture.height, depth: texture.depth),
        sourceBytesPerRow: TEXTURE_BYTES_PER_ROW,
        sourceBytesPerImage: TEXTURE_TOTAL_BYTES,
        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceHandle: fileHandle,
        sourceHandleOffset: 0
    )
}
cmdBuffer.commit()
cmdBuffer.waitUntilCompleted()
assert(cmdBuffer.status == .complete, "Failed to load texture");

print("  Verifying loaded image from texture...")
var imageBytes: [UInt8] = Array<UInt8>.init(repeating: 0, count: TEXTURE_TOTAL_BYTES)
for i in CUBE_FACE_RANGE {
    texture.getBytes(&imageBytes,
                     bytesPerRow: TEXTURE_BYTES_PER_ROW,
                     bytesPerImage: TEXTURE_TOTAL_BYTES,
                     from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                     size: MTLSize(width: texture.width,
                                                   height: texture.height,
                                                   depth: texture.depth)),
                     mipmapLevel: 0,
                     slice: i)
    
    if memcmp(imageBytes, originalImageBytes, TEXTURE_TOTAL_BYTES) != 0 {
        print(
            texture.swizzle.red == MTLTextureSwizzle.red &&
            texture.swizzle.green == MTLTextureSwizzle.green &&
            texture.swizzle.blue == MTLTextureSwizzle.blue &&
            texture.swizzle.alpha == MTLTextureSwizzle.alpha
        );
        let displayByteRange = 0..<4;
        print("[Face #\(i)] expected: \(originalImageBytes[displayByteRange]) actual: \(imageBytes[displayByteRange])")
        assertionFailure("Image is not the same")
    }
}
print("... success!")
