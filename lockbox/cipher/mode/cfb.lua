local Array = require("lockbox.util.array");
local Stream = require("lockbox.util.stream");
local Queue = require("lockbox.util.queue");

local CFB = {};

CFB.Cipher = function()

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
                    iv = out;
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

CFB.Decipher = function()

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
                    iv = block;
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

return CFB;
