require("lockbox").insecure();

local Bit = require("lockbox.util.bit");
local String = require("string");
local Math = require("math");
local Queue = require("lockbox.util.queue");

local SHIFT = {
    7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
    5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
    4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
    6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21};

local CONSTANTS = {
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391};

local AND = Bit.band;
local OR  = Bit.bor;
local NOT = Bit.bnot;
local XOR = Bit.bxor;
local LROT = Bit.lrotate;
local LSHIFT = Bit.lshift;
local RSHIFT = Bit.rshift;

--MD5 is little-endian
local bytes2word = function(b0, b1, b2, b3)
    local i = b3; i = LSHIFT(i, 8);
    i = OR(i, b2); i = LSHIFT(i, 8);
    i = OR(i, b1); i = LSHIFT(i, 8);
    i = OR(i, b0);
    return i;
end

local word2bytes = function(word)
    local b0, b1, b2, b3;
    b0 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b1 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b2 = AND(word, 0xFF); word = RSHIFT(word, 8);
    b3 = AND(word, 0xFF);
    return b0, b1, b2, b3;
end

local dword2bytes = function(i)
    local b4, b5, b6, b7 = word2bytes(Math.floor(i / 0x100000000));
    local b0, b1, b2, b3 = word2bytes(i);
    return b0, b1, b2, b3, b4, b5, b6, b7;
end

local F = function(x, y, z) return OR(AND(x, y), AND(NOT(x), z)); end
local G = function(x, y, z) return OR(AND(x, z), AND(y, NOT(z))); end
local H = function(x, y, z) return XOR(x, XOR(y, z)); end
local I = function(x, y, z) return XOR(y, OR(x, NOT(z))); end

local MD5 = function()

    local queue = Queue();

    local A = 0x67452301;
    local B = 0xefcdab89;
    local C = 0x98badcfe;
    local D = 0x10325476;
    local public = {};

    local processBlock = function()
        local a = A;
        local b = B;
        local c = C;
        local d = D;

        local X = {};

        for i = 1, 16 do
            X[i] = bytes2word(queue.pop(), queue.pop(), queue.pop(), queue.pop());
        end

        for i = 0, 63 do
            local f, g, temp;

            if (0 <= i) and (i <= 15) then
                f = F(b, c, d);
                g = i;
            elseif (16 <= i) and (i <= 31) then
                f = G(b, c, d);
                g = (5 * i + 1) % 16;
            elseif (32 <= i) and (i <= 47) then
                f = H(b, c, d);
                g = (3 * i + 5) % 16;
            elseif (48 <= i) and (i <= 63) then
                f = I(b, c, d);
                g = (7 * i) % 16;
            end
            temp = d;
            d = c;
            c = b;
            b = b + LROT((a + f + CONSTANTS[i + 1] + X[g + 1]), SHIFT[i + 1]);
            a = temp;
        end

        A = AND(A + a, 0xFFFFFFFF);
        B = AND(B + b, 0xFFFFFFFF);
        C = AND(C + c, 0xFFFFFFFF);
        D = AND(D + d, 0xFFFFFFFF);
    end

    public.init = function()
        queue.reset();

        A = 0x67452301;
        B = 0xefcdab89;
        C = 0x98badcfe;
        D = 0x10325476;

        return public;
    end

    public.update = function(bytes)
        for b in bytes do
            queue.push(b);
            if(queue.size() >= 64) then processBlock(); end
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
        local  b0, b1, b2, b3 = word2bytes(A);
        local  b4, b5, b6, b7 = word2bytes(B);
        local  b8, b9, b10, b11 = word2bytes(C);
        local b12, b13, b14, b15 = word2bytes(D);

        return {b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15};
    end

    public.asHex = function()
        local  b0, b1, b2, b3 = word2bytes(A);
        local  b4, b5, b6, b7 = word2bytes(B);
        local  b8, b9, b10, b11 = word2bytes(C);
        local b12, b13, b14, b15 = word2bytes(D);

        return String.format("%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15);
    end

    public.asString = function()
        local b0, b1, b2, b3 = word2bytes(A);
        local b4, b5, b6, b7 = word2bytes(B);
        local b8, b9, b10, b11 = word2bytes(C);
        local b12, b13, b14, b15 = word2bytes(D);

        return string.pack(string.rep('B', 16),
            b0, b1, b2, b3, b4, b5, b6, b7, b8,
            b9, b10, b11, b12, b13, b14, b15
        )
    end

    return public;

end

return MD5;
