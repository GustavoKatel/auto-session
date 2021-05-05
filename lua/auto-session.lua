local Lib = require('auto-session-library')

-- Run comand hooks
local function run_hook_cmds(cmds, hook_name)
  if not Lib.is_empty_table(cmds) then
    for _,cmd in ipairs(cmds) do
      Lib.logger.debug(string.format("Running %s command: %s", hook_name, cmd))
      local success, result = pcall(vim.cmd, cmd)
      if not success then Lib.logger.error(string.format("Error running %s. error: %s", cmd, result)) end
    end
  end
end

----------- Setup ----------
local AutoSession = {
  conf = {}
}

local defaultConf = {
  -- Sets the log level of the plugin (debug, info, error)
  logLevel = vim.g.auto_session_log_level or AutoSession.conf.logLevel or 'info',
  -- Enables/disables the "last session" feature
  auto_session_enable_last_session = vim.g.auto_session_enable_last_session or false,
  -- (internal) last session, do not set unless you absolutely know what you're doing.
  last_session = nil,
  -- Root dir where sessions will be stored
  auto_session_root_dir = vim.fn.stdpath('data').."/sessions/",
  -- Enables/disables auto-session
  auto_session_enabled = true,
  -- Do not load sessions when in these directories
  auto_session_suppress_dirs = vim.g.auto_session_suppress_dirs or {}
}

-- Set default config on plugin load
AutoSession.conf = defaultConf

-- Pass configs to Lib
Lib.conf = {
  logLevel = AutoSession.conf.logLevel
}
Lib.ROOT_DIR = defaultConf.ROOT_DIR

function AutoSession.setup(config)
  AutoSession.conf = Lib.Config.normalize(config, AutoSession.conf)
  Lib.ROOT_DIR = AutoSession.conf.auto_session_root_dir
  Lib.setup({
    logLevel = AutoSession.conf.logLevel
  })
end

-- TODO: finish is_enabled feature
local function is_enabled()
  if vim.g.auto_session_enabled ~= nil then
    return vim.g.auto_session_enabled == Lib._VIM_TRUE
  elseif AutoSession.conf.auto_session_enabled ~= nil then
    return AutoSession.conf.auto_session_enabled
  end

  return true
end

do
  function AutoSession.get_latest_session()
    local dir = vim.fn.expand(AutoSession.conf.auto_session_root_dir)
    local latest_session = { session = nil, last_edited = 0 }

    for _, filename in ipairs(vim.fn.readdir(dir)) do

      local session = AutoSession.conf.auto_session_root_dir..filename
      local last_edited = vim.fn.getftime(session)

      if last_edited > latest_session.last_edited then
        latest_session.session = session
        latest_session.last_edited = last_edited
      end
    end

    -- Need to escape % chars on the filename so expansion doesn't happen
    return latest_session.session:gsub("%%", "\\%%")
  end
end


------ MAIN FUNCTIONS ------
function AutoSession.AutoSaveSession(sessions_dir)
  if is_enabled() then
    if next(vim.fn.argv()) == nil then
      AutoSession.SaveSession(sessions_dir, true)
    end
  end
end

function AutoSession.get_root_dir()
  if AutoSession.valiated then
    return AutoSession.conf.auto_session_root_dir
  end

  local root_dir = vim.g["auto_session_root_dir"] or AutoSession.conf.auto_session_root_dir
  Lib.init_dir(root_dir)

  AutoSession.conf.auto_session_root_dir = Lib.validate_root_dir(root_dir)
  AutoSession.validated = true
  return root_dir
end


function AutoSession.get_cmds(typ)
  return AutoSession.conf[typ.."_cmds"] or vim.g["auto_session_"..typ.."_cmds"]
end

-- Saves the session, overriding if previously existing.
function AutoSession.SaveSession(sessions_dir, auto)
  if Lib.suppress_session(AutoSession.conf.auto_session_suppress_dirs) then
    return
  elseif Lib.is_empty(sessions_dir) then
    sessions_dir = AutoSession.get_root_dir()
  else
    sessions_dir = Lib.append_slash(sessions_dir)
  end

  local pre_cmds = AutoSession.get_cmds("pre_save")
  run_hook_cmds(pre_cmds, "pre-save")

  local session_name = Lib.escaped_session_name_from_cwd()
  local full_path = string.format(sessions_dir.."%s.vim", session_name)
  local cmd = "mks! "..full_path

  if auto then
    Lib.logger.debug("Session saved at "..full_path)
  else
    Lib.logger.info("Session saved at "..full_path)
  end

  vim.cmd(cmd)

  local post_cmds = AutoSession.get_cmds("post_save")
  run_hook_cmds(post_cmds, "post-save")
