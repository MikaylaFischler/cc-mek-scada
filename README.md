# cc-mek-scada
Configurable ComputerCraft SCADA system for multi-reactor control of Mekanism fission reactors with a GUI, automatic safety features, waste processing control, and more! 

Mod Requirements:
- CC: Tweaked
- Mekanism v10.1+

Mod Recommendations:
- Advanced Peripherals (adds the capability to detect environmental radiation levels)

v10.1+ is required due the complete support of CC:Tweaked added in Mekanism v10.1

There was also an apparent bug with boilers disconnecting and reconnecting when active in my test world on 10.0.24, so it may not even have been an option to fully implement this with support for 10.0.

## Installation

You can install this on a ComputerCraft computer using either:
* `wget https://raw.githubusercontent.com/MikaylaFischler/cc-mek-scada/main/ccmsi.lua`
* `pastebin get iUMjgW0C ccmsi.lua`

## [SCADA](https://en.wikipedia.org/wiki/SCADA)
> Supervisory control and data acquisition (SCADA) is a control system architecture comprising computers, networked data communications and graphical user interfaces for high-level supervision of machines and processes. It also covers sensors and other devices, such as programmable logic controllers, which interface with process plant or machinery.

This project implements concepts of a SCADA system in ComputerCraft (because why not? ..okay don't answer that). I recommend reviewing that linked wikipedia page on SCADA if you *want* to understand the concepts used here.

![Architecture](https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/Functional_levels_of_a_Distributed_Control_System.svg/1000px-Functional_levels_of_a_Distributed_Control_System.svg.png)

SCADA and industrial automation terminology is used throughout the project, such as:
- Supervisory Computer: Gathers data and controls the process
- Coordinating Computer: Used as the HMI component, user requests high-level processing operations
- RTU: Remote Terminal Unit
- PLC: Programmable Logic Controller

## ComputerCraft Architecture

### Coordinator Server

There can only be one of these. This server acts as a hybrid of levels 3 & 4 in the SCADA diagram above. In addition to viewing status and controlling processes with advanced monitors, it can host access for one or more Pocket computers.

### Supervisory Computers

There should be one of these per facility system. Currently, that means only one. In the future, multiple supervisors would provide the capability of coordinating between multiple facilities (like a fission facility, fusion facility, etc).

### RTUs

RTUs are effectively basic connections between a device and the SCADA system with no internal logic providing the system with I/O capabilities. A single Advanced Computer can represent multiple RTUs as instead I am modeling an RTU as the wired modems connected to that computer rather than the computer itself. Each RTU is referenced separately with an identifier in the modbus communications (see Communications section), so a single computer can distribute instructions to multiple devices. This should save on having a pile of computers everywhere (but if you want to have that, no one's stopping you).

The RTU control code is relatively unique, as instead of having instructions be decoded simply, due to using modbus, I implemented a generalized RTU interface. To fulfill this, each type of I/O operation is linked to a function rather than implementing the logic itself. For example, to connect an input register to a turbine `getFlowRate()` call, the function reference itself is passed to the `connect_input_reg()` function. A call to `read_input_reg()` on that register address will call the `turbine.getFlowRate()` function and return the result.

### PLCs

PLCs are advanced devices that allow for both reporting and control to/from the SCADA system in addition to programed behaviors independent of the SCADA system. Currently there is only one type of PLC, and that is the reactor PLC. This is responsible for reporting on and controlling the reactor as a part of the SCADA system, and independently regulating the safety of the reactor. It checks the status for multiple hazard scenarios and shuts down the reactor if any condition is met.

There can and should only be one of these per reactor. A single Advanced Computer will act as the PLC, with either a direct connection (physical contact) or a wired modem connection to the reactor logic port.

## Communications

A vaguely-modbus [modbus](https://en.wikipedia.org/wiki/Modbus) communication protocol is used for communication with RTUs. Useful terminology for you to know:
- Discrete Inputs: Single Bit Read-Only (digital inputs)
- Coils: Single Bit Read/Write (digital I/O)
- Input Registers: Multi-Byte Read-Only (analog inputs)
- Holding Registers: Multi-Byte Read/Write (analog I/O)

### Security and Encryption

TBD, I am planning on AES symmetric encryption for security + HMAC to prevent replay attacks. This will be done utilizing this codebase: https://github.com/somesocks/lua-lockbox.

This is somewhat important here as otherwise anyone can just control your setup, which is undeseriable. Unlike normal Minecraft PVP chaos, it would be very difficult to identify who is messing with your system, as with an Ender Modem they can do it from effectively anywhere and the server operators would have to check every computer's filesystem to find suspicious code. 

The other security mitigation for commanding (no effect on monitoring) is to enforce a maximum authorized transmission range, which has been added as a configurable feature.

## Known Issues

None yet since the switch to requiring 10.1+!
