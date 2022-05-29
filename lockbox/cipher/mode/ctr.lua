local Array = require("lockbox.util.array");
local Stream = require("lockbox.util.stream");
local Queue = require("lockbox.util.queue");

local Bit = require("lockbox.util.bit");

local AND = Bit.band;

local CTR = {};

CTR.Cipher = function()

    local public = {};

    local key;
    local blockCipher;
    local padding;
    local inputQueue;
    local outputQueue;
    local iv;

    public.setKey = function(keyBytes)
        key = keyBytes;
        return public;
    end

    public.setBlockCipher = function(cipher)
        blockCipher = cipher;
        return public;
    end

    public.setPadding = function(paddingMode)
        padding = paddingMode;
        return public;
    end

    public.init = function()
        inputQueue = Queue();
        outputQueue = Queue();
        iv = nil;
        return public;
    end

    local updateIV = function()
        iv[16] = iv[16] + 1;
        if iv[16] <= 0xFF then return; end
        iv[16] = AND(iv[16], 0xFF);

        iv[15] = iv[15] + 1;
        if iv[15] <= 0xFF then return; end
        iv[15] = AND(iv[15], 0xFF);

        iv[14] = iv[14] + 1;
        if iv[14] <= 0xFF then return; end
        iv[14] = AND(iv[14], 0xFF);

        iv[13] = iv[13] + 1;
        if iv[13] <= 0xFF then return; end
        iv[13] = AND(iv[13], 0xFF);

        iv[12] = iv[12] + 1;
        if iv[12] <= 0xFF then return; end
        iv[12] = AND(iv[12], 0xFF);

        iv[11] = iv[11] + 1;
        if iv[11] <= 0xFF then return; end
        iv[11] = AND(iv[11], 0xFF);

        iv[10] = iv[10] + 1;
        if iv[10] <= 0xFF then return; end
        iv[10] = AND(iv[10], 0xFF);

        iv[9] = iv[9] + 1;
        if iv[9] <= 0xFF then return; end
        iv[9] = AND(iv[9], 0xFF);

        return;
    end

    public.update = function(messageStream)
        local byte = messageStream();
        while (byte ~= nil) do
            inputQueue.push(byte);

            if(inputQueue.size() >= blockCipher.blockSize) then
                local block = Array.readFromQueue(inputQueue, blockCipher.blockSize);

                if(iv == nil) then
                    iv = block;
                else
                    local out = iv;
                    out = blockCipher.encrypt(key, out);

                    out = Array.XOR(out, block);
                    Array.writeToQueue(outputQueue, out);
                    updateIV();
                end
            end
            byte = messageStream();
        end
        return public;
    end

    public.finish = function()
        local paddingStream = padding(blockCipher.blockSize, inputQueue.getHead());
        public.update(paddingStream);

        return public;
    end

    public.getOutputQueue = function()
        return outputQueue;
    end

    public.asHex = function()
        return Stream.toHex(outputQueue.pop);
    end

    public.asBytes = function()
        return Stream.toArray(outputQueue.pop);
    end

    return public;

end


CTR.Decipher = function()

    local public = {};

    local key;
    local blockCipher;
    local padding;
    local inputQueue;
    local outputQueue;
    local iv;

    public.setKey = function(keyBytes)
        key = keyBytes;
        return public;
    end

    public.setBlockCipher = function(cipher)
        blockCipher = cipher;
        return public;
    end

    public.setPadding = function(paddingMode)
        padding = paddingMode;
        return public;
    end

    public.init = function()
        inputQueue = Queue();
        outputQueue = Queue();
        iv = nil;
        return public;
    end

    local updateIV = function()
        iv[16] = iv[16] + 1;
        if iv[16] <= 0xFF then return; end
        iv[16] = AND(iv[16], 0xFF);

        iv[15] = iv[15] + 1;
        if iv[15] <= 0xFF then return; end
        iv[15] = AND(iv[15], 0xFF);

        iv[14] = iv[14] + 1;
        if iv[14] <= 0xFF then return; end
        iv[14] = AND(iv[14], 0xFF);

        iv[13] = iv[13] + 1;
        if iv[13] <= 0xFF then return; end
        iv[13] = AND(iv[13], 0xFF);

        iv[12] = iv[12] + 1;
        if iv[12] <= 0xFF then return; end
        iv[12] = AND(iv[12], 0xFF);

        iv[11] = iv[11] + 1;
        if iv[11] <= 0xFF then return; end
        iv[11] = AND(iv[11], 0xFF);

        iv[10] = iv[10] + 1;
        if iv[10] <= 0xFF then return; end
        iv[10] = AND(iv[10], 0xFF);

        iv[9] = iv[9] + 1;
        if iv[9] <= 0xFF then return; end
        iv[9] = AND(iv[9], 0xFF);

        return;
    end

    public.update = function(messageStream)
        local byte = messageStream();
        while (byte ~= nil) do
            inputQueue.push(byte);

            if(inputQueue.size() >= blockCipher.blockSize) then
                local block = Array.readFromQueue(inputQueue, blockCipher.blockSize);

                if(iv == nil) then
                    iv = block;
                else
                    local out = iv;
                    out = blockCipher.encrypt(key, out);

                    out = Array.XOR(out, block);
                    Array.writeToQueue(outputQueue, out);
                    updateIV();
                end
            end
            byte = messageStream();
        end
        return public;
    end

    public.finish = function()
        local paddingStream = padding(blockCipher.blockSize, inputQueue.getHead());
        public.update(paddingStream);

        return public;
    end

    public.getOutputQueue = function()
        return outputQueue;
    end

    public.asHex = function()
        return Stream.toHex(outputQueue.pop);
    end

    public.asBytes = function()
        return Stream.toArray(outputQueue.pop);
    end

    return public;

end




return CTR;

