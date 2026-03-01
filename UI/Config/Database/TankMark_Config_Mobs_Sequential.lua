-- TankMark: v0.23
-- File: TankMark_Config_Mobs_Sequential.lua
-- Sequential marking functionality

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- SEQUENTIAL MARKING HELPERS
-- ==========================================================

-- Refresh the sequential marks scroll frame display
function TankMark:RefreshSequentialRows()
	if not TankMark.sequentialScrollFrame then return end
	
	local numMarks = L._tgetn(TankMark.editingSequentialMarks)
	
	if numMarks == 0 then
		-- Hide all sequential rows when empty
		for i = 1, 4 do
			if TankMark.sequentialRows[i] then
				TankMark.sequentialRows[i]:Hide()
			end
		end
		TankMark.sequentialScrollFrame:Hide()
		
		-- Show instructional text if accordion is expanded
		if TankMark.sequentialEmptyText and TankMark.isSequentialExpanded then
			TankMark.sequentialEmptyText:Show()
		end
		
		return
	end
	
	-- Hide instructional text when marks exist
	if TankMark.sequentialEmptyText then
		TankMark.sequentialEmptyText:Hide()
	end
	
	TankMark.sequentialScrollFrame:Show()
	
	local scrollChild = TankMark.sequentialScrollFrame:GetScrollChild()
	if scrollChild then
		scrollChild:Show()
	end
	
	-- Update scroll range (max 4 visible rows)
	local visibleRows = 4
	FauxScrollFrame_Update(TankMark.sequentialScrollFrame, numMarks, visibleRows, 24)
	local offset = FauxScrollFrame_GetOffset(TankMark.sequentialScrollFrame)
	
	-- Force visibility after FauxScrollFrame_Update
	TankMark.sequentialScrollFrame:Show()
	if scrollChild then
		scrollChild:Show()
	end
	
	-- Update visible rows (max 4)
	for i = 1, 4 do
		local dataIndex = offset + i
		local row = TankMark.sequentialRows[i]
		
		if dataIndex <= numMarks then
			local seqData = TankMark.editingSequentialMarks[dataIndex]
			row:Show()
			
			-- Update row number (dataIndex + 1 because main row is #1)
			row.number:SetText("|cff888888#" .. (dataIndex + 1) .. "|r")
			
			-- Update icon
			TankMark:SetIconTexture(row.iconBtn.tex, seqData.icon)
			
			-- Update CC button
			if seqData.class then
				row.ccBtn:SetText(seqData.class)
				row.ccBtn:SetTextColor(0, 1, 0)
			else
				row.ccBtn:SetText("No CC")
				row.ccBtn:SetTextColor(1, 0.82, 0)
			end
			
			-- Store dataIndex for delete button
			row.dataIndex = dataIndex
		else
			row:Hide()
		end
	end
end

-- Add a new sequential mark row
function TankMark:OnAddMoreMarksClicked()
	-- Check limit: max 7 additional marks (8 total)
	if L._tgetn(TankMark.editingSequentialMarks) >= 7 then
		TankMark:Print("|cffff0000Error:|r Maximum 8 marks total (1 main + 7 additional).")
		return
	end
	
	-- v0.23: Reset IGNORE to SKULL when adding sequential marks
	if TankMark.selectedIcon == 0 then
		TankMark.selectedIcon = 8
		if TankMark.iconBtn and TankMark.iconBtn.tex then
			TankMark:SetIconTexture(TankMark.iconBtn.tex, 8)
		end
		if TankMark.editPrio then
			TankMark.editPrio:SetText("1")  -- Reset priority from 9 to 1
		end
		TankMark:UpdateClassButton()
	end
	
	-- Add new entry
	L._tinsert(TankMark.editingSequentialMarks, {
		icon = 8,  -- Default to SKULL
		class = nil,
		type = "KILL"
	})
	
	TankMark:RefreshSequentialRows()
	
	-- Disable Lock button when sequential marks exist
	if TankMark.lockBtn then
		TankMark.lockBtn:Disable()
		TankMark.lockBtn:SetText("|cff888888Lock Mark|r")  -- Gray text
	end
end

-- Remove a sequential mark row by index
function TankMark:RemoveSequentialRow(index)
	L._tremove(TankMark.editingSequentialMarks, index)
	TankMark:RefreshSequentialRows()
	
	-- Re-enable Lock button if no sequential marks remain
	if L._tgetn(TankMark.editingSequentialMarks) == 0 and TankMark.lockBtn then
		TankMark.lockBtn:Enable()
		TankMark.lockBtn:SetText("Lock Mark")  -- Reset normal text
	end
end
