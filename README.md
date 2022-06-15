This command line project reproduces an error when using `MTLIOCommandBuffer.load(texture:)` with a file handle with a compression method.

# Background

The WWDC 2022 session [Load resources faster with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10104) outlines how to create a compressed pack file and how to load it with the new Metal 3 features with MTLIO.

Here are the session's ([14:03](https://developer.apple.com/videos/play/wwdc2022/10104/?time=843)) directions for creating a compressed pack file:

```swift
// Create a compressed file

// Create compression context
let chunkSize = 64 * 1024
let compressionMethod = MTLIOCompressionMethod.zlib
let compressionContext = MTLIOCreateCompressionContext(compressedFilePath, compressionMethod, chunkSize)

// Append uncompressed file data to the compression context
// Get uncompressed file data
MTLIOCompressionContextAppendData(compressionContext, filedata.bytes, filedata.length)


// Write the compressed file
MTLIOFlushAndDestroyCompressionContext(compressionContext)
```

Here are the session's ([15:00](https://developer.apple.com/videos/play/wwdc2022/10104/?time=900)) directions for loading the compressed pack file as a file handle:

```swift
// Create an Metal File IO Handle

// Create handle to a compressed file
var compressedFileIOHandle : MTLIOFileHandle!
do {
    try compressedFileHandle = device.makeIOHandle(url: compressedFilePath, compressionMethod: MTLIOCompressionMethod.zlib)
} catch {
    print(error)
}
```

# Findings

Running this project...

1. Loads the image bytes using `MTKTextureLoader` and `MTLTexture.getBytes` from `brick.png`.
2. Writes the uncompressed image bytes to `/tmp/uncompressed.dat`
    ```swift
    try Data(bytes: &imageBytes, count: totalBytes).write(to: UNCOMPRESSED_FILE_URL)
    ```
3. Writes the compressed image bytes to `/tmp/compressed.lz4`
    ```swift
    let context = MTLIOCreateCompressionContext(COMPRESSED_FILE_URL.absoluteString, COMPRESSION_METHOD, 64 * 1024)
    MTLIOCompressionContextAppendData(context, &imageBytes, totalBytes)
    MTLIOFlushAndDestroyCompressionContext(context)
    ```
4. Loads the uncompressed image bytes file into a new MTLTexture using MTLIO
5. Loads the compressed image bytes file into a new MTLTexture using MTLIO
    - The following error occurs on the line calling `MTLIOCommandBuffer.load()`
      ```
        2022-06-15 18:00:51.878097-0500 x-mtlio-compress-texture[18348:437229] -[MTLToolsIOHandle traceStream]: unrecognized selector sent to instance 0x600000c6d5f0
        2022-06-15 18:00:51.878328-0500 x-mtlio-compress-texture[18348:437229] *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[MTLToolsIOHandle traceStream]: unrecognized selector sent to instance 0x600000c6d5f0'
        *** First throw call stack:
        (
            0   CoreFoundation                      0x00000001a97b5b2c __exceptionPreprocess + 176
            1   libobjc.A.dylib                     0x00000001a938d458 objc_exception_throw + 60
            2   CoreFoundation                      0x00000001a9855bac -[NSObject(NSObject) __retain_OA] + 0
            3   CoreFoundation                      0x00000001a971c470 ___forwarding___ + 1600
            4   CoreFoundation                      0x00000001a971bd70 _CF_forwarding_prep_0 + 96
            5   GPUToolsCapture                     0x0000000100b60638 -[CaptureMTLIOCommandBuffer loadTexture:slice:level:size:sourceBytesPerRow:sourceBytesPerImage:destinationOrigin:sourceHandle:sourceHandleOffset:] + 440
            6   x-mtlio-compress-texture            0x000000010000697c $s24x_mtlio_compress_texture21loadTextureUsingMTLIO5width6height7fileURL17compressionMethodySi_Si10Foundation0K0VSo016MTLIOCompressionM0VSgtKF + 2036
            7   x-mtlio-compress-texture            0x0000000100005bc4 main + 6816
            8   dyld                                0x0000000235a13c10 start + 2368
        )
        libc++abi: terminating with uncaught exception of type NSException
        *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[MTLToolsIOHandle traceStream]: unrecognized selector sent to instance 0x600000c6d5f0'
        terminating with uncaught exception of type NSException
      ```

## Environment

- MacBook Pro 2021 M1 Max
- macOS Version 13.0 Beta 22A5266r
- Xcode Version 14.0 beta 14A5228