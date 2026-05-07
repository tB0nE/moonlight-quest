package com.godot.game;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.util.Log;

import org.tensorflow.lite.Interpreter;

import java.io.FileInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

public class DepthEstimator {
    private static final String TAG = "DepthEstimator";
    private static final int OUTPUT_SIZE = 256;
    private static final int DA_INPUT_SIZE = 252;
    private static final String MODEL_MIDAS = "midas-midas-v2-w8a8.tflite";
    private static final String MODEL_DEPTH_ANYTHING = "depth-anything-v2-small.tflite";

    private Interpreter tfliteMidas;
    private Interpreter tfliteDepthAnything;
    private Interpreter activeInterpreter;
    private ByteBuffer inputBufferMidas;
    private ByteBuffer inputBufferDA;
    private ByteBuffer outputBufferMidas;
    private ByteBuffer outputBufferDA;
    private volatile boolean initialized = false;
    private volatile int activeModelIndex = 0;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean isInferencing = new AtomicBoolean(false);
    private final AtomicReference<byte[]> latestDepthMap = new AtomicReference<>();

    private byte[] previousDepthBytes = null;
    private byte[] smoothedDepthBytes = null;

    private Context appContext;

    public synchronized boolean initialize(Context context) {
        if (initialized) return true;
        appContext = context.getApplicationContext();

        try {
            inputBufferMidas = ByteBuffer.allocateDirect(1 * OUTPUT_SIZE * OUTPUT_SIZE * 3 * 4)
                    .order(ByteOrder.nativeOrder());
            outputBufferMidas = ByteBuffer.allocateDirect(1 * OUTPUT_SIZE * OUTPUT_SIZE * 1 * 4)
                    .order(ByteOrder.nativeOrder());

            inputBufferDA = ByteBuffer.allocateDirect(1 * DA_INPUT_SIZE * DA_INPUT_SIZE * 3 * 4)
                    .order(ByteOrder.nativeOrder());
            outputBufferDA = ByteBuffer.allocateDirect(1 * DA_INPUT_SIZE * DA_INPUT_SIZE * 1 * 4)
                    .order(ByteOrder.nativeOrder());

            tfliteMidas = loadInterpreter(MODEL_MIDAS);

            try {
                tfliteDepthAnything = loadInterpreter(MODEL_DEPTH_ANYTHING);
                Log.i(TAG, "Depth Anything V2 model loaded");
            } catch (Exception e) {
                Log.w(TAG, "Depth Anything V2 model not available", e);
                tfliteDepthAnything = null;
            }

            activeInterpreter = tfliteMidas;
            activeModelIndex = 0;
            initialized = true;
            Log.i(TAG, "Initialized successfully (MiDaS=" + (tfliteMidas != null) + ", DA=" + (tfliteDepthAnything != null) + ")");
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize", e);
            return false;
        }
    }

    private Interpreter loadInterpreter(String modelFile) throws IOException {
        MappedByteBuffer buffer = loadModelFile(modelFile);
        try {
            Interpreter.Options opts = new Interpreter.Options();
            opts.setUseNNAPI(true);
            opts.setNumThreads(4);
            Interpreter interp = new Interpreter(buffer, opts);
            Log.i(TAG, modelFile + " loaded with NNAPI");
            return interp;
        } catch (Exception e) {
            Log.w(TAG, "NNAPI failed for " + modelFile + ", falling back to CPU", e);
            Interpreter.Options opts = new Interpreter.Options();
            opts.setNumThreads(4);
            return new Interpreter(buffer, opts);
        }
    }

    public void setActiveModel(int modelIndex) {
        if (!initialized) return;
        Interpreter target;
        if (modelIndex == 1 && tfliteDepthAnything != null) {
            target = tfliteDepthAnything;
        } else {
            target = tfliteMidas;
            modelIndex = 0;
        }
        if (activeModelIndex != modelIndex) {
            while (isInferencing.get()) {
                Thread.yield();
            }
            previousDepthBytes = null;
            smoothedDepthBytes = null;
            activeInterpreter = target;
            activeModelIndex = modelIndex;
            Log.i(TAG, "Switched to model " + (modelIndex == 0 ? "MiDaS" : "Depth Anything V2"));
        }
    }

    public int getActiveModel() {
        return activeModelIndex;
    }

    public boolean hasModelV2() {
        return tfliteDepthAnything != null;
    }

