local plugin_name = 'nvim-visual-eof-lua'
local options
local ns
local init = false

local DEFAULT_OPTIONS = {
  -- text for EOL
  text_EOL        = ' ⏎';

  -- text for absence of EOL
  text_NOEOL      = ' ✗⏎';

  -- highlight group name for EOL
  hl_EOL          = 'VisualEOL';

  -- highlight group name for absence of EOL
  hl_NOEOL        = 'VisualNoEOL';

  -- no setup autocmd
  -- ( you can setup_autocmd() alone )
  no_autocmd      = false;

  -- exclude listed ft regex of buffer
  -- regex is lua standard one
  ft_ng           = {
    'startify',
    'nerdtree',
    'fern',
    'fugitive.*',
    'git.*',
    'gina.*',
  };

  -- Used after ft_ng filtering
  buf_filter      = function(bufnr)
    return true
  end;
}

local function is_buf_auto_eol(bufnr)
  if not vim.api.nvim_buf_get_option(bufnr, 'eol')
      and (
        vim.api.nvim_buf_get_option(bufnr, 'binary')
        or not vim.api.nvim_buf_get_option(bufnr, 'fixeol')
      ) then
    return false
  end

  -- Vim saves zero byte file if there's no line.
  local lc = vim.fn.getbufinfo(bufnr)[1].linecount
  if lc == 1 and vim.fn.getbufline(bufnr, 1)[1] == '' then
    return false
  end

  return true
end

-- is buf saved to a real file as shown in buffer?
local function is_buf_saved(bufnr)
  local changed = vim.fn.getbufinfo(bufnr)[1].changed == 1
  if changed then
    return false
  end

  if vim.api.nvim_buf_get_option(bufnr, 'buftype') ~= '' then
    return false
  end

  local bufname = vim.fn.bufname(bufnr)
  if vim.fn.filereadable(bufname) == 1 then
    return true
  end

  return false
end

-- eol at eof?
---- buffer is saved to file: file status
---- buffer is not saved: when buffer is saved as a file
local function buf_eoftype(bufnr)
  if is_buf_saved(bufnr) then
    bufname = vim.fn.bufname(bufnr)
    local lc = vim.fn.getbufinfo(bufnr)[1].linecount
    return #vim.fn.readfile(bufname, 'b') ~= lc
  else
    return is_buf_auto_eol(bufnr)
  end
end

local function check_buf(bufnr)
  ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')

  for i, ng_pat in ipairs(options.ft_ng) do
    if ft:match(ng_pat) then
      return false
    end
  end

  if not options.buf_filter(bufnr) then
    return false
  end

  return true
end

local function clean_buf(bufnr)
  if not init then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

local function redraw_buf(bufnr)
  if not init then
    echo_error('Do setup() first.')
    return
  end

  local line_cnt = vim.fn.line('$')
  local lc = vim.fn.getbufinfo(bufnr)[1].linecount
  local name = vim.fn.bufname(bufnr)
  local eoftype = buf_eoftype(bufnr)

  local text = options.text_EOL
  local hl_name = options.hl_EOL
  if not eoftype then
    text = options.text_NOEOL
    hl_name = options.hl_NOEOL
  end
  if text == '' then
    return
  end
  vim.api.nvim_buf_set_virtual_text(
    bufnr,
    ns,
    lc - 1,
    {{text, hl_name}},
    {}
  )
end

local function echo_error(msg)
  local cmd = vim.api.nvim_command
  cmd('echohl Error')
  cmd(string.format(
    'echomsg "[%s] %s"',
    plugin_name,
    msg
  ))
  cmd('echohl None')
end

local function make_option(default, extend)
  local res = {}

  for k, v in pairs(default) do
    res[k] = v
  end

  for k, v in pairs(extend) do
    if res[k] == nil then
      echo_error(string.format(
        "Unknown option '%s'.",
        k
      ))
    else
      if type(res[k]) == type(v) then
        res[k] = v
      else
        echo_error(string.format(
          "Provide %s for option '%s'.",
          type(res[k]),
          k
        ))
      end
    end
  end

  return res
end

local augroup_cnt = 0
local function augroup(fn)
  augroup_cnt = augroup_cnt + 1
  local group_name = string.format('%s_internal_%d', plugin_name, augroup_cnt)
  local cmd = vim.api.nvim_command
  cmd(string.format('augroup %s', group_name))
  cmd('autocmd!')
  fn()
  cmd('augroup END')
  return group_name
end

local function hl_default()
  local cmd = vim.api.nvim_command
  cmd(string.format(
    'highlight default %s ctermfg=LightGreen guifg=LightGreen',
    options.hl_EOL
  ))
  cmd(string.format(
    'highlight default %s ctermfg=Red guifg=Red',
    options.hl_NOEOL
  ))
end

local function setup_autocmd()
  local cmd = vim.api.nvim_command
  redraw_vim = string.format(
    'lua %s; if (vim.fn.getcmdwintype() == \'\' and (%s)) then %s end',
    'require"visual-eof".clean_buf(vim.fn.bufnr())',
    'require"visual-eof".check_buf(vim.fn.bufnr())',
    'require"visual-eof".redraw_buf(vim.fn.bufnr())'
  )
  hl_def_vim = string.format(
    'lua %s',
    'require"visual-eof".hl_default()'
  )
  group_name = augroup(function()
    cmd(string.format(
      'autocmd %s %s %s',
      'TextChanged,TextChangedI,TextChangedP,BufWritePost,BufWinEnter',
      '*',
      redraw_vim
    ))
    cmd(string.format(
      'autocmd %s %s %s',
      'OptionSet',
      'endofline,fixendofline,binary',
      redraw_vim
    ))
    cmd(string.format(
      'autocmd %s %s %s',
      'ColorScheme',
      '*',
      hl_def_vim
    ))
  end)
  return group_name
end

local function setup(user_options)
  init = true
  options = make_option(DEFAULT_OPTIONS, user_options or {})
  ns = vim.api.nvim_create_namespace(plugin_name)

  hl_default()

  redraw_buf(vim.fn.bufnr())
  setup_autocmd(ns)
end

return {
  setup = setup;
  setup_autocmd = setup_autocmd;
  clean_buf = clean_buf;
  redraw_buf = redraw_buf;

  -- internal
  check_buf = check_buf;
  hl_default = hl_default;
}
