local core       = require("graphics.core")

local Div        = require("graphics.elements.div")
local ListBox    = require("graphics.elements.listbox")
local TextBox    = require("graphics.elements.textbox")

local PushButton = require("graphics.elements.controls.push_button")

local ALIGN = core.ALIGN
local cpair = core.cpair

-- new guide documentation section
---@param data _guide_section_constructor_data
---@param base_page nav_tree_page
---@param title string
---@param items table
---@param scroll_height integer
---@return nav_tree_page
return function (data, base_page, title, items, scroll_height)
    local app, page_div, panes, doc_map, search_map, btn_fg_bg, btn_active = table.unpack(data)

    local section_page = app.new_page(base_page, #panes + 1)
    local section_div = Div{parent=page_div,x=2}
    table.insert(panes, section_div)
    TextBox{parent=section_div,y=1,text=title,height=1,alignment=ALIGN.CENTER}
    PushButton{parent=section_div,x=3,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=base_page.nav_to}

    local gls_term_view_page = app.new_page(section_page, #panes + 1)
    local section_view_div = Div{parent=page_div,x=2}
    table.insert(panes, section_view_div)
    TextBox{parent=section_view_div,y=1,text=title,height=1,alignment=ALIGN.CENTER}
    PushButton{parent=section_view_div,x=3,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=section_page.nav_to}

    local name_list = ListBox{parent=section_div,x=1,y=3,scroll_height=30,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
    local def_list = ListBox{parent=section_view_div,x=1,y=3,scroll_height=scroll_height,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

    local _end = nil

    for i = 1, #items do
        local item = items[i] ---@type pocket_doc_item

        local anchor = TextBox{parent=def_list,text=item.name,anchor=true,fg_bg=cpair(colors.blue,colors.black)}
        TextBox{parent=def_list,text=item.desc}
        _end = Div{parent=def_list,height=1,can_focus=true}

        local function view()
            _end.focus()
            gls_term_view_page.nav_to()
            anchor.focus()
        end

        doc_map[item.key] = view
        search_map[item.name] = view

        PushButton{parent=name_list,text=item.name,fg_bg=cpair(colors.blue,colors.black),active_fg_bg=btn_active,callback=view}
    end

    return section_page
end
