package com.example.solfeus

import android.accounts.AccountManager
import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
	private val channelName = "solfeus/google_account"
	private val accountRequest = 4301
	private var accountResult: MethodChannel.Result? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"getAccount" -> result.success(getSharedPreferences("solfeus", MODE_PRIVATE).getString("account", null))
				"chooseAccount" -> {
					if (accountResult != null) {
						result.error("busy", "Ya hay un selector de cuentas abierto", null)
					} else {
						accountResult = result
						try {
							val intent = AccountManager.newChooseAccountIntent(
								null, null, arrayOf("com.google"), null, null, null, null
							)
							startActivityForResult(intent, accountRequest)
						} catch (error: Exception) {
							accountResult = null
							result.error("unavailable", "No se pudo abrir el selector de cuentas Google", null)
						}
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	@Deprecated("Activity result API used by Android account chooser")
	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode != accountRequest) return
		val email = if (resultCode == Activity.RESULT_OK) {
			data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
		} else null
		if (!email.isNullOrBlank()) {
			getSharedPreferences("solfeus", MODE_PRIVATE).edit().putString("account", email).apply()
		}
		accountResult?.success(email)
		accountResult = null
	}
}
