package com.suseoaa.castpigeon.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.surfaceColorAtElevation
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import kotlin.math.pow

@Composable
fun LiquidGlassBottomBar(
    tabs: List<AppTab>,
    currentTab: AppTab,
    onTabSelected: (AppTab) -> Unit,
    indicatorProgress: Float,
    onIndicatorDrag: (Float) -> Unit,
    onIndicatorDragEnd: () -> Unit,
    hazeState: HazeState,
    modifier: Modifier = Modifier
) {
    val colorScheme = MaterialTheme.colorScheme
    val selectedTint = colorScheme.onSecondaryContainer
    val unselectedTint = colorScheme.onSurfaceVariant.copy(alpha = 0.9f)
    
    val indicatorColor = colorScheme.secondaryContainer.copy(alpha = 0.95f)
    val hazeSurface = colorScheme.surfaceColorAtElevation(3.dp)
    
    val hazeBackground = Color.White.copy(alpha = 0.35f)
    val hazeTintColor = Color.White.copy(alpha = 0.15f)
    val barOverlay = Color.White.copy(alpha = 0.12f)
    val outlineColor = Color.White.copy(alpha = 0.4f)
    val blurRadius = 32.dp

    val tabInteractionSources = remember { List(tabs.size) { MutableInteractionSource() } }

    Box(
        modifier = modifier
            .padding(16.dp)
            .height(72.dp)
            .clip(RoundedCornerShape(36.dp))
            .hazeEffect(
                state = hazeState,
                style = HazeStyle(
                    backgroundColor = hazeBackground,
                    tint = HazeTint(hazeTintColor),
                    blurRadius = blurRadius,
                    noiseFactor = 0f
                )
            )
            .background(barOverlay)
            .border(
                width = 1.dp,
                color = outlineColor,
                shape = RoundedCornerShape(36.dp)
            )
    ) {
        BoxWithConstraints(
            modifier = Modifier.fillMaxWidth()
        ) {
            val tabCount = tabs.size
            val barHorizontalPadding = 6.dp
            val barVerticalPadding = 4.dp
            val itemSpacing = 2.dp
            val safeProgress = indicatorProgress.coerceIn(0f, (tabCount - 1).toFloat())
            val itemWidth = (maxWidth - barHorizontalPadding * 2 - itemSpacing * (tabCount - 1)) / tabCount
            val density = LocalDensity.current
            val dragStepPx = with(density) { (itemWidth + itemSpacing).toPx() }
            val itemWidthPx = with(density) { itemWidth.toPx() }
            
            val indicatorDraggableState = rememberDraggableState { deltaPx ->
                if (dragStepPx > 0f) {
                    onIndicatorDrag(deltaPx / dragStepPx)
                }
            }

            val pressedStates = tabInteractionSources.map { it.collectIsPressedAsState() }
            val anyTabPressed = pressedStates.any { it.value }
            
            val isExpanded = anyTabPressed || (indicatorProgress % 1f != 0f)

            val targetBubbleHeight = if (isExpanded) 84.dp else 52.dp
            val animatedBubbleHeight by animateDpAsState(
                targetValue = targetBubbleHeight,
                animationSpec = androidx.compose.animation.core.spring(
                    dampingRatio = 0.7f,
                    stiffness = 300f
                )
            )

            val startTab = kotlin.math.floor(safeProgress.toDouble()).toFloat()
            val f = safeProgress - startTab
            val pow = 2.4f
            
            val leftProgress = startTab + f.toDouble().pow(pow.toDouble()).toFloat()
            val rightProgress = startTab + f.toDouble().pow((1f / pow).toDouble()).toFloat()
            
            val leftPx = leftProgress * dragStepPx
            val rightPx = rightProgress * dragStepPx + itemWidthPx
            
            val currentIndicatorWidth = with(density) { (rightPx - leftPx).toDp() }
            val currentIndicatorOffset = with(density) { leftPx.toDp() } + barHorizontalPadding

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = barVerticalPadding)
                    .height(60.dp)
                    .draggable(
                        state = indicatorDraggableState,
                        orientation = Orientation.Horizontal,
                        onDragStopped = { onIndicatorDragEnd() }
                    )
            ) {
                val bubbleOffsetY = (60.dp - animatedBubbleHeight) / 2

                val indicatorModifier = Modifier
                    .hazeEffect(
                        state = hazeState,
                        style = HazeStyle(
                            backgroundColor = indicatorColor.copy(alpha = 0.4f),
                            tint = HazeTint(indicatorColor.copy(alpha = 0.45f)),
                            blurRadius = 64.dp,
                            noiseFactor = 0f
                        )
                    )
                    .background(
                        brush = Brush.linearGradient(
                            colors = listOf(
                                Color.White.copy(alpha = 0.25f),
                                indicatorColor.copy(alpha = 0.5f),
                                Color.White.copy(alpha = 0.1f)
                            ),
                            start = androidx.compose.ui.geometry.Offset(0f, 0f),
                            end = androidx.compose.ui.geometry.Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY)
                        )
                    )

                val indicatorBorder = Modifier.border(
                    width = 1.dp,
                    brush = Brush.verticalGradient(
                        colors = listOf(Color.White.copy(alpha = 0.7f), Color.White.copy(alpha = 0.6f))
                    ),
                    shape = RoundedCornerShape(percent = 50)
                )

                val bubbleShape = RoundedCornerShape(percent = 50)

                Box(
                    modifier = Modifier
                        .offset(x = currentIndicatorOffset, y = bubbleOffsetY)
                        .width(currentIndicatorWidth)
                        .height(animatedBubbleHeight)
                        .clip(bubbleShape)
                        .then(indicatorModifier)
                        .then(indicatorBorder)
                )

                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = barHorizontalPadding)
                        .liquidGlassDistortion(
                            isExpanded = isExpanded,
                            centerX = with(density) { (currentIndicatorOffset + currentIndicatorWidth / 2f).toPx() },
                            centerY = with(density) { (bubbleOffsetY + animatedBubbleHeight / 2f).toPx() },
                            width = with(density) { currentIndicatorWidth.toPx() },
                            height = with(density) { animatedBubbleHeight.toPx() },
                            fallbackScaleX = 1f + ((rightPx - leftPx) / itemWidthPx - 1f) * 0.15f + 0.1f,
                            fallbackScaleY = 1.15f,
                            fallbackPivotX = (with(density) { barHorizontalPadding.toPx() } + leftPx + (rightPx - leftPx) / 2f) / with(density) { this@BoxWithConstraints.maxWidth.toPx() },
                            fallbackPivotY = 0.5f
                        ),
                    horizontalArrangement = Arrangement.spacedBy(itemSpacing),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    tabs.forEachIndexed { index, tab ->
                        val isSelected = tabs.indexOf(currentTab) == index
                        val iconTint = if (isSelected) selectedTint else unselectedTint
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .clip(RoundedCornerShape(percent = 50))
                                .clickable(
                                    interactionSource = tabInteractionSources[index],
                                    indication = null,
                                    onClick = { onTabSelected(tab) }
                                )
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(vertical = 8.dp, horizontal = 4.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center
                            ) {
                                Icon(
                                    imageVector = tab.icon,
                                    contentDescription = tab.title,
                                    tint = iconTint
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = tab.title,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = iconTint
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
