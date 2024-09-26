local log            = require("scada-common.log")
local util           = require("scada-common.util")

local docs           = require("pocket.ui.docs")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local ListBox        = require("graphics.elements.ListBox")
local TextBox        = require("graphics.elements.TextBox")

local PushButton     = require("graphics.elements.controls.PushButton")

local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")
local LED            = require("graphics.elements.indicators.LED")

local ALIGN = core.ALIGN
local cpair = core.cpair

local DOC_TYPE = docs.DOC_ITEM_TYPE
local LIST_TYPE = docs.DOC_LIST_TYPE

-- new guide documentation section
---@param data { [1]: pocket_app, [2]: Div, [3]: Div[], [4]: { [string]: function }, [5]: [ string, string, string, function ][], [6]: cpair, [7]: cpair }
---@param base_page nav_tree_page
---@param title string
---@param items table
---@param scroll_height integer
---@return nav_tree_page
return function (data, base_page, title, items, scroll_height)
    local app, page_div, panes, doc_map, search_db, btn_fg_bg, btn_active = data[1], data[2], data[3], data[4], data[5], data[6], data[7]

    local section_page = app.new_page(base_page, #panes + 1)
    local section_div = Div{parent=page_div,x=2}
    table.insert(panes, section_div)
    TextBox{parent=section_div,y=1,text=title,alignment=ALIGN.CENTER}
    PushButton{parent=section_div,x=3,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=base_page.nav_to}

    local view_page = app.new_page(section_page, #panes + 1)
    local section_view_div = Div{parent=page_div,x=2}
    table.insert(panes, section_view_div)
    TextBox{parent=section_view_div,y=1,text=title,alignment=ALIGN.CENTER}
    PushButton{parent=section_view_div,x=3,y=1,text="<",fg_bg=btn_fg_bg,active_fg_bg=btn_active,callback=section_page.nav_to}

    local name_list = ListBox{parent=section_div,x=1,y=3,scroll_height=60,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}
    local def_list = ListBox{parent=section_view_div,x=1,y=3,scroll_height=scroll_height,nav_fg_bg=cpair(colors.lightGray,colors.gray),nav_active=cpair(colors.white,colors.gray)}

    local sect_id = 1
    local page_end

    for i = 1, #items do
        local item = items[i] ---@type pocket_doc_sect|pocket_doc_subsect|pocket_doc_text|pocket_doc_list

        if item.type == DOC_TYPE.SECTION then
            ---@cast item pocket_doc_sect

            local title_text = sect_id.."."
            local title_offs = string.len(title_text) + 2

            local sect_title = Div{parent=def_list,height=1}
            TextBox{parent=sect_title,x=1,text=title_text,fg_bg=cpair(colors.lightGray,colors.black)}
            local anchor = TextBox{parent=sect_title,x=title_offs,y=1,text=item.name,anchor=true,fg_bg=cpair(colors.green,colors.black)}

            page_end = Div{parent=def_list,height=1,can_focus=true}

            local function view()
                page_end.focus()
                view_page.nav_to()
                anchor.focus()
            end

            if #name_list.get_children() > 0 then
                local _ = Div{parent=name_list,height=1}
            end

            local name_title = Div{parent=name_list,height=1}
            TextBox{parent=name_title,x=1,text=title_text,fg_bg=cpair(colors.lightGray,colors.black)}
            PushButton{parent=name_title,x=title_offs,y=1,text=item.name,alignment=ALIGN.LEFT,fg_bg=cpair(colors.green,colors.black),active_fg_bg=btn_active,callback=view}

            sect_id = sect_id + 1
        elseif item.type == DOC_TYPE.SUBSECTION then
            ---@cast item pocket_doc_subsect

            local anchor = TextBox{parent=def_list,text=item.name,anchor=true,fg_bg=cpair(colors.blue,colors.black)}

            if item.subtitle then
                TextBox{parent=def_list,text=item.subtitle,fg_bg=cpair(colors.gray,colors.black)}
            end

            TextBox{parent=def_list,text=item.body}

            page_end = Div{parent=def_list,height=1,can_focus=true}

            local function view()
                page_end.focus()
                view_page.nav_to()
                anchor.focus()
            end

            doc_map[item.key] = view
            table.insert(search_db, { string.lower(item.name), item.name, title, view })

            local name_entry = Div{parent=name_list,height=#util.strwrap(item.name,name_list.get_width()-3)}
            TextBox{parent=name_entry,x=1,text="\x10",fg_bg=cpair(colors.gray,colors.black)}
            PushButton{parent=name_entry,x=3,y=1,text=item.name,alignment=ALIGN.LEFT,fg_bg=cpair(colors.blue,colors.black),active_fg_bg=btn_active,callback=view}
        elseif item.type == DOC_TYPE.TEXT then
            ---@cast item pocket_doc_text

            TextBox{parent=def_list,text=item.text}

            page_end = Div{parent=def_list,height=1,can_focus=true}
        elseif item.type == DOC_TYPE.LIST then
            ---@cast item pocket_doc_list

            local container = Div{parent=def_list,height=#item.items}

            if item.list_type == LIST_TYPE.BULLET then
                for _, li in ipairs(item.items) do
                    TextBox{parent=container,x=2,text="\x07 "..li}
                end
            elseif item.list_type == LIST_TYPE.NUMBERED then
                local width = string.len("" .. #item.items)
                for idx, li in ipairs(item.items) do
                    TextBox{parent=container,x=2,text=util.sprintf("%" .. width .. "d. %s", idx, li)}
                end
            elseif item.list_type == LIST_TYPE.INDICATOR then
                for idx, li in ipairs(item.items) do
                    local _ = IndicatorLight{parent=container,x=2,label=li,colors=cpair(colors.black,item.colors[idx])}
                end
            elseif item.list_type == LIST_TYPE.LED then
                for idx, li in ipairs(item.items) do
                    local _ = LED{parent=container,x=2,label=li,colors=cpair(colors.black,item.colors[idx])}
                end
            end

            page_end = Div{parent=def_list,height=1,can_focus=true}
        end

        if i % 12 == 0 then util.nop() end
    end

    log.debug("guide section " .. title .. " generated with final height ".. page_end.get_y())

    util.nop()

    return section_page
end
