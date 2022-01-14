function rtu_init()
    local self = {
        discrete_inputs = {},
        coils = {},
        input_regs = {},
        holding_regs = {},
        io_count_cache = { 0, 0, 0, 0 }
    }

    local __count_io = function ()
        self.io_count_cache = { #self.discrete_inputs, #self.coils, #self.input_regs, #self.holding_regs }
    end

    local io_count = function ()
        return self.io_count_cache[0], self.io_count_cache[1], self.io_count_cache[2], self.io_count_cache[3]
    end

    -- discrete inputs: single bit read-only

    local connect_di = function (f)
        table.insert(self.discrete_inputs, f)
        __count_io()
        return #self.discrete_inputs
    end

    local read_di = function (di_addr)
        return self.discrete_inputs[di_addr]()
    end

    -- coils: single bit read-write

    local connect_coil = function (f_read, f_write)
        table.insert(self.coils, { read = f_read, write = f_write })
        __count_io()
        return #self.coils
    end

    local read_coil = function (coil_addr)
        return self.coils[coil_addr].read()
    end

    local write_coil = function (coil_addr, value)
        self.coils[coil_addr].write(value)
    end

    -- input registers: multi-bit read-only

    local connect_input_reg = function (f)
        table.insert(self.input_regs, f)
        __count_io()
        return #self.input_regs
    end

    local read_input_reg = function (reg_addr)
        return self.coils[reg_addr]()
    end

    -- holding registers: multi-bit read-write

    local connect_holding_reg = function (f_read, f_write)
        table.insert(self.holding_regs, { read = f_read, write = f_write })
        __count_io()
        return #self.holding_regs
    end

    local read_holding_reg = function (reg_addr)
        return self.coils[reg_addr].read()
    end

    local write_holding_reg = function (reg_addr, value)
        self.coils[reg_addr].write(value)
    end

    return {
        io_count = io_count,
        connect_di = connect_di,
        read_di = read_di,
        connect_coil = connect_coil,
        read_coil = read_coil,
        write_coil = write_coil,
        connect_input_reg = connect_input_reg,
        read_input_reg = read_input_reg,
        connect_holding_reg = connect_holding_reg,
        read_holding_reg = read_holding_reg,
        write_holding_reg = write_holding_reg
    }
end
