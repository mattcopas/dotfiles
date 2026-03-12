local home = os.getenv 'HOME'
local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
local workspace_dir = home .. '/.cache/jdtls/workspace/' .. project_name

local sdkman_directory = home .. '/.sdkman/candidates/java'
local java_8_home = sdkman_directory .. '/8.0.472-amzn'
local java_17_home = sdkman_directory .. '/17.0.17-amzn'
local java_21_home = sdkman_directory .. '/21.0.10-amzn'

local os_name = 'linux'
if vim.fn.has 'mac' == 1 then
  os_name = 'mac'
elseif vim.fn.has 'win32' == 1 then
  os_name = 'win'
end

-- Path to the jdtls installation (installed via Mason)
local jdtls_path = home .. '/.local/share/nvim/mason/packages/jdtls'
local path_to_launcher = vim.fn.glob(jdtls_path .. '/plugins/org.eclipse.equinox.launcher_*.jar')
local path_to_config = jdtls_path .. '/config_' .. os_name
local workspace_dir = home .. '/.cache/jdtls/workspace/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')

local config = {
  cmd = {
    java_21_home .. '/bin/java',
    '-Declipse.application=org.eclipse.jdt.ls.core.id1',
    '-Dosgi.bundles.defaultStartLevel=4',
    '-Declipse.product=org.eclipse.jdt.ls.core.product',
    '-Dlog.protocol=true',
    '-Dlog.level=ALL',
    '-Xmx1g',
    '--add-modules=ALL-SYSTEM',
    '--add-opens',
    'java.base/java.util=ALL-UNNAMED',
    '--add-opens',
    'java.base/java.lang=ALL-UNNAMED',

    '-jar',
    path_to_launcher,
    '-configuration',
    path_to_config,
    '-data',
    workspace_dir,
  },
  root_dir = require('jdtls.setup').find_root { '.git', 'pom.xml', 'build.gradle' },
  settings = {
    java = {
      -- Important for your Java 8 project
      configuration = {
        runtimes = {
          {
            name = 'Java 17',
            path = java_17_home, -- Update this!
            default = true,
          },
          {
            name = 'Java 8',
            path = java_8_home, -- Update this!
            default = false,
          },
        },
      },
    },
  },
}

-- Start or attach the server
require('jdtls').start_or_attach(config)
