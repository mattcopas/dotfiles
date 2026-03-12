local function setup_java_boilerplate()
  -- Use BufReadPre too to have this work when creating a java file through neo-tree
  vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPre" }, {
    pattern = "*.java",
    callback = function()
      local path = vim.fn.expand("%:p:h")
      local file_path = vim.fn.expand("%:p")
      local file_not_empty = vim.fn.getfsize(file_path) > 0

      if file_not_empty then
        return
      end

      local base_path = path:match(".*src/[^/]+/java/")

      if base_path then
        local package_path = path:sub(#base_path + 1):gsub("/", ".")
        local class_name = vim.fn.expand("%:t:r")

        local lines = {
          "package " .. package_path .. ";",
          "",
          "public class " .. class_name .. " {",
          "}",
        }
        vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
        vim.api.nvim_win_set_cursor(0, { 4, 4 })
      end
    end,
  })
end

return {
  "mfussenegger/nvim-jdtls",
  ft = { "java" },
  config = function()
    setup_java_boilerplate()
    local mason_path = vim.fn.stdpath("data") .. "/mason/packages/jdtls"

    local home = vim.fn.expand("~")
    local java_21_path = home .. "/.sdkman/candidates/java/21.0.10-amzn/bin/java"
    local lombok_jar = vim.fn.expand("$MASON/share/jdtls/lombok.jar")
    local config = {
      cmd = {
        -- Your explicit Java 21 path
        java_21_path,
        "-Declipse.application=org.eclipse.jdt.ls.core.id1",
        "-Dosgi.bundles.defaultStartLevel=4",
        "-Declipse.product=org.eclipse.jdt.ls.core.product",
        "-Djvm.arg=-Xmx1G",
        "-javaagent:" .. lombok_jar,
        "-jar",
        vim.fn.glob(mason_path .. "/plugins/org.eclipse.equinox.launcher_*.jar"),
        "-configuration",
        mason_path .. "/config_mac",
        "-data",
        vim.fn.stdpath("cache") .. "/jdtls/workspace/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t"),
      },
      root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew" }),
      settings = {
        java = {
          configuration = {
            runtimes = {
              { name = "JavaSE-21", path = java_21_path, default = true },
            },
          },
        },
      },
    }

    -- This manually attaches the server to the buffer
    require("jdtls").start_or_attach(config)
  end,
}
