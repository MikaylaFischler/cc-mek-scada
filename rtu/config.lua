-- #REQUIRES rsio.lua

SCADA_SERVER = 16000

RTU_DEVICES = {
    {
        name = "boiler_0",
        index = 1,
        for_reactor = 1
    },
    {
        name = "turbine_0",
        index = 1,
        for_reactor = 1
    }
}

RTU_REDSTONE = {
    {
        for_reactor = 1,
        io = {
            {
                channel = RS_IO.WASTE_PO,
                side = "top",
                bundled_color = colors.blue,
                for_reactor = 1
            },
            {
                channel = RS_IO.WASTE_PU,
                side = "top",
                bundled_color = colors.cyan,
                for_reactor = 1
            },
            {
                channel = RS_IO.WASTE_AM,
                side = "top",
                bundled_color = colors.purple,
                for_reactor = 1
            }
        }
    }
}
