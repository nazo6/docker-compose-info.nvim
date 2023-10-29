local setted_up = false
local curl = require "plenary.curl"

local api_cache = {}

local function get_image_info_of_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  ---@type table<number, {user: string|nil,name: string, tag: string|nil}>
  local info = {}

  for i, line in ipairs(lines) do
    local trimmed = line:gsub("^%s*(.-)%s*$", "%1")
    if trimmed:sub(1, #"image:") == "image:" then
      local image = trimmed:sub(#"image:" + 1)
      local image_trimmed = image:gsub("^%s*(.-)%s*$", "%1")
      local image_split = vim.split(image_trimmed, ":")
      local tag = image_split[2]
      local image_name = image_split[1]
      local user, name = image_name:match "^(.-)/(.*)$"
      if (not user) or not name then
        name = image_name
        user = "_"
      end
      info[i] = { user = user, name = name, tag = tag }
    end
  end

  return info
end

local ns = vim.api.nvim_create_namespace "DockerComposeInfo"
vim.api.nvim_set_hl(0, "DockerComposeInfoRefreshing", { link = "DiagnosticHint" })
vim.api.nvim_set_hl(0, "DockerComposeInfo", { link = "DiagnosticInfo" })
vim.api.nvim_set_hl(0, "DockerComposeInfoError", { link = "DiagnosticError" })

local function load(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local info = get_image_info_of_text(buf)
  for line, i in pairs(info) do
    local em_id = vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
      virt_text = { { "󰑓 ", "DockerComposeInfoRefreshing" } },
      hl_mode = "combine",
    })
    if api_cache[i.user .. "/" .. i.name] then
      local text = ""
      for _, result in ipairs(api_cache[i.user .. "/" .. i.name]) do
        text = text .. result.name .. ", "
      end
      text = text:sub(1, -3)
      vim.schedule(function()
        vim.api.nvim_buf_del_extmark(buf, ns, em_id)
        vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
          virt_text = { { text, "DockerComposeInfo" } },
          hl_mode = "combine",
        })
      end)
      return
    end
    curl.get("https://registry.hub.docker.com/v2/repositories/" .. i.user .. "/" .. i.name .. "/tags?page_size=3", {
      callback = function(res)
        local data = vim.json.decode(res.body)
        if not data.results then
          vim.schedule(function()
            vim.api.nvim_buf_del_extmark(buf, ns, em_id)
            vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
              virt_text = { { "Fetch failed", "DockerComposeInfoError" } },
              hl_mode = "combine",
            })
          end)
          return
        end

        local text = ""
        for _, result in ipairs(data.results) do
          text = text .. result.name .. ", "
        end
        text = text:sub(1, -3)
        api_cache[i.user .. "/" .. i.name] = data.results
        vim.schedule(function()
          vim.api.nvim_buf_del_extmark(buf, ns, em_id)
          vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
            virt_text = { { text, "DockerComposeInfo" } },
            hl_mode = "combine",
          })
        end)
      end,
    })
  end
end

local ag = vim.api.nvim_create_augroup("docker-compose-info", {})

return {
  setup = function()
    if setted_up then
      return
    end

    vim.api.nvim_create_autocmd("FileType", {
      group = ag,
      pattern = { "yaml" },
      callback = function(ctx)
        load(ctx.buf)
        vim.api.nvim_create_autocmd("ModeChanged", {
          group = ag,
          buffer = ctx.buf,
          callback = function(c)
            if c.match:match "n" then
              load(c.buf)
            end
          end,
        })
      end,
    })
  end,
}
