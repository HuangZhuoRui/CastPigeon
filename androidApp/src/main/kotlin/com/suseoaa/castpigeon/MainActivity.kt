package com.suseoaa.castpigeon

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import com.suseoaa.castpigeon.ui.MainScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        
        setContent {
            val isDark = androidx.compose.foundation.isSystemInDarkTheme()
            val colorScheme = if (isDark) {
                androidx.compose.material3.darkColorScheme()
            } else {
                androidx.compose.material3.lightColorScheme()
            }
            
            androidx.compose.material3.MaterialTheme(colorScheme = colorScheme) {
                androidx.compose.foundation.layout.Box(
                    modifier = androidx.compose.ui.Modifier.fillMaxSize().background(colorScheme.background)
                ) {
                    MainScreen()
                }
            }
        }
    }
}
