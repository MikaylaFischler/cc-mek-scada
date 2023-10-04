local Bit = require("lockbox.util.bit");
local Stream = require("lockbox.util.stream");
local Array = require("lockbox.util.array");

local XOR = Bit.bxor;

local HMAC = function()

    local public = {};
    local blockSize = 64;
    local Digest;
    local outerPadding = {};
    local innerPadding = {}
    local digest;

    public.setBlockSize = function(bytes)
        blockSize = bytes;
        return public;
    end

    public.setDigest = function(digestModule)
        Digest = digestModule;
        digest = Digest();
        return public;
    end

    public.setKey = function(key)
        local keyStream;

        if(Array.size(key) > blockSize) then
            keyStream = Stream.fromArray(Digest()
                        .update(Stream.fromArray(key))
                        .finish()
                        .asBytes());
        else
            keyStream = Stream.fromArray(key);
        end

        outerPadding = {};
        innerPadding = {};

        for i = 1, blockSize do
            local byte = keyStream();
            if byte == nil then byte = 0x00; end
            outerPadding[i] = XOR(0x5C, byte);
            innerPadding[i] = XOR(0x36, byte);
        end

        return public;
    end

    public.init = function()
        digest.init()
              .update(Stream.fromArray(innerPadding));
        return public;
    end

    public.update = function(messageStream)
        digest.update(messageStream);
        return public;
    end

    public.finish = function()
        local inner = digest.finish().asBytes();
        digest.init()
              .update(Stream.fromArray(outerPadding))
              .update(Stream.fromArray(inner))
              .finish();

        return public;
    end

    public.asBytes = function()
        return digest.asBytes();
    end

    public.asHex = function()
        return digest.asHex();
    end

    return public;

end

return HMAC;
