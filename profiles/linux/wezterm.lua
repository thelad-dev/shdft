local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "Grape"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 11.0
config.window_background_opacity = 0.92
-- Linux counterpart to Windows `win32_system_backdrop = "Acrylic"`.
config.wayland_window_background_blur = true
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
-- Windows uses RESIZE (no title bar). On Wayland the same flag forces
-- Smithay's client-side fallback frame (min/max/close button strip).
-- NONE matches that borderless look; KWin still moves/resizes the window.
if os.getenv("WAYLAND_DISPLAY") then
	config.window_decorations = "NONE"
else
	config.window_decorations = "RESIZE"
end

-- Report modified keys (Shift+Enter, Ctrl+Enter) distinctly to herdr and Claude Code.
-- Backspace and Delete stay the classic bytes. Once an app enables the kitty
-- protocol, WezTerm otherwise sends CSI 127 u and CSI 3;1 ~, which do not delete.
config.enable_kitty_keyboard = true
config.keys = {
	{ key = "Backspace", mods = "NONE", action = wezterm.action.SendString("\x7f") },
	{ key = "Backspace", mods = "SHIFT", action = wezterm.action.SendString("\x7f") },
	{ key = "Delete", mods = "NONE", action = wezterm.action.SendString("\x1b[3~") },
}

-- Konsole habits: middle click pastes, also inside herdr (which captures the mouse).
config.mouse_bindings = {
	{ event = { Down = { streak = 1, button = "Middle" } }, mods = "NONE", action = wezterm.action.PasteFrom("Clipboard"), mouse_reporting = false },
	{ event = { Down = { streak = 1, button = "Middle" } }, mods = "NONE", action = wezterm.action.PasteFrom("Clipboard"), mouse_reporting = true },
}

-- Only the first window at startup attaches to herdr; after detaching, it stays in a login shell.
wezterm.on("gui-startup", function(cmd)
	if cmd and cmd.args then
		wezterm.mux.spawn_window(cmd)
		return
	end
	local _, _, window = wezterm.mux.spawn_window({
		args = { "bash", "-lc", "cd ~ && herdr; exec bash -l" },
	})
	-- No title/button bar, so the herdr window opens maximized.
	window:gui_window():maximize()
end)

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.5, brightness = 0.65 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.82

-- get_config_overrides() hands back a copy, so the current value is never the
-- same table we last stored; compare the fields instead of the identity.
local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	-- Only write when one of the two values we own actually changes; a redundant
	-- set_config_overrides() call would trigger another config reload.
	if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

return config