    public void submitFrame(byte[] rgbaPixels, int width, int height) {
        if (!initialized || activeInterpreter == null) return;
        if (rgbaPixels == null || rgbaPixels.length < width * height * 4) return;
        if (!isInferencing.compareAndSet(false, true)) return;

        final byte[] frameCopy = rgbaPixels.clone();
        final int modelIdx = activeModelIndex;
        executor.submit(() -> {
            long startTime = System.nanoTime();
            try {
                byte[] result;
                if (modelIdx == 1) {
                    result = runInferenceDA(frameCopy, width, height);
                } else {
                    result = runInferenceMidas(frameCopy, width, height);
                }
                if (result != null) {
                    latestDepthMap.set(result);
                }
            } catch (Exception e) {
                Log.e(TAG, "Async inference failed", e);
            } finally {
                isInferencing.set(false);
                long duration = (System.nanoTime() - startTime) / 1_000_000;
                Log.d(TAG, "Inference: " + duration + "ms (" + (modelIdx == 1 ? "DA" : "MiDaS") + ")");
            }
        });
    }

    public byte[] getLatestDepth() {
        return latestDepthMap.getAndSet(null);
    }

    private byte[] runInferenceMidas(byte[] rgbaPixels, int width, int height) {
        inputBufferMidas.rewind();
        outputBufferMidas.rewind();

        int srcRowBytes = width * 4;
        float scaleX = (float) width / OUTPUT_SIZE;
        float scaleY = (float) height / OUTPUT_SIZE;

        for (int y = 0; y < OUTPUT_SIZE; y++) {
            int srcY = Math.min((int) (y * scaleY), height - 1);
            int srcRowOff = srcY * srcRowBytes;
            for (int x = 0; x < OUTPUT_SIZE; x++) {
                int srcX = Math.min((int) (x * scaleX), width - 1);
                int srcIdx = srcRowOff + srcX * 4;
                inputBufferMidas.putFloat((rgbaPixels[srcIdx] & 0xFF) / 255.0f);
                inputBufferMidas.putFloat((rgbaPixels[srcIdx + 1] & 0xFF) / 255.0f);
                inputBufferMidas.putFloat((rgbaPixels[srcIdx + 2] & 0xFF) / 255.0f);
            }
        }
        inputBufferMidas.rewind();

        tfliteMidas.run(inputBufferMidas, outputBufferMidas);
        outputBufferMidas.rewind();

        return postProcess(outputBufferMidas, OUTPUT_SIZE);
    }

    private byte[] runInferenceDA(byte[] rgbaPixels, int width, int height) {
        inputBufferDA.rewind();
        outputBufferDA.rewind();

        int srcRowBytes = width * 4;
        float scaleX = (float) width / DA_INPUT_SIZE;
        float scaleY = (float) height / DA_INPUT_SIZE;

        for (int y = 0; y < DA_INPUT_SIZE; y++) {
            int srcY = Math.min((int) (y * scaleY), height - 1);
            int srcRowOff = srcY * srcRowBytes;
            for (int x = 0; x < DA_INPUT_SIZE; x++) {
                int srcX = Math.min((int) (x * scaleX), width - 1);
                int srcIdx = srcRowOff + srcX * 4;
                inputBufferDA.putFloat((rgbaPixels[srcIdx] & 0xFF) / 255.0f);
                inputBufferDA.putFloat((rgbaPixels[srcIdx + 1] & 0xFF) / 255.0f);
                inputBufferDA.putFloat((rgbaPixels[srcIdx + 2] & 0xFF) / 255.0f);
            }
        }
        inputBufferDA.rewind();

        tfliteDepthAnything.run(inputBufferDA, outputBufferDA);
        outputBufferDA.rewind();

        byte[] rawDepth = postProcess(outputBufferDA, DA_INPUT_SIZE);
        return bilinearResize(rawDepth, DA_INPUT_SIZE, OUTPUT_SIZE);
    }

