local Bit = require("lockbox.util.bit");
local Array = require("lockbox.util.array");
local Stream = require("lockbox.util.stream");
local Math = require("math");

local AND = Bit.band;
local RSHIFT = Bit.rshift;

local word2bytes = function(word)
    local b0, b1, b2, b3;
    b3 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b2 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b1 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b0 = AND(word, 0xFF);
    return b0, b1, b2, b3;
end

local PBKDF2 = function()

    local public = {};

    local blockLen = 16;
    local dKeyLen = 256;
    local iterations = 4096;

    local salt;
    local password;


    local PRF;

    local dKey;


    public.setBlockLen = function(len)
        blockLen = len;
        return public;
    end

    public.setDKeyLen = function(len)
        dKeyLen = len
        return public;
    end

    public.setIterations = function(iter)
        iterations = iter;
        return public;
    end

    public.setSalt = function(saltBytes)
        salt = saltBytes;
        return public;
    end

    public.setPassword = function(passwordBytes)
        password = passwordBytes;
        return public;
    end

    public.setPRF = function(prf)
        PRF = prf;
        return public;
    end

    local buildBlock = function(i)
        local b0, b1, b2, b3 = word2bytes(i);
        local ii = {b0, b1, b2, b3};
        local s = Array.concat(salt, ii);

        local out = {};

        PRF.setKey(password);
        for c = 1, iterations do
            PRF.init()
                .update(Stream.fromArray(s));

            s = PRF.finish().asBytes();
            if(c > 1) then
                out = Array.XOR(out, s);
            else
                out = s;
            end
        end

        return out;
    end

    public.finish = function()
        local blocks = Math.ceil(dKeyLen / blockLen);

        dKey = {};

        for b = 1, blocks do
            local block = buildBlock(b);
            dKey = Array.concat(dKey, block);
        end

        if(Array.size(dKey) > dKeyLen) then dKey = Array.truncate(dKey, dKeyLen); end

        return public;
    end

    public.asBytes = function()
        return dKey;
    end

    public.asHex = function()
        return Array.toHex(dKey);
    end

    return public;
end

return PBKDF2;
