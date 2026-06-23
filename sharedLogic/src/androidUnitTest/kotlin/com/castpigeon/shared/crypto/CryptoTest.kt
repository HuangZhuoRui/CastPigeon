package com.castpigeon.shared.crypto

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

//测试加解密和密钥交换逻辑
class CryptoTest {

    @Test
    fun testKeyExchangeAndEncryption() {
        val alice = Crypto()
        alice.generateKeyPair()
        
        val bob = Crypto()
        bob.generateKeyPair()
        
        //交换公钥并计算共享密钥
        alice.computeSharedSecret(bob.getPublicKeyBytes())
        bob.computeSharedSecret(alice.getPublicKeyBytes())
        
        //测试加密解密
        val message = "这是一条测试消息".encodeToByteArray()
        val cipherText = alice.encryptAesGcm(message)
        
        //密文不等于明文
        assertNotEquals(message.toList(), cipherText.toList())
        
        val decryptedText = bob.decryptAesGcm(cipherText)
        
        //解密后等于原明文
        assertArrayEquals(message, decryptedText)
    }
}
