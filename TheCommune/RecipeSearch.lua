local _, TC = ...
local aliases = {}
for category, words in pairs({
    bag="bag bags container containers pouch pouches satchel satchels pack backpack backpacks quiver quivers",
    sword="sword swords blade blades",
    mace="mace maces hammer hammers maul mauls",
    axe="axe axes hatchet hatchets",
    dagger="dagger daggers",
    staff="staff staffs staves",
    bow="bow bows",
    shield="shield shields",
    weapon="weapon weapons",
}) do
    for word in words:gmatch("%S+") do aliases[word] = category end
end

-- Game item class/subclass IDs keep English keyword aliases useful across locales.
local weapons = {[0]="axe",[1]="axe",[2]="bow",[4]="mace",[5]="mace",[7]="sword",[8]="sword",[10]="staff",[15]="dagger"}
local outputs, pendingItems = {}, {}

function TC.RecipeOutputDataReceived(id)
    if not id or not pendingItems[id] then return false end
    pendingItems[id] = nil
    TC.InvalidateRecipeSearch()
    return true
end

local function WaitForItem(itemID)
    if not pendingItems[itemID] then
        pendingItems[itemID] = true
        TC.ItemName(itemID)
    end
end

local function Output(recipeID, spellName)
    if outputs[recipeID] then return outputs[recipeID] end
    local api = C_TradeSkillUI
    local itemID
    if api and api.GetRecipeSchematic then
        local ok, schematic = pcall(api.GetRecipeSchematic, recipeID, false)
        if ok and type(schematic)=="table" then itemID = schematic.outputItemID end
    end
    if not itemID and api and api.GetRecipeItemLink then
        local ok, link = pcall(api.GetRecipeItemLink, recipeID)
        if ok and type(link)=="string" then itemID = tonumber(link:match("item:(%d+)")) end
    end
    if not TC.Integer(itemID,1,2147483647) or not C_Item or not C_Item.GetItemInfoInstant then return end
    local ok, id, kind, subtype, _, _, class, subclass = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or not id then
        WaitForItem(itemID)
        return
    end
    local category
    if class==1 or (class==6 and subclass==2) or (class==6 and subclass==3) then category="bag"
    elseif class==2 then category=weapons[subclass]
    elseif class==4 and subclass==6 then category="shield" end
    local name = C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
    local output = {category=category, weapon=class==2, text=table.concat({name or spellName,kind or "",subtype or ""}," "):lower()}
    if name then
        outputs[recipeID]=output
    else
        WaitForItem(itemID)
    end
    return output
end

function TC.RecipeMatches(query, text, spellName, recipeID)
    if query=="" or text:find(query,1,true) then return true end
    local category=aliases[query]
    local output=Output(recipeID,spellName)
    if output and (output.text:find(query,1,true) or
        (category and (output.category==category or (category=="weapon" and output.weapon)))) then return true end
    if category and not output then
        for word in spellName:lower():gmatch("%a+") do
            if aliases[word]==category then return true end
        end
    end
    return false
end
