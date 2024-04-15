# cc-mek-scada
Configurable ComputerCraft SCADA system for multi-reactor control of Mekanism fission reactors with a GUI, automatic safety features, waste processing control, and more! 

![GitHub](https://img.shields.io/github/license/MikaylaFischler/cc-mek-scada)
![GitHub release (latest by date including pre-releases)](https://img.shields.io/github/v/release/MikaylaFischler/cc-mek-scada?include_prereleases)
![GitHub Workflow Status (with branch)](https://img.shields.io/github/actions/workflow/status/MikaylaFischler/cc-mek-scada/check.yml?branch=main&label=main)
![GitHub Workflow Status (with branch)](https://img.shields.io/github/actions/workflow/status/MikaylaFischler/cc-mek-scada/check.yml?branch=devel&label=devel)

### Join [the Discord](https://discord.gg/R9NSCkhcwt)!

![Discord](https://img.shields.io/discord/1129075839288496259?logo=Discord&logoColor=white&label=discord)

## Released Component Versions

![Installer](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Finstaller.json)


![Bootloader](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Fbootloader.json)
![Comms](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Fcommon.json)
![Comms](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Fcomms.json)
![Graphics](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Fgraphics.json)
![Lockbox](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Flockbox.json)


![Reactor PLC](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Freactor-plc.json)
![RTU](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Frtu.json)
![Supervisor](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Fsupervisor.json)
![Coordinator](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Fcoordinator.json)
![Pocket](https://img.shields.io/endpoint?url=https%3A%2F%2Fmikaylafischler.github.io%2Fcc-mek-scada%2Fpocket.json)

## Requirements

Mod Requirements:
- CC: Tweaked
- Mekanism v10.1+

Mod Recommendations:
- Advanced Peripherals (adds the capability to detect environmental radiation levels)
- Immersive Engineering (provides bundled redstone, though any mod containing bundled redstone will do)

v10.1+ is required due to the complete support of CC:Tweaked added in Mekanism v10.1

## Installation

You can install this on a ComputerCraft computer using either:
* `wget https://raw.githubusercontent.com/MikaylaFischler/cc-mek-scada/main/ccmsi.lua`
* `pastebin get sqUN6VUb ccmsi.lua`

## Contributing

Please reach out to me via Discord or email (or GitHub in some way) if you are thinking of making any contributions at this time. I started this project as a challenge for myself and have been enjoying having something I can work on in my own way. 

Once this is out of beta I will be more open to contributions, but for now I am hoping to keep them to a minimum as the remaining challenges are ones I am looking forward to solving.

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

### Security

HMAC message authentication is available as a configuration option to prevent replay attacks and generally prevent control or false data reporting within a system's network. This is done utilizing the [lua-lockbox](https://github.com/somesocks/lua-lockbox) project.

The other, simpler security feature is to enforce a maximum authorized transmission range, which is also a configurable feature on each device.
