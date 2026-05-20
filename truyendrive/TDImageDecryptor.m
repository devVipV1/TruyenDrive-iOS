#import "TDImageDecryptor.h"
#import <ImageIO/ImageIO.h>
#include <math.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <os/log.h>

static NSString *const TDImageDecryptorDomain = @"com.truyendrive.imagedecryptor";

#pragma mark - cyrb128 hash

/// Matches the TypeScript `cyrb128(str)` function.
/// Math.imul(a, b) is 32-bit integer multiply — in C, multiplying uint32_t
/// values produces the same low-32-bit result because unsigned overflow wraps.
/// The JS `>>> 0` (unsigned right shift by 0) converts to uint32, which is
/// the natural state of uint32_t in C.
static uint32_t td_cyrb128(NSString *str) {
    uint32_t h1 = 1779033703;
    uint32_t h2 = 3144134277;
    uint32_t h3 = 1013904242;
    uint32_t h4 = 2773480762;

    NSUInteger len = str.length;
    for (NSUInteger i = 0; i < len; i++) {
        uint32_t k = (uint32_t)[str characterAtIndex:i];
        h1 = h2 ^ (uint32_t)((uint64_t)(h1 ^ k) * (uint64_t)597399067);
        h2 = h3 ^ (uint32_t)((uint64_t)(h2 ^ k) * (uint64_t)2869860233);
        h3 = h4 ^ (uint32_t)((uint64_t)(h3 ^ k) * (uint64_t)951274213);
        h4 = h1 ^ (uint32_t)((uint64_t)(h4 ^ k) * (uint64_t)2716044179);
    }

    h1 = (uint32_t)((uint64_t)(h3 ^ (h1 >> 18)) * (uint64_t)597399067);
    h2 = (uint32_t)((uint64_t)(h4 ^ (h2 >> 22)) * (uint64_t)2869860233);
    h3 = (uint32_t)((uint64_t)(h1 ^ (h3 >> 17)) * (uint64_t)951274213);
    h4 = (uint32_t)((uint64_t)(h2 ^ (h4 >> 19)) * (uint64_t)2716044179);

    return h1 ^ h2 ^ h3 ^ h4;
}

#pragma mark - mulberry32 PRNG

/// State for the mulberry32 PRNG. The single uint32_t `a` value is mutated
/// on each call to `td_mulberry32_next`.
typedef struct {
    double a; // MUST be double to match JS Number (float64) behavior
} TDMulberry32;

static TDMulberry32 td_mulberry32_init(uint32_t seed) {
    return (TDMulberry32){ .a = (double)seed };
}

// JS mulberry32: `a` is a float64 Number that grows beyond 2^32.
// Bitwise ops (`^`, `>>>`, `|`) convert to int32/uint32 via ToInt32/ToUint32.
// Math.imul treats inputs as int32.
// We replicate this by keeping `a` as double and converting to uint32 for ops.
static uint8_t td_mulberry32_next_byte(TDMulberry32 *state) {
    state->a += 0x6D2B79F5; // float64 addition, NO 32-bit wrap

    // JS ToUint32: mod 2^32 then interpret as unsigned
    uint32_t a = (uint32_t)fmod(state->a, 4294967296.0);

    uint32_t t = (uint32_t)((uint64_t)(a ^ (a >> 15)) * (uint64_t)(a | 1));
    t ^= t + (uint32_t)((uint64_t)(t ^ (t >> 7)) * (uint64_t)(t | 61));
    uint32_t result = t ^ (t >> 14);

    double f = (double)result / 4294967296.0;
    return (uint8_t)(f * 256.0);
}

#pragma mark - Pixel decryption

static void td_decrypt_pixel_data(unsigned char *data, NSUInteger length, NSString *password) {
    uint32_t seed = td_cyrb128(password);
    TDMulberry32 prng = td_mulberry32_init(seed);

    for (NSUInteger i = 0; i < length; i += 4) {
        data[i]     ^= td_mulberry32_next_byte(&prng);
        data[i + 1] ^= td_mulberry32_next_byte(&prng);
        data[i + 2] ^= td_mulberry32_next_byte(&prng);
    }
}

static void td_decrypt_pixel_data_with_stride(unsigned char *data, size_t width, size_t height, size_t bytesPerRow, NSString *password) {
    uint32_t seed = td_cyrb128(password);
    TDMulberry32 prng = td_mulberry32_init(seed);
    size_t pixelBytes = width * 4;

    for (size_t row = 0; row < height; row++) {
        unsigned char *rowPtr = data + (row * bytesPerRow);
        for (size_t x = 0; x < pixelBytes; x += 4) {
            rowPtr[x]     ^= td_mulberry32_next_byte(&prng);
            rowPtr[x + 1] ^= td_mulberry32_next_byte(&prng);
            rowPtr[x + 2] ^= td_mulberry32_next_byte(&prng);
        }
    }
}

#pragma mark - TDImageDecryptor

@implementation TDImageDecryptor

+ (uint32_t)cyrb128:(NSString *)str {
    return td_cyrb128(str);
}

+ (void)decryptPixelData:(unsigned char *)data
                  length:(NSUInteger)length
                password:(NSString *)password {
    td_decrypt_pixel_data(data, length, password);
}

