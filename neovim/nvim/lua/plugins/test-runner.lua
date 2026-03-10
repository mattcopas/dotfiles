local neotest_directory = vim.fn.stdpath("data") .. "/neotest-java"
local junit_standalone_version = "1.10.1"
local junit_jar_name = "junit-platform-console-standalone-" .. junit_standalone_version .. ".jar"
local junit_standalone_path = neotest_directory .. "/" .. junit_jar_name

local function ensure_junit_jar()
  if vim.fn.isdirectory(neotest_directory) == 0 then
    vim.fn.mkdir(neotest_directory, "p")
  end

  if vim.fn.filereadable(junit_standalone_path) == 0 then
    vim.notify("Junit jar missing for neot-java. Downloading.", vim.log.levels.INFO)

    local url = "https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/"
      .. junit_standalone_version
      .. "/"
      .. junit_jar_name
    vim.fn.system({ "curl", "-L", url, "-o", junit_standalone_path })

    if vim.v.shell.error == 0 then
      vim.notify("Junit Standlone jar downloaded successfully", vim.log.levels.INFO)
    else
      vim.notify("Error downloading Junit Standlone jar", vim.log.levels.ERROR)
    end
  end
end

local junit_jar_path = ensure_junit_jar()

return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "rcasia/neotest-java",
  },
  init = function()
    ensure_junit_jar()
  end,
  -- Use the 'config' function to delay execution otherwise a race condition/error occurs
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-java")({
          ignore_wrapper = false,
          junit_path = junit_standalone_path,
        }),
      },
      output = {
        enabled = true,
        open_on_run = true,
      },
      quickfix = {
        enabled = true,
      },
    })
  end,
}
