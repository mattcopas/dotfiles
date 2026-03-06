return {
  "mfussenegger/nvim-jdtls",
  ft = { "java" },
  config = function()
    local mason_path = vim.fn.stdpath("data") .. "/mason/packages/jdtls"

    local home = vim.fn.expand("~")
    local java_21_path = home .. "/.sdkman/candidates/java/21.0.10-amzn/bin/java"
    local config = {
      cmd = {
        -- Your explicit Java 21 path
        java_21_path,
        "-Declipse.application=org.eclipse.jdt.ls.core.id1",
        "-Dosgi.bundles.defaultStartLevel=4",
        "-Declipse.product=org.eclipse.jdt.ls.core.product",
        "-Djvm.arg=-Xmx1G",
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
