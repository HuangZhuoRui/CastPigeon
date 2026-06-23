package com.suseoaa.castpigeon.shared.crypto

import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyFactory
import java.security.spec.X509EncodedKeySpec
import java.security.MessageDigest
import javax.crypto.KeyAgreement
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec
import javax.crypto.spec.GCMParameterSpec
import java.security.SecureRandom

//Android端的加密模块实现
actual class Crypto actual constructor() {

    private var keyPair: KeyPair? = null
    private var sharedSecretKey: SecretKeySpec? = null
    
    //AES-GCM的标签长度(位)
    private val gcmTagLength = 128
    //AES-GCM的初始化向量长度(字节)
    private val gcmIvLength = 12

    actual fun generateKeyPair() {
        //使用椭圆曲线算法生成密钥对
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(256)
        keyPair = kpg.generateKeyPair()
    }

    actual fun getPublicKeyBytes(): ByteArray {
        //获取X.509格式的公钥字节
        return keyPair?.public?.encoded ?: throw IllegalStateException("未生成密钥对")
    }

    actual fun computeSharedSecret(peerPublicKey: ByteArray) {
        //从字节数组恢复对方公钥
        val kf = KeyFactory.getInstance("EC")
        val x509Spec = X509EncodedKeySpec(peerPublicKey)
        val peerKey = kf.generatePublic(x509Spec)
        
        //使用ECDH算法计算共享密钥
        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(keyPair?.private ?: throw IllegalStateException("未生成密钥对"))
        ka.doPhase(peerKey, true)
        val sharedSecret = ka.generateSecret()
        
        //使用SHA-256进行密钥派生，取前16字节作为AES-128的密钥
        val md = MessageDigest.getInstance("SHA-256")
        val derivedKey = md.digest(sharedSecret).copyOf(16)
        sharedSecretKey = SecretKeySpec(derivedKey, "AES")
    }

    actual fun encryptAesGcm(plainText: ByteArray): ByteArray {
        val key = sharedSecretKey ?: throw IllegalStateException("共享密钥未初始化")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        
        //生成随机IV
        val iv = ByteArray(gcmIvLength)
        SecureRandom().nextBytes(iv)
        val spec = GCMParameterSpec(gcmTagLength, iv)
        
        cipher.init(Cipher.ENCRYPT_MODE, key, spec)
        val cipherText = cipher.doFinal(plainText)
        
        //将IV附加在密文前面返回
        val result = ByteArray(iv.size + cipherText.size)
        System.arraycopy(iv, 0, result, 0, iv.size)
        System.arraycopy(cipherText, 0, result, iv.size, cipherText.size)
        return result
    }

    actual fun decryptAesGcm(cipherText: ByteArray): ByteArray {
        val key = sharedSecretKey ?: throw IllegalStateException("共享密钥未初始化")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        
        //从密文前部提取IV
        if (cipherText.size < gcmIvLength) throw IllegalArgumentException("密文太短")
        val iv = cipherText.copyOfRange(0, gcmIvLength)
        val spec = GCMParameterSpec(gcmTagLength, iv)
        
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        //解密剩余部分
        return cipher.doFinal(cipherText, gcmIvLength, cipherText.size - gcmIvLength)
    }
}
