-- Peripheral Classes

--#region CC: TWEAKED CLASSES https://tweaked.cc

---@class Redirect
---@field write fun(text: string) Write text at the current cursor position, moving the cursor to the end of the text.
---@field scroll fun(y: integer) Move all positions up (or down) by y pixels.
---@field getCursorPos fun() : x: integer, y: integer Get the position of the cursor.
---@field setCursorPos fun(x: integer, y: integer) Set the position of the cursor.
---@field getCursorBlink fun() : boolean Checks if the cursor is currently blinking.
---@field setCursorBlink fun(blink: boolean) Sets whether the cursor should be visible (and blinking) at the current cursor position.
---@field getSize fun() : width: integer, height: integer Get the size of the terminal.
---@field clear fun() Clears the terminal, filling it with the current background color.
---@field clearLine fun() Clears the line the cursor is currently on, filling it with the current background color.
---@field getTextColor fun() : color Return the color that new text will be written as.
---@field setTextColor fun(color: color) Set the colour that new text will be written as.
---@field getBackgroundColor fun() : color Return the current background color.
---@field setBackgroundColor fun(color: color) set the current background color.
---@field isColor fun() Determine if this terminal supports color.
---@field blit fun(text: string, textColor: string, backgroundColor: string) Writes text to the terminal with the specific foreground and background colors.
---@diagnostic disable-next-line: duplicate-doc-field
---@field setPaletteColor fun(index: color, color: integer) Set the palette for a specific color.
---@diagnostic disable-next-line: duplicate-doc-field
---@field setPaletteColor fun(index: color, r: number, g: number, b:number) Set the palette for a specific color. R/G/B are 0 to 1.
---@field getPaletteColor fun(color: color) :  r: number, g: number, b:number Get the current palette for a specific color.

---@class Window:Redirect
---@field getLine fun(y: integer) : content: string, fg: string, bg: string Get the buffered contents of a line in this window.
---@field setVisible fun(visible: boolean) Set whether this window is visible. Invisible windows will not be drawn to the screen until they are made visible again.
---@field isVisible fun() : visible: boolean Get whether this window is visible. Invisible windows will not be drawn to the screen until they are made visible again.
---@field redraw fun() Draw this window. This does nothing if the window is not visible.
---@field restoreCursor fun() Set the current terminal's cursor to where this window's cursor is. This does nothing if the window is not visible.
---@field getPosition fun() : x: integer, y: integer Get the position of the top left corner of this window.
---@field reposition fun(new_x: integer, new_y: integer, new_width?: integer, new_height?: integer, new_parent?: Redirect) Reposition or resize the given window.

---@class Monitor:Redirect,PPMDevice
---@field setTextScale fun(scale: number) Set the scale of this monitor.
---@field getTextScale fun() : number Get the monitor's current text scale.

---@class Modem:PPMDevice
---@field open fun(channel: integer) Open a channel on a modem.
---@field isOpen fun(channel: integer) : boolean Check if a channel is open.
---@field close fun(channel: integer) Close an open channel, meaning it will no longer receive messages.
---@field closeAll fun() Close all open channels.
---@field transmit fun(channel: integer, replyChannel: integer, payload: any) Sends a modem message on a certain channel.
---@field isWireless fun() : boolean Determine if this is a wired or wireless modem.
---@field getNamesRemote fun() : string[] List all remote peripherals on the wired network.
---@field isPresentRemote fun(name: string) : boolean Determine if a peripheral is available on this wired network.
---@field getTypeRemote fun(name: string) : string|nil Get the type of a peripheral is available on this wired network.
---@field hasTypeRemote fun(name: string, type: string) : boolean|nil Check a peripheral is of a particular .
---@field getMethodsRemote fun(name: string) : string[] Get all available methods for the remote peripheral with the given name.
---@field callRemote fun(remoteName: string, method: string, ...) : table Call a method on a peripheral on this wired network.
---@field getNameLocal fun() : string|nil Returns the network name of the current computer, if the modem is on.

---@class Speaker:PPMDevice
---@field playNote fun(instrument: string, volume?: number, pitch?: number) : success: boolean Plays a note block note through the speaker.
---@field playSound fun(name: string, volume?: number, pitch?: number) : success: boolean Plays a Minecraft sound through the speaker.
---@field playAudio fun(audio: number[], volume?: number) : success: boolean Attempt to stream some audio data to the speaker.
---@field stop fun() Stop all audio being played by this speaker.

--#endregion

--#region Mekanism Classes

---@class Multiblock:PPMDevice
---@field isFormed fun() : boolean Check if this multiblock is formed.

---@class MultiblockFormed:Multiblock
---@field getLength fun() : integer Length of the multiblock.
---@field getWidth fun() : integer Width of the multiblock.
---@field getHeight fun() : integer Height of the multiblock.
---@field getMinPos fun() : coordinate Get the minimum corner of the multiblock.
---@field getMaxPos fun() : coordinate Get the maximum corner of the multiblock.

---@class FissionReactor:MultiblockFormed
---@field activate fun() : nil Enable the reactor.
---@field scram fun() : nil	Disable the reactor.
---@field setBurnRate fun(rate: number) : number Set the burn rate.
---@field getBurnRate fun() : number Get the configured burn rate.
---@field getActualBurnRate fun() : number Get the actual burn rate (0 if no fuel).
---@field getMaxBurnRate fun() : integer Get the maximum burn rate according to the number of fuel assemblies.
---@field getStatus fun() : boolean Get the reactor enable status.
---@field getTemperature fun() : number Get the reactor core temperature (K).
---@field getHeatingRate fun() : integer Get the coolant heating rate.
---@field getBoilEfficiency fun() : number Reactor boil efficiency.
---@field getEnvironmentalLoss fun() : number Get the environmental loss factor.
---@field getDamagePercent fun() : integer Get the reactor damage, 0 - 100%.
---@field isForceDisabled fun() : boolean If meltdowns are disabled, this returns true if the reactor was disabled instead of melting down.
---@field getFuelAssemblies fun() : integer Get the number of fuel assemblies.
---@field getFuelSurfaceArea fun() : integer Get the exposed fuel surface area.
---@field getHeatCapacity fun() : number Get the heat capacity of the reactor structure.
---@field getFuel fun() : tank_fluid Get the fuel.
---@field getFuelNeeded fun() : integer Get the remaining capacity available for fuel.
---@field getFuelCapacity fun() : integer Get the fuel capacity.
---@field getFuelFilledPercentage fun() : number Get the fuel fill (0 - 1).
---@field getWaste fun() : tank_fluid Get the waste.
---@field getWasteNeeded fun() : integer Get the remaining capacity available for waste.
---@field getWasteCapacity fun() : integer Get the waste capacity.
---@field getWasteFilledPercentage fun() : number Get the waste fill (0 - 1).
---@field getCoolant fun() : tank_fluid Get the cooled coolant.
---@field getCoolantNeeded fun() : integer Get the remaining capacity available for cooled coolant.
---@field getCoolantCapacity fun() : integer Get the cooled coolant capacity.
---@field getCoolantFilledPercentage fun() : number Get the cooled coolant fill (0 - 1).
---@field getHeatedCoolant fun() : tank_fluid Get the heated coolant.
---@field getHeatedCoolantNeeded fun() : integer Get the remaining capacity available for heated coolant.
---@field getHeatedCoolantCapacity fun() : integer Get the heated coolant capacity.
---@field getHeatedCoolantFilledPercentage fun() : number Get the heated coolant fill (0 - 1).

---#endregion
