---@diagnostic disable: undefined-global
-- luacheck: ignore install_manifest, ccmsi_offline, app_files, dep_files, lgray, green, white

local b64_lookup = {
    ['A'] = 0,  ['B'] = 1,  ['C'] = 2,  ['D'] = 3,  ['E'] = 4,  ['F'] = 5,  ['G'] = 6,  ['H'] = 7,  ['I'] = 8,  ['J'] = 9,  ['K'] = 10, ['L'] = 11, ['M'] = 12, ['N'] = 13, ['O'] = 14, ['P'] = 15, ['Q'] = 16, ['R'] = 17, ['S'] = 18, ['T'] = 19, ['U'] = 20, ['V'] = 21, ['W'] = 22, ['X'] = 23, ['Y'] = 24, ['Z'] = 25,
    ['a'] = 26, ['b'] = 27, ['c'] = 28, ['d'] = 29, ['e'] = 30, ['f'] = 31, ['g'] = 32, ['h'] = 33, ['i'] = 34, ['j'] = 35, ['k'] = 36, ['l'] = 37, ['m'] = 38, ['n'] = 39, ['o'] = 40, ['p'] = 41, ['q'] = 42, ['r'] = 43, ['s'] = 44, ['t'] = 45, ['u'] = 46, ['v'] = 47, ['w'] = 48, ['x'] = 49, ['y'] = 50, ['z'] = 51,
    ['0'] = 52, ['1'] = 53, ['2'] = 54, ['3'] = 55, ['4'] = 56, ['5'] = 57, ['6'] = 58, ['7'] = 59, ['8'] = 60, ['9'] = 61, ['+'] = 62, ['/'] = 63
}

local BYTE  = 0xFF
local CHAR  = string.char
local BOR   = bit.bor           ---@type function
local BAND  = bit.band          ---@type function
local LSHFT = bit.blshift       ---@type function
local RSHFT = bit.blogic_rshift ---@type function

-- decode a base64 string
---@param input string
local function b64_decode(input)
---@diagnostic disable-next-line: undefined-field
    local t_start = os.epoch("local")

    local decoded = {}

    local c_idx, idx = 1, 1

    for _ = 1, input:len() / 4 do
        local block = input:sub(idx, idx + 4)
        local word = 0x0

        -- build the 24-bit sequence from the 4 characters
        for i = 1, 4 do
            local num = b64_lookup[block:sub(i, i)]

            if num then
                word = BOR(word, LSHFT(b64_lookup[block:sub(i, i)], (4 - i) * 6))
            end
        end

        -- decode the 24-bit sequence as 8 bytes
        for i = 1, 3 do
            local char = BAND(BYTE, RSHFT(word, (3 - i) * 8))

            if char ~= 0 then
                decoded[c_idx] = CHAR(char)
                c_idx = c_idx + 1
            end
        end

        idx = idx + 4
    end

---@diagnostic disable-next-line: undefined-field
    local elapsed = (os.epoch("local") - t_start)
    local decoded_str = table.concat(decoded)

    return decoded_str, elapsed
end

-- write files recursively from base64 encodings in a table
---@param files table
---@param path string
local function write_files(files, path)
    fs.makeDir(path)

    for k, v in pairs(files) do
        if type(v) == "table" then
            if k == "system" then
                -- write system files to root
                write_files(v, "/")
            else
                -- descend into directories
                write_files(v, path .. "/" .. k .. "/")
            end

---@diagnostic disable-next-line: undefined-field
            os.sleep(0.05)
        else
            local handle = fs.open(path .. k, "w")
            local text, time = b64_decode(v)

            print("decoded '" .. k .. "' in " .. time .. "ms")

            handle.write(text)
            handle.close()
        end
    end
end

local function write_install()
    local handle = fs.open("install_manifest.json", "w")
    handle.write(b64_decode(install_manifest))
    handle.close()

    handle = fs.open("ccmsim.lua", "w")
    handle.write(b64_decode(ccmsi_offline))
    handle.close()
end

lgray()

-- write both app and dependency files
write_files(app_files, "/")
write_files(dep_files, "/")

-- write a install manifest and offline installer
write_install()

green()
print("Done!")
white()
print("All files have been installed. The app can be started with 'startup' and configured with 'configure'.")
lgray()
print("Hint: You can use 'ccmsim' to manage your off-line installation.")
white()
