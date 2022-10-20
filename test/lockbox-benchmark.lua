require("/initenv").init_env()

local pbkdf2 = require("lockbox.kdf.pbkdf2")
local AES128Cipher = require("lockbox.cipher.aes128")
local HMAC = require("lockbox.mac.hmac")
local SHA1 = require("lockbox.digest.sha1")
local SHA2_224 = require("lockbox.digest.sha2_224")
local SHA2_256 = require("lockbox.digest.sha2_256")
local Stream = require("lockbox.util.stream")
local Array = require("lockbox.util.array")

local CBCMode = require("lockbox.cipher.mode.cbc")
local CFBMode = require("lockbox.cipher.mode.cfb")
local OFBMode = require("lockbox.cipher.mode.ofb")
local CTRMode = require("lockbox.cipher.mode.ctr")

local ZeroPadding = require("lockbox.padding.zero")

local comms = require("scada-common.comms")
local util = require("scada-common.util")

local start = util.time()

local keyd = pbkdf2()

keyd.setPassword("mypassword")
keyd.setSalt("no_salt_thanks")
keyd.setIterations(16)
keyd.setBlockLen(4)
keyd.setDKeyLen(16)
keyd.setPRF(HMAC().setBlockSize(64).setDigest(SHA2_256))
keyd.finish()

util.println("pbkdf2: took " .. (util.time() - start) .. "ms")
util.println(keyd.asHex())

local pkt = comms.modbus_packet()
pkt.make(1, 2, 7, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9})
local spkt = comms.scada_packet()
spkt.make(1, 1, pkt.raw_sendable())

start = util.time()
local data = textutils.serialize(spkt.raw_sendable(), { allow_repetitions = true, compact = true })

util.println("packet serialize: took " .. (util.time() - start) .. "ms")
util.println("message: " .. data)

start = util.time()
local v = {
    cipher = CTRMode.Cipher,
    decipher = CTRMode.Decipher,
    iv = Array.fromHex("000102030405060708090A0B0C0D0E0F"),
    key = Array.fromHex(keyd.asHex()),
    padding = ZeroPadding
}
util.println("v init: took " .. (util.time() - start) .. "ms")

start = util.time()
local cipher = v.cipher()
.setKey(v.key)
.setBlockCipher(AES128Cipher)
.setPadding(v.padding);
util.println("cipher init: took " .. (util.time() - start) .. "ms")

start = util.time()
local cipherOutput = cipher
            .init()
            .update(Stream.fromArray(v.iv))
            .update(Stream.fromString(data))
            .asHex();
util.println("encrypt: took " .. (util.time() - start) .. "ms")
util.println("ciphertext: " .. cipherOutput)

start = util.time()
local decipher = v.decipher()
    .setKey(v.key)
    .setBlockCipher(AES128Cipher)
    .setPadding(v.padding);
util.println("decipher init: took " .. (util.time() - start) .. "ms")

start = util.time()
local plainOutput = decipher
            .init()
            .update(Stream.fromArray(v.iv))
            .update(Stream.fromHex(cipherOutput))
            .asHex();
util.println("decrypt: took " .. (util.time() - start) .. "ms")
local a = Stream.fromHex(plainOutput)
local b = Stream.toString(a)
util.println("plaintext: " .. b)

local msg = "000102030405060708090A0B0C0D0E0F" .. cipherOutput

start = util.time()
local hash = HMAC()
    .setBlockSize(64)
    .setDigest(SHA1)
    .setKey(keyd)
    .init()
    .update(Stream.fromHex(msg))
    .finish()
    .asHex();
util.println("hmac: took " .. (util.time() - start) .. "ms")
util.println("hash: " .. hash)
