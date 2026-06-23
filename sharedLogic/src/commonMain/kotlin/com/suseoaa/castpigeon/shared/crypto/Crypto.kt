package com.suseoaa.castpigeon.shared.crypto

//加密模块接口定义
expect class Crypto() {
    //生成密钥对
    fun generateKeyPair()
    //获取公钥字节数组
    fun getPublicKeyBytes(): ByteArray
    //根据对方公钥计算共享密钥
    fun computeSharedSecret(peerPublicKey: ByteArray)
    //使用AES-GCM加密数据
    fun encryptAesGcm(plainText: ByteArray): ByteArray
    //使用AES-GCM解密数据
    fun decryptAesGcm(cipherText: ByteArray): ByteArray
}
