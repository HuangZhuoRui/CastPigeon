package com.suseoaa.castpigeon.ui.component.sukisu

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import top.yukonga.miuix.kmp.blur.layerBackdrop
import top.yukonga.miuix.kmp.blur.rememberLayerBackdrop
import top.yukonga.miuix.kmp.theme.MiuixTheme
import com.suseoaa.castpigeon.ui.AppTab

import androidx.compose.ui.layout.onSizeChanged

private const val BOTTOM_BAR_BLUR_ENABLED = false

@Composable
fun LiquidGlassBackdropWrapper(
    isLiquidGlassTabbarEnabled: Boolean,
    liquidGlassTabbarStyle: Int,
    selectedIndex: () -> Int,
    onNavigate: (Int) -> Unit,
    onBottomBarHeightChanged: (Int) -> Unit,
    modifier: Modifier,
    content: @Composable (backdropModifier: Modifier) -> Unit
) {
    if (isLiquidGlassTabbarEnabled && liquidGlassTabbarStyle == 2) {
        val backdrop = rememberLayerBackdrop()
        val density = androidx.compose.ui.platform.LocalDensity.current
        Box(modifier = modifier) {
            content(if (BOTTOM_BAR_BLUR_ENABLED) Modifier.layerBackdrop(backdrop) else Modifier)
            FloatingBottomBar(
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp)
                    .onSizeChanged { 
                        // Include the 12dp bottom padding in the reported height
                        val paddingPx = with(density) { 12.dp.roundToPx() }
                        onBottomBarHeightChanged(it.height + paddingPx)
                    },
                selectedIndex = selectedIndex,
                onSelected = onNavigate,
                backdrop = backdrop,
                tabsCount = AppTab.entries.size,
                isBlurEnabled = BOTTOM_BAR_BLUR_ENABLED
            ) {
                AppTab.entries.forEachIndexed { index, item ->
                    FloatingBottomBarItem(
                        onClick = { onNavigate(index) },
                        modifier = Modifier.defaultMinSize(minWidth = 76.dp)
                    ) {
                        Icon(
                            imageVector = item.icon,
                            contentDescription = item.title,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = item.title,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    } else {
        Box(modifier = modifier) {
            content(Modifier)
        }
    }
}
