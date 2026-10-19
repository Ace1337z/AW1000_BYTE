module("luci.controller.modeminfo", package.seeall)

function index()
    -- Create a new entry under the "Modem" section
    entry({"admin", "modem", "modeminfo"}, call("action_modeminfo"), _("Modem Info"), 20).dependent = false
    entry({"admin", "modem", "modeminfo", "get_info"}, call("get_modem_info")).dependent = false  -- New endpoint for AJAX
    entry({"admin", "modem", "modeminfo", "set_refresh"}, call("set_refresh")).dependent = false
    entry({"admin", "modem", "modeminfo", "get_ports_info"}, call("get_ports_info")).dependent = false
    entry({"admin", "modem", "modeminfo", "save_port"}, call("save_port")).dependent = false
end

function action_modeminfo()
    local uci = require "luci.model.uci".cursor()

    -- Read modem info from the file
    local modeminfo = {}
    local file = io.open("/tmp/modeminfo", "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^(.-):%s*(.*)$")
            if key and value then
                modeminfo[key] = value
            end
        end
        file:close()
    end

    -- Get refresh interval from uci (default is 5 seconds)
    local refresh_rate = uci:get("modeminfo", "settings", "refresh_rate") or "5"

    -- Get the saved communication port from UCI
    local saved_comm = uci:get("modeminfo", "settings", "comm") or "/dev/ttyUSB3"

    -- Render the template and pass saved_comm
    luci.template.render("modeminfo", {modeminfo = modeminfo, refresh_rate = refresh_rate, saved_comm = saved_comm})
end

function get_ports_info()
    local available_ports = {}
    local fs = require "nixio.fs"
    local uci = require "luci.model.uci".cursor()

    -- List all /dev/ttyUSB* files
    for file in fs.dir("/dev") do
        if file:match("^ttyUSB%d+$") or file:match("^ttyACM%d+$") then
            available_ports[#available_ports + 1] = "/dev/" .. file
        end
    end

    -- Get the saved communication port from UCI or default to /dev/ttyUSB3
    local saved_comm = uci:get("modeminfo", "settings", "comm") or "/dev/ttyUSB3"

    -- Return the available ports and the saved port as JSON
    luci.http.prepare_content("application/json")
    luci.http.write_json({ports = available_ports, default_port = saved_comm})
end


function save_port()
    local uci = require "luci.model.uci".cursor()
    local http = require "luci.http"
    
    -- Get the selected commport from the form submission
    local selected_port = http.formvalue("commport")
    
    -- Log selected port
    luci.sys.exec("logger -t modeminfo 'Attempting to save selected comm port: " .. (selected_port or "None") .. "'")
    
    if selected_port then
        -- Check if the 'settings' section exists, and create it if necessary
        if not uci:get("modeminfo", "settings") then
            luci.sys.exec("logger -t modeminfo 'Settings section does not exist, creating it'")
            uci:section("modeminfo", "settings", "settings")
        end

        -- Save the selected port to /etc/config/modeminfo as option comm
        luci.sys.exec("logger -t modeminfo 'Saving selected port: " .. selected_port .. "'")
        uci:set("modeminfo", "settings", "comm", selected_port)

        -- Commit the changes to the UCI system
        uci:commit("modeminfo")
        luci.sys.exec("logger -t modeminfo 'Committed selected port: " .. selected_port .. "'")
    else
        -- Log an error if no port was selected
        luci.sys.exec("logger -t modeminfo 'Error: No comm port selected'")
    end

    -- Redirect back to the modem info page
    luci.http.redirect(luci.dispatcher.build_url("admin/modem/modeminfo"))
end


function update_cron(refresh_rate)
    -- Remove existing cron job for modeminfo
    luci.sys.call("crontab -l | grep -v '/usr/bin/modeminfo' | crontab -")
    
    -- Add new cron job with the selected refresh rate
    if refresh_rate then
        local cron_job = "*/" .. refresh_rate .. " * * * * /bin/bash /usr/bin/modeminfo > /dev/null 2>&1"
        luci.sys.call(string.format('(crontab -l ; echo "%s") | crontab -', cron_job))
    end
end

function set_refresh()
    local uci = require "luci.model.uci".cursor()
    local http = require "luci.http"
    
    -- Get the selected refresh rate from the form
    local refresh_rate = http.formvalue("refresh_rate")

    -- Log the refresh rate for debugging
    luci.sys.exec("logger -t modeminfo 'Attempting to save refresh rate: " .. (refresh_rate or "None") .. "'")
    
    -- Update UCI settings
    if refresh_rate then
        uci:set("modeminfo", "settings", "refresh_rate", refresh_rate)
        uci:commit("modeminfo")

        -- Log success
        luci.sys.exec("logger -t modeminfo 'Saved refresh rate: " .. refresh_rate .. "'")
    else
        -- Log an error if no refresh rate was selected
        luci.sys.exec("logger -t modeminfo 'Error: No refresh rate selected'")
    end

    -- Redirect back to the modem info page to apply the new refresh rate
    luci.http.redirect(luci.dispatcher.build_url("admin/modem/modeminfo"))
end


function get_modem_info()
    -- Run the modem info script and capture the output
    luci.sys.call("/bin/bash /usr/bin/modeminfo")

    -- Read the modem info from /tmp/modeminfo and return it as JSON
    local modeminfo = {}
    local file = io.open("/tmp/modeminfo", "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^(.-):%s*(.*)$")
            if key and value then
                modeminfo[key] = value
            end
        end
        file:close()
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(modeminfo)
end

