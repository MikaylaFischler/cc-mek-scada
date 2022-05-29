local Bit = require("lockbox.util.bit");
local String = require("string");
local Math = require("math");
local Queue = require("lockbox.util.queue");

local CONSTANTS = {
   0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
   0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
   0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
   0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
   0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
   0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
   0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
   0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2  };

local fmt = "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" ..
            "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x"

local AND = Bit.band;
local OR  = Bit.bor;
local NOT = Bit.bnot;
local XOR = Bit.bxor;
local RROT = Bit.rrotate;
local LSHIFT = Bit.lshift;
local RSHIFT = Bit.rshift;

--SHA2 is big-endian
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




local SHA2_224 = function()

    local queue = Queue();

    local h0 = 0xc1059ed8;
    local h1 = 0x367cd507;
    local h2 = 0x3070dd17;
    local h3 = 0xf70e5939;
    local h4 = 0xffc00b31;
    local h5 = 0x68581511;
    local h6 = 0x64f98fa7;
    local h7 = 0xbefa4fa4;

    local public = {};

    local processBlock = function()
        local a = h0;
        local b = h1;
        local c = h2;
        local d = h3;
        local e = h4;
        local f = h5;
        local g = h6;
        local h = h7;

        local w = {};

        for i = 0, 15 do
            w[i] = bytes2word(queue.pop(), queue.pop(), queue.pop(), queue.pop());
        end

        for i = 16, 63 do
            local s0 = XOR(RROT(w[i - 15], 7), XOR(RROT(w[i - 15], 18), RSHIFT(w[i - 15], 3)));
            local s1 = XOR(RROT(w[i - 2], 17), XOR(RROT(w[i - 2], 19), RSHIFT(w[i - 2], 10)));
            w[i] = AND(w[i - 16] + s0 + w[i - 7] + s1, 0xFFFFFFFF);
        end

        for i = 0, 63 do
            local s1 = XOR(RROT(e, 6), XOR(RROT(e, 11), RROT(e, 25)));
            local ch = XOR(AND(e, f), AND(NOT(e), g));
            local temp1 = h + s1 + ch + CONSTANTS[i + 1] + w[i];
            local s0 = XOR(RROT(a, 2), XOR(RROT(a, 13), RROT(a, 22)));
            local maj = XOR(AND(a, b), XOR(AND(a, c), AND(b, c)));
            local temp2 = s0 + maj;

            h = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
        end

        h0 = AND(h0 + a, 0xFFFFFFFF);
        h1 = AND(h1 + b, 0xFFFFFFFF);
        h2 = AND(h2 + c, 0xFFFFFFFF);
        h3 = AND(h3 + d, 0xFFFFFFFF);
        h4 = AND(h4 + e, 0xFFFFFFFF);
        h5 = AND(h5 + f, 0xFFFFFFFF);
        h6 = AND(h6 + g, 0xFFFFFFFF);
        h7 = AND(h7 + h, 0xFFFFFFFF);
    end

    public.init = function()
        queue.reset();

        h0 = 0xc1059ed8;
        h1 = 0x367cd507;
        h2 = 0x3070dd17;
        h3 = 0xf70e5939;
        h4 = 0xffc00b31;
        h5 = 0x68581511;
        h6 = 0x64f98fa7;
        h7 = 0xbefa4fa4;

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
        local b20, b21, b22, b23 = word2bytes(h5);
        local b24, b25, b26, b27 = word2bytes(h6);

        return {  b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15
                , b16, b17, b18, b19, b20, b21, b22, b23, b24, b25, b26, b27};
    end

    public.asHex = function()
        local  b0, b1, b2, b3 = word2bytes(h0);
        local  b4, b5, b6, b7 = word2bytes(h1);
        local  b8, b9, b10, b11 = word2bytes(h2);
        local b12, b13, b14, b15 = word2bytes(h3);
        local b16, b17, b18, b19 = word2bytes(h4);
        local b20, b21, b22, b23 = word2bytes(h5);
        local b24, b25, b26, b27 = word2bytes(h6);

        return String.format(fmt, b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15
                , b16, b17, b18, b19, b20, b21, b22, b23, b24, b25, b26, b27);
    end

    return public;

end

return SHA2_224;

