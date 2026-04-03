local _ = require("gettext")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Tailscale = WidgetContainer:extend{
    name = "tailscale",
}

local BIN_DIR = "/mnt/us/extensions/tailscale/bin"
local TAILSCALE_BIN = BIN_DIR .. "/tailscale"
local START_SCRIPT = BIN_DIR .. "/start_tailscale.sh"
local STOP_SCRIPT = BIN_DIR .. "/stop_tailscale.sh"
local START_LOG = BIN_DIR .. "/tailscale_start_log.txt"
local STOP_LOG = BIN_DIR .. "/tailscale_stop_log.txt"

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function trim(text)
    if not text then
        return ""
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", [['"'"']]) .. "'"
end

local function read_command(command)
    local handle = io.popen(command .. " 2>/dev/null")
    if not handle then
        return ""
    end
    local output = handle:read("*a")
    handle:close()
    return trim(output)
end

local function command_succeeds(command)
    local handle = io.popen(command .. " >/dev/null 2>&1; printf %s $?")
    if not handle then
        return false
    end
    local output = handle:read("*a")
    handle:close()
    return trim(output) == "0"
end

function Tailscale:init()
    self.ui.menu:registerToMainMenu(self)
end

function Tailscale:isInstalled()
    return file_exists(TAILSCALE_BIN) and file_exists(START_SCRIPT) and file_exists(STOP_SCRIPT)
end

function Tailscale:getConnectedIPs()
    if not file_exists(TAILSCALE_BIN) then
        return ""
    end
    return read_command(shell_quote(TAILSCALE_BIN) .. " ip")
end

function Tailscale:getBackendState()
    if not file_exists(TAILSCALE_BIN) then
        return ""
    end
    return read_command(
        shell_quote(TAILSCALE_BIN)
            .. " status --json | tr -d '\\n' | sed -n 's/.*\"BackendState\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p'"
    )
end

function Tailscale:isConnected()
    return self:getBackendState() == "Running"
end

function Tailscale:getIPs()
    if not self:isConnected() then
        return ""
    end
    return self:getConnectedIPs()
end

function Tailscale:getStatusText()
    if not self:isInstalled() then
        return _("Tailscale extension not found in /mnt/us/extensions/tailscale.")
    end

    if self:isConnected() then
        local ips = self:getIPs()
        if ips ~= "" then
            return string.format(_("Connected\n%s"), ips)
        end
        return _("Connected")
    end

    local backend_state = self:getBackendState()
    if backend_state ~= "" then
        return string.format(_("Not connected\nBackend state: %s"), backend_state)
    end

    return _("Not connected")
end

function Tailscale:showMessage(text)
    UIManager:show(InfoMessage:new{
        text = text,
    })
end

function Tailscale:showNotice(text)
    UIManager:show(Notification:new{
        text = text,
    })
end

function Tailscale:runScript(script_path, success_text, failure_text)
    if not file_exists(script_path) then
        self:showMessage(_("Required Tailscale script is missing."))
        return
    end

    local ok = command_succeeds("/bin/sh " .. shell_quote(script_path))
    if ok then
        self:showNotice(success_text)
    else
        self:showMessage(failure_text)
    end
end

function Tailscale:connect()
    self:runScript(
        START_SCRIPT,
        _("Tailscale connect command finished."),
        string.format(_("Tailscale connect failed. Check %s."), START_LOG)
    )
end

function Tailscale:disconnect()
    self:runScript(
        STOP_SCRIPT,
        _("Tailscale disconnect command finished."),
        string.format(_("Tailscale disconnect failed. Check %s."), STOP_LOG)
    )
end

function Tailscale:showStatus()
    local text = self:getStatusText()
    if not self:isConnected() and self:isInstalled() then
        text = text .. "\n\n" .. _("If connect keeps failing, make sure tailscaled is already running.")
    end
    self:showMessage(text)
end

function Tailscale:addToMainMenu(menu_items)
    menu_items.tailscale = {
        text = _("Tailscale"),
        sorting_hint = "network",
        checked_func = function()
            return self:isConnected()
        end,
        sub_item_table = {
            {
                text_func = function()
                    if self:isConnected() then
                        return _("Status: Connected")
                    end
                    return _("Status: Disconnected")
                end,
                keep_menu_open = true,
                callback = function()
                    self:showStatus()
                end,
            },
            {
                text = _("Connect"),
                callback = function()
                    self:connect()
                end,
            },
            {
                text = _("Disconnect"),
                callback = function()
                    self:disconnect()
                end,
            },
        },
    }
end

return Tailscale
