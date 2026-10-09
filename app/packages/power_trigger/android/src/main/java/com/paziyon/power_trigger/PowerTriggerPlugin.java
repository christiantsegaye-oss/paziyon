package com.paziyon.power_trigger;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

/**
 * Streams screen on/off changes. SCREEN_ON and SCREEN_OFF can only be received
 * by a receiver registered at runtime, so it lives as long as someone listens
 * (the app's background service).
 */
public class PowerTriggerPlugin implements FlutterPlugin, EventChannel.StreamHandler {
  private EventChannel channel;
  private Context context;
  private BroadcastReceiver receiver;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    channel = new EventChannel(binding.getBinaryMessenger(), "com.paziyon/power_trigger/screen");
    channel.setStreamHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    onCancel(null);
    channel.setStreamHandler(null);
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    onCancel(null);
    receiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context c, Intent intent) {
        events.success(System.currentTimeMillis());
      }
    };
    IntentFilter filter = new IntentFilter();
    filter.addAction(Intent.ACTION_SCREEN_ON);
    filter.addAction(Intent.ACTION_SCREEN_OFF);
    if (Build.VERSION.SDK_INT >= 33) {
      // System broadcasts are still delivered to a non-exported receiver.
      context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
    } else {
      context.registerReceiver(receiver, filter);
    }
  }

  @Override
  public void onCancel(Object arguments) {
    if (receiver != null) {
      try {
        context.unregisterReceiver(receiver);
      } catch (IllegalArgumentException ignored) {
        // already unregistered
      }
      receiver = null;
    }
  }
}
