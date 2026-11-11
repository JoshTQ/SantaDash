--[[
	Where the HUD goes on small and touch screens. Pure maths so it runs in
	tests.

	The top row (stats 250 + stop 300 + noise 240 px, plus margins) needs
	about 860 px; a landscape phone has 640-930, so the row overlapped on
	most phones. Below that width the whole HUD scales down (never under
	MinScale, so buttons stay tappable). On touch screens Roblox puts its
	thumbstick bottom-left and the jump button bottom-right, so nothing of
	ours may sit in those corners.
]]

local HudLayout = {}

HudLayout.DesignWidth = 860 -- px the top row needs at scale 1
HudLayout.DesignHeight = 560 -- px the tallest stack needs (results panel + margins)
HudLayout.MinScale = 0.6

-- UIScale for a viewport (nil viewport: 1).
function HudLayout.scale(viewport: Vector2?): number
	if not viewport or viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end
	local s = math.min(1, viewport.X / HudLayout.DesignWidth, viewport.Y / HudLayout.DesignHeight)
	return math.max(HudLayout.MinScale, s)
end

-- One column under the stop timer: the map event chip, body heat, banners
-- and first-time tips stack in this order and only take room while shown,
-- so none of them can cover another (Hud.client builds it, Tips.client
-- puts its card in it).
HudLayout.TopStack = {
	name = "TopStack",
	y = 98, -- px from the top: just under the 84 px stop panel at y 8
	width = 560,
	order = { event = 1, heat = 2, banner = 3, tip = 4 },
}

export type Spots = { snow: UDim2, quit: UDim2 }

-- Positions for the controls that would otherwise sit under the touch
-- thumbstick (quit) or the jump button (throw).
function HudLayout.spots(touch: boolean): Spots
	return {
		-- Snowballs: bottom-right on keyboard; above the jump button on touch.
		snow = if touch then UDim2.new(1, -12, 1, -260) else UDim2.new(1, -12, 1, -110),
		-- Back to hub: under the stats panel (top-left) everywhere, so a thumb
		-- on the stick never quits the run.
		quit = UDim2.fromOffset(12, 112),
	}
end

return HudLayout
