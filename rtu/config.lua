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
        io = RS_IO.WASTE_PO,
        for_reactor = 1
    },
    {
        io = RS_IO.WASTE_PU,
        for_reactor = 1
    },
    {
        io = RS_IO.WASTE_AM,
        for_reactor = 1
    },
}
