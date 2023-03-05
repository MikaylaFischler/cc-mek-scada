local ISOIEC7816Padding = function(blockSize, byteCount)

    local paddingCount = blockSize - (byteCount % blockSize);
    local bytesLeft = paddingCount;

    local stream = function()
        if bytesLeft == paddingCount then
            bytesLeft = bytesLeft - 1;
            return 0x80;
        elseif bytesLeft > 0 then
            bytesLeft = bytesLeft - 1;
            return 0x00;
        else
            return nil;
        end
    end

    return stream;

end

return ISOIEC7816Padding;
