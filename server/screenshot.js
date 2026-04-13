/// <reference types="@citizenfx/server" />

const imagejs = require('image-js');
const fs = require('fs');

const resName = GetCurrentResourceName();
const resourcePath = GetResourcePath(resName);
const tempPath = `${resourcePath}/data/_screenshot_temp`;

try {
    if (!fs.existsSync(tempPath)) {
        fs.mkdirSync(tempPath, { recursive: true });
    }
} catch (e) {
    console.log(`[retry_greenscreener] Warning: Could not create temp dir: ${e.message}`);
}

// Screenshot capture -> chroma key + crop -> pass base64 to Lua for Fivemanage upload
onNet('retry_greenscreener:captureScreenshot', async (itemName) => {
    const src = global.source;

    // Admin permission check via Lua callback
    const isAdmin = await new Promise((resolve) => {
        emit('retry_greenscreener:internal:checkAdmin', src, (result) => {
            resolve(result);
        });
    });

    if (!isAdmin) {
        console.log(`[retry_greenscreener] Non-admin player ${src} tried to capture screenshot`);
        emitNet('retry_greenscreener:screenshotDone', src, false, null);
        return;
    }

    if (!itemName || itemName === '') {
        emitNet('retry_greenscreener:screenshotDone', src, false, null);
        return;
    }

    const filename = itemName.toLowerCase().replace(/[^a-z0-9_\-]/g, '_');
    const fullPath = `${tempPath}/${filename}_raw.png`;

    console.log(`[retry_greenscreener] Capturing screenshot for: ${filename}`);

    try {
        exports['screenshot-basic'].requestClientScreenshot(
            src,
            {
                fileName: fullPath,
                encoding: 'png',
                quality: 1.0,
            },
            async (err, savedFileName) => {
                if (err) {
                    console.log(`[retry_greenscreener] Screenshot error: ${err}`);
                    emitNet('retry_greenscreener:screenshotDone', src, false, null);
                    return;
                }

                try {
                    let image = await imagejs.Image.load(savedFileName);

                    // Chroma key: remove green pixels
                    for (let x = 0; x < image.width; x++) {
                        for (let y = 0; y < image.height; y++) {
                            const px = image.getPixelXY(x, y);
                            if (px[1] > px[0] + px[2]) {
                                image.setPixelXY(x, y, [255, 255, 255, 0]);
                            }
                        }
                    }

                    // Clean semi-transparent edge artifacts (anti-aliasing residue)
                    const ALPHA_THRESHOLD = 30;
                    for (let x = 0; x < image.width; x++) {
                        for (let y = 0; y < image.height; y++) {
                            const a = image.getPixelXY(x, y)[3];
                            if (a > 0 && a < ALPHA_THRESHOLD) {
                                image.setPixelXY(x, y, [255, 255, 255, 0]);
                            }
                        }
                    }

                    // Auto-crop to content
                    let minX = image.width, maxX = -1, minY = image.height, maxY = -1;
                    for (let x = 0; x < image.width; x++) {
                        for (let y = 0; y < image.height; y++) {
                            if (image.getPixelXY(x, y)[3] >= ALPHA_THRESHOLD) {
                                minX = Math.min(minX, x); maxX = Math.max(maxX, x);
                                minY = Math.min(minY, y); maxY = Math.max(maxY, y);
                            }
                        }
                    }

                    let finalImage = image;
                    if (maxX >= minX && maxY >= minY) {
                        finalImage = image.crop({
                            x: minX, y: minY,
                            width: maxX - minX + 1,
                            height: maxY - minY + 1,
                        });
                    }

                    // Save processed image, read back as base64
                    const processedPath = `${tempPath}/${filename}.png`;
                    await finalImage.save(processedPath);
                    const pngBuffer = fs.readFileSync(processedPath);
                    const base64 = pngBuffer.toString('base64');
                    try { fs.unlinkSync(processedPath); } catch (_) {}

                    console.log(`[retry_greenscreener] Processed ${filename}: ${finalImage.width}x${finalImage.height}, ${Math.round(base64.length / 1024)}KB base64`);

                    // Pass to Lua for Fivemanage upload
                    emit('retry_greenscreener:internal:uploadImage', {
                        name: filename,
                        base64: base64,
                        src: src,
                    });
                } catch (processErr) {
                    console.log(`[retry_greenscreener] Image processing error: ${processErr.message}`);
                    emitNet('retry_greenscreener:screenshotDone', src, false, filename, null);
                } finally {
                    try { fs.unlinkSync(savedFileName); } catch (_) {}
                }
            }
        );
    } catch (e) {
        console.log(`[retry_greenscreener] Screenshot capture error: ${e.message}`);
        emitNet('retry_greenscreener:screenshotDone', src, false, null);
    }
});
