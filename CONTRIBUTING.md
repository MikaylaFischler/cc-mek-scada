# Contribution Guide

>[!NOTE]
Until the system is out of beta, contributions will be limited as I wrap up the specific release feature set.

This project is highly complex for a ComputerCraft Lua application. Contributions need to follow style guides and meet the code quality I've kept this project up to for years. Contributions must be tested appropriately with test results included.

I have extensively tested software components for stability required for safety, with tiers of software robustness.
1. **Critical: High-Impact** -
   The Reactor-PLC is "uncrashable" and must remain so. I've extensively reviewed every line and behavior, so any code contributions must be at this high standard. Simple is stable, so the less code the better. Always check for parameter validity and extensively test any changes to critical thread functions.
2. **Important: Moderate-Impact** -
   The Supervisor and RTU Gateway should rarely, if ever, crash. Certain places may not be held to as strict of a level as above, but should be written understanding all the possible inputs to and impacts of a section of code.
3. **Useful: Low-Impact** -
   The Coordinator and Pocket are nice UI apps, and things can break. There's a lot of data going to and from them, so checking every single incoming value would have negative performance impacts and increase program size. If they break, the user can restart them. Don't introduce careless bugs, but making assumptions about the integrity of incoming data is acceptable.

## Valuable Contributions

Pull requests should not consist of purely whitespace changes, comment changes, or other trivial changes. They should target specific features, bug fixes, or functional improvements. I reserve the right to decline PRs that don't follow this in good faith.

## Project Management Guidelines

Any contributions should be linked to an open GitHub issue. These are used to track progress, discuss changes, etc. Surprise changes to this project might conflict with existing plans, so I prefer we coordinate changes ahead of time.

## Software Guidelines

These guidelines are subject to change. The general rule is make the code look like the rest of the code around it and elsewhere in the project.

### Style Guide

PRs will only be accepted if they match the style of this project and pass manual and automated code analysis. Listing out the whole style guide would take a while, so as stated above, please review code adjacent to your modifications.

1. **No Block Comments.**
   These interfere with the minification used for the bundled installation files due to the complexity of parsing Lua block comments. The minification code is meant to be simple to have 0 risk of breaking anything, so I'm staying far away from those.
2. **Comment Your Code.**
   This includes type hints as used elsewhere throughout the project. Your comments should be associated with parts of code that are more complex or unclear, or otherwise to split up sections of tasks. You'll see `--#region` used in various places.
   - Type hints are intended to be utilized by the `sumneko.lua` vscode extension. You should use this while developing, as it provides extremely valuable functionality.
3. **Whitespace Usage.**
   Whitespace should be used to separate function parameters and operators. The one exception is the unique styling of graphics elements, which you should compare against if modifying them.
   - 4 spaces are used for all indentation.
   - Try to align assignment operator lines as is done elsewhere (adding space before `=`).
   - Use empty new lines to separate steps or distinct groups of operations.
   - Generally add new lines for each step in loops and for statements. For some single-line ones, they may be compressed into a single line. This saves on space utilization, especially on deeply indented lines.
4. **Variables and Classes.**
   - Variables, functions, and class-like tables follow the snake_case convention.
   - Graphics objects and configuration settings follow PascalCase.
   - Constants follow all-caps SNAKE_CASE and local ones should be declared at the top of files after `require` statements and external ones (like `local ALARM = types.ALARM`).
5. **No `goto`.**
   These are generally frowned upon due to reducing code readability.
6. **Multiple `return`s.**
   These are allowed to minimize code size, but if it is simple to avoid multiple, do so.
7. **Classes and Objects.**
   Review the existing code for examples on how objects are implemented in this project. They do not use Lua's `:` operator and `self` functionality. A manual object-like table definition is used. Some global single-instance classes don't use a `new()` function, such as the [PPM](https://github.com/MikaylaFischler/cc-mek-scada/blob/main/scada-common/ppm.lua). Multi-instance ones do, such as the Supervisor's [unit](https://github.com/MikaylaFischler/cc-mek-scada/blob/main/supervisor/unit.lua) class.

### No AI

Your code should follow the style guide, be succinct, make sense, and you should be able to explain what it does. Random changes done in multiple places will be deemed suspicious along with poor comments or nonsensical code.
Use your contributions as programming practice or to hone your skills; don't automate away thinking.