    private byte[] postProcess(ByteBuffer output, int size) {
        output.rewind();
        FloatBuffer floatOut = output.asFloatBuffer();
        float min = Float.MAX_VALUE, max = Float.MIN_VALUE;
        for (int i = 0; i < floatOut.capacity(); i++) {
            float v = floatOut.get(i);
            if (v < min) min = v;
            if (v > max) max = v;
        }

        float range = max - min;
        byte[] depthBytes = new byte[size * size];
        if (range > 0) {
            floatOut.rewind();
            for (int i = 0; i < floatOut.capacity(); i++) {
                float normalized = (floatOut.get() - min) / range;
                float contrast = (float) Math.pow(normalized, 0.5);
                depthBytes[i] = (byte) (contrast * 255.0f);
            }
        }

        depthBytes = boxBlur(depthBytes, size);
        return temporalSmooth(depthBytes);
    }

    private byte[] bilinearResize(byte[] src, int srcSize, int dstSize) {
        byte[] dst = new byte[dstSize * dstSize];
        float scale = (float) srcSize / dstSize;
        for (int y = 0; y < dstSize; y++) {
            float srcYf = y * scale;
            int y0 = Math.min((int) srcYf, srcSize - 1);
            int y1 = Math.min(y0 + 1, srcSize - 1);
            float fy = srcYf - y0;
            for (int x = 0; x < dstSize; x++) {
                float srcXf = x * scale;
                int x0 = Math.min((int) srcXf, srcSize - 1);
                int x1 = Math.min(x0 + 1, srcSize - 1);
                float fx = srcXf - x0;
                float v00 = (src[y0 * srcSize + x0] & 0xFF);
                float v10 = (src[y0 * srcSize + x1] & 0xFF);
                float v01 = (src[y1 * srcSize + x0] & 0xFF);
                float v11 = (src[y1 * srcSize + x1] & 0xFF);
                float val = v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy) + v01 * (1 - fx) * fy + v11 * fx * fy;
                dst[y * dstSize + x] = (byte) (val + 0.5f);
            }
        }
        return dst;
    }

    private byte[] boxBlur(byte[] depth, int size) {
        byte[] result = new byte[depth.length];
        int r = 2;
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                int sum = 0;
                int count = 0;
                for (int dy = -r; dy <= r; dy++) {
                    for (int dx = -r; dx <= r; dx++) {
                        int nx = x + dx;
                        int ny = y + dy;
                        if (nx >= 0 && nx < size && ny >= 0 && ny < size) {
                            sum += depth[ny * size + nx] & 0xFF;
                            count++;
                        }
                    }
                }
                result[y * size + x] = (byte) (sum / count);
            }
        }
        return result;
    }

    private byte[] temporalSmooth(byte[] newDepth) {
        if (previousDepthBytes == null) {
            previousDepthBytes = newDepth.clone();
            smoothedDepthBytes = newDepth.clone();
            return newDepth;
        }

        float smoothing = 0.15f;

        long totalDiff = 0;
        for (int i = 0; i < newDepth.length; i++) {
            totalDiff += Math.abs((newDepth[i] & 0xFF) - (previousDepthBytes[i] & 0xFF));
        }
        double avgDiff = (double) totalDiff / newDepth.length;

        if (avgDiff > 80.0) {
            smoothing = 0.5f;
        } else if (avgDiff > 50.0) {
            smoothing = 0.3f;
        }

        byte[] result = new byte[newDepth.length];
        for (int i = 0; i < newDepth.length; i++) {
            float prev = smoothedDepthBytes[i] & 0xFF;
            float curr = newDepth[i] & 0xFF;
            result[i] = (byte) (prev * (1.0f - smoothing) + curr * smoothing);
        }

        previousDepthBytes = newDepth.clone();
        smoothedDepthBytes = result.clone();
        return result;
    }

    public synchronized void close() {
        if (tfliteMidas != null) {
            tfliteMidas.close();
            tfliteMidas = null;
        }
        if (tfliteDepthAnything != null) {
            tfliteDepthAnything.close();
            tfliteDepthAnything = null;
        }
        activeInterpreter = null;
        initialized = false;
        executor.shutdownNow();
    }

    public int getModelSize() {
        return OUTPUT_SIZE;
    }

    public boolean isInitialized() {
        return initialized;
    }

    private MappedByteBuffer loadModelFile(String filename) throws IOException {
        AssetFileDescriptor fd = appContext.getAssets().openFd(filename);
        FileInputStream is = new FileInputStream(fd.getFileDescriptor());
        FileChannel ch = is.getChannel();
        long offset = fd.getStartOffset();
        long length = fd.getDeclaredLength();
        return ch.map(FileChannel.MapMode.READ_ONLY, offset, length);
    }
}