+ (void)decryptImageAtURL:(NSURL *)url
                 password:(NSString *)password
               completion:(void (^)(UIImage *_Nullable, NSError *_Nullable))completion {
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithURL:url
      completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }

        if (!data || data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *noDataError = [NSError errorWithDomain:TDImageDecryptorDomain
                                                           code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"No data received from image URL."}];
                completion(nil, noDataError);
            });
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if ([httpResponse isKindOfClass:[NSHTTPURLResponse class]] && httpResponse.statusCode != 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *msg = [NSString stringWithFormat:@"Image download failed with HTTP %ld.", (long)httpResponse.statusCode];
                NSError *httpError = [NSError errorWithDomain:TDImageDecryptorDomain
                                                         code:2
                                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
                completion(nil, httpError);
            });
            return;
        }

        // Perform decryption on a background queue to avoid blocking.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *result = [self decryptImageData:data password:password];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result) {
                    completion(result, nil);
                } else {
                    NSError *decryptError = [NSError errorWithDomain:TDImageDecryptorDomain
                                                                code:3
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode or decrypt image data."}];
                    completion(nil, decryptError);
                }
            });
        });
    }];

    [task resume];
}

+ (void)decryptImageData:(NSData *)imageData
                password:(NSString *)password
              completion:(void (^)(UIImage *_Nullable, NSError *_Nullable))completion {
    if (!imageData || imageData.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:TDImageDecryptorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"No image data."}]);
        });
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *result = [self decryptImageData:imageData password:password];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result) {
                completion(result, nil);
            } else {
                completion(nil, [NSError errorWithDomain:TDImageDecryptorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decrypt image."}]);
            }
        });
    });
}

+ (nullable NSData *)encryptImage:(UIImage *)image password:(NSString *)password {
    if (!image || password.length == 0) return nil;

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return nil;

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) return nil;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaNoneSkipLast;

    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, bitmapInfo);
    if (!ctx) {
        bitmapInfo = kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
        ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, bitmapInfo);
    }
    if (!ctx) {
        CGColorSpaceRelease(colorSpace);
        return nil;
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);

    size_t actualBPR = CGBitmapContextGetBytesPerRow(ctx);
    unsigned char *pixels = (unsigned char *)CGBitmapContextGetData(ctx);
    if (!pixels) {
        CGContextRelease(ctx);
        CGColorSpaceRelease(colorSpace);
        return nil;
    }

    // XOR is symmetric — encrypting uses the same function as decrypting
    td_decrypt_pixel_data_with_stride(pixels, width, height, actualBPR, password);

    // Create a new CGImage from the encrypted pixels
    CGImageRef encryptedCGImage = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    if (!encryptedCGImage) return nil;

    // Encode as PNG
    NSMutableData *pngData = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)pngData, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    if (!dest) {
        CGImageRelease(encryptedCGImage);
        return nil;
    }

    CGImageDestinationAddImage(dest, encryptedCGImage, NULL);
    BOOL success = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    CGImageRelease(encryptedCGImage);

    return success ? [pngData copy] : nil;
}

#pragma mark - Private

/// Decode image data into an RGBA pixel buffer, decrypt in place, and
/// produce a new UIImage from the result.
+ (nullable UIImage *)decryptImageData:(NSData *)data password:(NSString *)password {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!cgImage) return nil;

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    // Use sRGB to match web canvas getImageData() which returns sRGB values.
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaNoneSkipLast;

    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, bitmapInfo);
    if (!ctx) {
        bitmapInfo = kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
        ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, bitmapInfo);
    }
    CGColorSpaceRelease(colorSpace);

    if (!ctx) {
        CGImageRelease(cgImage);
        return nil;
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);
    CGImageRelease(cgImage);

    size_t actualBPR = CGBitmapContextGetBytesPerRow(ctx);
    unsigned char *pixels = (unsigned char *)CGBitmapContextGetData(ctx);

    os_log_error(OS_LOG_DEFAULT, "[TDDecrypt] %zux%zu bpr=%zu pad=%zu",
            width, height, actualBPR, actualBPR-width*4);

    if (!pixels) {
        CGContextRelease(ctx);
        return nil;
    }

    td_decrypt_pixel_data_with_stride(pixels, width, height, actualBPR, password);

    CGImageRef decryptedCGImage = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);

    if (!decryptedCGImage) return nil;

    // Debug: save first 3 decrypted images to tmp
    static int debugCount = 0;
    if (debugCount < 3) {
        NSString *path = [NSString stringWithFormat:@"/tmp/app_decrypt_%d_%zux%zu.png", debugCount, width, height];
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)fileURL, (__bridge CFStringRef)@"public.png", 1, NULL);
        if (dest) {
            CGImageDestinationAddImage(dest, decryptedCGImage, NULL);
            CGImageDestinationFinalize(dest);
            CFRelease(dest);
            os_log_error(OS_LOG_DEFAULT, "[TDDebug] Saved %{public}@", path);
        }
        debugCount++;
    }

    UIImage *result = [UIImage imageWithCGImage:decryptedCGImage];
    CGImageRelease(decryptedCGImage);
    return result;
}

@end
