#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Native port of the TruyenDrive XOR image decryption pipeline.
///
/// The algorithm matches `src/lib/imageCrypto.ts` exactly:
///   1. cyrb128 hashes the password string into a uint32 seed.
///   2. mulberry32 PRNG generates a deterministic byte sequence from the seed.
///   3. Each pixel's R, G, B channels are XORed with successive PRNG bytes.
///      The alpha channel is left untouched.
@interface TDImageDecryptor : NSObject

/// Download an image, decrypt its pixel data, and return the result as a UIImage.
///
/// The completion block is always called on the main queue.
/// @param url        Remote URL of the encrypted image.
/// @param password   Encryption password used to derive the PRNG seed.
/// @param completion Called with the decrypted image on success, or an error.
+ (void)decryptImageAtURL:(NSURL *)url
                 password:(NSString *)password
               completion:(void (^)(UIImage *_Nullable image, NSError *_Nullable error))completion;

/// Decrypt raw RGBA pixel data in place.
///
/// Iterates every 4-byte pixel group, XORing the R, G, B channels with
/// floor(rand() * 256) from the mulberry32 PRNG seeded by cyrb128(password).
/// The alpha byte at offset i+3 is skipped.
///
/// @param data     Pointer to mutable RGBA pixel buffer.
/// @param length   Total byte count of the buffer (must be a multiple of 4).
/// @param password Encryption password.
+ (void)decryptPixelData:(unsigned char *)data
                  length:(NSUInteger)length
                password:(NSString *)password;

/// Decrypt image from already-downloaded data.
+ (void)decryptImageData:(NSData *)imageData
                password:(NSString *)password
              completion:(void (^)(UIImage *_Nullable image, NSError *_Nullable error))completion;

/// Encrypt a UIImage by XOR-ing its RGB pixel data using cyrb128 + mulberry32.
///
/// Since XOR is its own inverse, this uses the same pixel transformation as
/// decryption. The result is returned as PNG data suitable for saving or uploading.
///
/// @param image    The source image to encrypt.
/// @param password Encryption password used to derive the PRNG seed.
/// @return PNG data of the encrypted image, or nil on failure.
+ (nullable NSData *)encryptImage:(UIImage *)image password:(NSString *)password;

/// cyrb128 hash — converts a string into a single uint32 seed.
///
/// This is a non-cryptographic hash used only to derive a PRNG seed.
/// The implementation matches the TypeScript `cyrb128()` function exactly.
+ (uint32_t)cyrb128:(NSString *)str;

@end

NS_ASSUME_NONNULL_END
