package com.rqkitchen.rqnative;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Base64;
import android.view.WindowManager;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.sunmi.peripheral.printer.InnerPrinterCallback;
import com.sunmi.peripheral.printer.InnerPrinterManager;
import com.sunmi.peripheral.printer.InnerResultCallback;
import com.sunmi.peripheral.printer.SunmiPrinterService;

/**
 * RQ Kitchen native helpers on Android (branch screen device):
 * keep the screen on, and print receipts on a Sunmi built-in printer.
 * Receipts arrive as a PNG drawn by the page, so Arabic prints correctly.
 */
@CapacitorPlugin(name = "RQNative")
public class RQNativePlugin extends Plugin {
    private SunmiPrinterService printer;
    private boolean binding = false;

    @Override
    public void load() {
        getActivity().runOnUiThread(() -> {
            try { getBridge().getWebView().getSettings().setMediaPlaybackRequiresUserGesture(false); } catch (Exception ignored) {}
        });
        bindPrinter();
    }

    private void bindPrinter() {
        if (printer != null || binding) return;
        binding = true;
        try {
            InnerPrinterManager.getInstance().bindService(getContext(), new InnerPrinterCallback() {
                @Override protected void onConnected(SunmiPrinterService service) { printer = service; binding = false; }
                @Override protected void onDisconnected() { printer = null; binding = false; }
            });
        } catch (Exception e) { binding = false; }
    }

    @PluginMethod
    public void keepAwake(PluginCall call) {
        boolean on = call.getBoolean("on", true);
        getActivity().runOnUiThread(() -> {
            if (on) getActivity().getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            else getActivity().getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        });
        call.resolve();
    }

    @PluginMethod
    public void printerStatus(PluginCall call) {
        bindPrinter();
        JSObject r = new JSObject();
        if (printer == null) { r.put("ok", false); r.put("reason", "no_printer"); call.resolve(r); return; }
        try {
            int state = printer.updatePrinterState();
            int width = 384;
            try { int paper = printer.getPrinterPaper(); if (paper == 2) width = 576; } catch (Exception ignored) {}
            r.put("ok", state == 1 || state == 0);
            r.put("state", state);
            r.put("width", width);
        } catch (Exception e) { r.put("ok", false); r.put("reason", String.valueOf(e.getMessage())); }
        call.resolve(r);
    }

    @PluginMethod
    public void printBitmap(PluginCall call) {
        String data = call.getString("data");
        if (data == null) { call.reject("no data"); return; }
        if (printer == null) { bindPrinter(); call.reject("no_printer"); return; }
        try {
            byte[] bytes = Base64.decode(data, Base64.DEFAULT);
            Bitmap bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
            InnerResultCallback cb = new InnerResultCallback() {
                @Override public void onRunResult(boolean isSuccess) {}
                @Override public void onReturnString(String result) {}
                @Override public void onRaiseException(int code, String msg) {}
                @Override public void onPrintResult(int code, String msg) {}
            };
            printer.printBitmap(bmp, cb);
            printer.lineWrap(4, cb);
            try { printer.cutPaper(cb); } catch (Exception ignored) {}
            call.resolve();
        } catch (Exception e) { call.reject(String.valueOf(e.getMessage())); }
    }

    // iOS-only features: not used on the branch device
    @PluginMethod public void startTracking(PluginCall call) { call.resolve(); }
    @PluginMethod public void stopTracking(PluginCall call) { call.resolve(); }
    @PluginMethod public void status(PluginCall call) { JSObject r = new JSObject(); r.put("tracking", false); call.resolve(r); }
}