end

-- This function avoids calling RestoreSession automatically when argv is not nil.
function AutoSession.AutoRestoreSession(sessions_dir)
  if is_enabled() and not Lib.suppress_session(AutoSession.conf.auto_session_suppress_dirs) then
    if next(vim.fn.argv()) == nil then
      AutoSession.RestoreSession(sessions_dir)
    end
  end
end

local function extract_dir_or_file(sessions_dir_or_file)
  local sessions_dir = nil
  local session_file = nil

  if Lib.is_empty(sessions_dir_or_file) then
    sessions_dir = AutoSession.get_root_dir()
  elseif vim.fn.isdirectory(vim.fn.expand(sessions_dir_or_file)) == Lib._VIM_TRUE then
    if not Lib.ends_with(sessions_dir_or_file, '/') then
      sessions_dir = Lib.append_slash(sessions_dir_or_file)
    else
      sessions_dir = sessions_dir_or_file
    end
  else
    session_file = sessions_dir_or_file
  end

  return sessions_dir, session_file
end

-- TODO: make this more readable!
-- Restores the session by sourcing the session file if it exists/is readable.
function AutoSession.RestoreSession(sessions_dir_or_file)
  Lib.logger.debug("sessions dir or file", sessions_dir_or_file)
  local sessions_dir, session_file = extract_dir_or_file(sessions_dir_or_file)

  local restore = function(file_path)
    local pre_cmds = AutoSession.get_cmds("pre_restore")
    run_hook_cmds(pre_cmds, "pre-restore")

    local cmd = "source "..file_path
    vim.cmd(cmd)
    Lib.logger.info("Session restored from "..file_path)

    local post_cmds = AutoSession.get_cmds("post_restore")
    run_hook_cmds(post_cmds, "post-restore")
  end

  -- I still don't like reading this chunk, please cleanup
  if sessions_dir then
    Lib.logger.debug("==== Using session DIR")
    local session_name = Lib.escaped_session_name_from_cwd()
    local session_file_path = string.format(sessions_dir.."%s.vim", session_name)

    local legacy_session_name = Lib.legacy_session_name_from_cwd()
    local legacy_file_path = string.format(sessions_dir.."%s.vim", legacy_session_name)

    if Lib.is_readable(session_file_path) then
      restore(session_file_path)
    elseif Lib.is_readable(legacy_file_path) then
      restore(legacy_file_path)
    else
      if AutoSession.conf.auto_session_enable_last_session then
        local last_session_file_path = AutoSession.get_latest_session()
        Lib.logger.info("Restoring last session", last_session_file_path)
        restore(last_session_file_path)
      else
        Lib.logger.debug("File not readable, not restoring session")
      end
    end
  elseif session_file then
    Lib.logger.debug("==== Using session FILE")
    local escaped_file = session_file:gsub("%%", "\\%%")
    if Lib.is_readable(escaped_file) then
      Lib.logger.debug("isReadable, calling restore")
      restore(escaped_file)
    else
      Lib.logger.debug("File not readable, not restoring session")
    end
  else
    Lib.logger.error("Error while trying to parse session dir or file")
  end
end

function AutoSession.DeleteSession(file_path)
  Lib.logger.debug("session_file_path", file_path)

  local pre_cmds = AutoSession.get_cmds("pre_delete")
  run_hook_cmds(pre_cmds, "pre-delete")

  -- TODO: make the delete command customizable
  local cmd = "silent! !rm "

  if file_path then
    local escaped_file_path = file_path:gsub("%%", "\\%%")
    vim.cmd(cmd..escaped_file_path)
    Lib.logger.info("Deleted session "..file_path)
  else
    local session_name = Lib.escaped_session_name_from_cwd()
    local session_file_path = string.format(AutoSession.get_root_dir().."%s.vim", session_name)

    vim.cmd(cmd..session_file_path)
    Lib.logger.info("Deleted session "..session_file_path)
  end

  local post_cmds = AutoSession.get_cmds("post_delete")
  run_hook_cmds(post_cmds, "post-delete")
end

return AutoSession
