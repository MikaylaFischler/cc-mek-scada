local ANSIX923Padding = function(blockSize, byteCount)

    local paddingCount = blockSize - (byteCount % blockSize);
    local bytesLeft = paddingCount;

    local stream = function()
        if bytesLeft > 1 then
            bytesLeft = bytesLeft - 1;
            return 0x00;
        elseif bytesLeft > 0 then
            bytesLeft = bytesLeft - 1;
            return paddingCount;
        else
            return nil;
        end
    end

    return stream;

end

return ANSIX923Padding;
