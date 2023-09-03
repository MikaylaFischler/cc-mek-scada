local Bit = require("lockbox.util.bit");
local String = require("string");
local Math = require("math");
local Queue = require("lockbox.util.queue");

local AND = Bit.band;
local OR  = Bit.bor;
local XOR = Bit.bxor;
local LROT = Bit.lrotate;
local LSHIFT = Bit.lshift;
local RSHIFT = Bit.rshift;

--SHA1 is big-endian
local bytes2word = function(b0, b1, b2, b3)
    local i = b0; i = LSHIFT(i, 8);
    i = OR(i, b1); i = LSHIFT(i, 8);
    i = OR(i, b2); i = LSHIFT(i, 8);
    i = OR(i, b3);
    return i;
end

local word2bytes = function(word)
    local b0, b1, b2, b3;
    b3 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b2 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b1 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b0 = AND(word, 0xFF);
    return b0, b1, b2, b3;
end

local dword2bytes = function(i)
    local b4, b5, b6, b7 = word2bytes(i);
    local b0, b1, b2, b3 = word2bytes(Math.floor(i / 0x100000000));
    return b0, b1, b2, b3, b4, b5, b6, b7;
end

local F = function(x, y, z) return XOR(z, AND(x, XOR(y, z))); end
local G = function(x, y, z) return XOR(x, XOR(y, z)); end
local H = function(x, y, z) return OR(AND(x, OR(y, z)), AND(y, z)); end
local I = function(x, y, z) return XOR(x, XOR(y, z)); end

local SHA1 = function()

    local queue = Queue();

    local h0 = 0x67452301;
    local h1 = 0xEFCDAB89;
    local h2 = 0x98BADCFE;
    local h3 = 0x10325476;
    local h4 = 0xC3D2E1F0;

    local public = {};

    local processBlock = function()
        local a = h0;
        local b = h1;
        local c = h2;
        local d = h3;
        local e = h4;
        local temp;
        local k;

        local w = {};
        for i = 0, 15 do
            w[i] = bytes2word(queue.pop(), queue.pop(), queue.pop(), queue.pop());
        end

        for i = 16, 79 do
            w[i] = LROT((XOR(XOR(w[i - 3], w[i - 8]), XOR(w[i - 14], w[i - 16]))), 1);
        end

        for i = 0, 79 do
            if (i <= 19) then
                temp = F(b, c, d);
                k = 0x5A827999;
            elseif (i <= 39) then
                temp = G(b, c, d);
                k = 0x6ED9EBA1;
            elseif (i <= 59) then
                temp = H(b, c, d);
                k = 0x8F1BBCDC;
            else
                temp = I(b, c, d);
                k = 0xCA62C1D6;
            end
            temp = LROT(a, 5) + temp + e + k + w[i];
            e = d;
            d = c;
            c = LROT(b, 30);
            b = a;
            a = temp;
        end

        h0 = AND(h0 + a, 0xFFFFFFFF);
        h1 = AND(h1 + b, 0xFFFFFFFF);
        h2 = AND(h2 + c, 0xFFFFFFFF);
        h3 = AND(h3 + d, 0xFFFFFFFF);
        h4 = AND(h4 + e, 0xFFFFFFFF);
    end

    public.init = function()
        queue.reset();
        h0 = 0x67452301;
        h1 = 0xEFCDAB89;
        h2 = 0x98BADCFE;
        h3 = 0x10325476;
        h4 = 0xC3D2E1F0;
        return public;
    end


    public.update = function(bytes)
        for b in bytes do
            queue.push(b);
            if queue.size() >= 64 then processBlock(); end
        end

        return public;
    end

    public.finish = function()
        local bits = queue.getHead() * 8;

        queue.push(0x80);
        while ((queue.size() + 7) % 64) < 63 do
            queue.push(0x00);
        end

        local b0, b1, b2, b3, b4, b5, b6, b7 = dword2bytes(bits);

        queue.push(b0);
        queue.push(b1);
        queue.push(b2);
        queue.push(b3);
        queue.push(b4);
        queue.push(b5);
        queue.push(b6);
        queue.push(b7);

        while queue.size() > 0 do
            processBlock();
        end

        return public;
    end

    public.asBytes = function()
        local  b0, b1, b2, b3 = word2bytes(h0);
        local  b4, b5, b6, b7 = word2bytes(h1);
        local  b8, b9, b10, b11 = word2bytes(h2);
        local b12, b13, b14, b15 = word2bytes(h3);
        local b16, b17, b18, b19 = word2bytes(h4);

        return {b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15, b16, b17, b18, b19};
    end

    public.asHex = function()
        local  b0, b1, b2, b3 = word2bytes(h0);
        local  b4, b5, b6, b7 = word2bytes(h1);
        local  b8, b9, b10, b11 = word2bytes(h2);
        local b12, b13, b14, b15 = word2bytes(h3);
        local b16, b17, b18, b19 = word2bytes(h4);

        return String.format("%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15, b16, b17, b18, b19);
    end

    return public;
end

return SHA1;
