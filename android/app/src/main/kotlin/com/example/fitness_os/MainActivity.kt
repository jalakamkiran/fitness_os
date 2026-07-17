package com.example.fitness_os

import com.example.fitness_os.huawei.HuaweiBtPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var huaweiPlugin: HuaweiBtPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = HuaweiBtPlugin(this)
        plugin.register(flutterEngine)
        huaweiPlugin = plugin
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        val handled = huaweiPlugin?.onRequestPermissionsResult(requestCode, grantResults) == true
        if (!handled) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        huaweiPlugin?.dispose()
        huaweiPlugin = null
        super.onDestroy()
    }
}
