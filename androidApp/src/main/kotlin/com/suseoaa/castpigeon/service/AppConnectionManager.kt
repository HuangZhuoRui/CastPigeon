package com.suseoaa.castpigeon.service

import com.suseoaa.castpigeon.shared.BleCentral
import com.suseoaa.castpigeon.shared.BlePeripheral
import com.suseoaa.castpigeon.shared.ConnectionStateMachine
import com.suseoaa.castpigeon.shared.crypto.Crypto

object AppConnectionManager {
    val stateMachine = ConnectionStateMachine()
    val blePeripheral = BlePeripheral()
    val bleCentral = BleCentral()
    val crypto = Crypto().apply { generateKeyPair() }
}
