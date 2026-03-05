return {
  "ahmedkhalf/project.nvim",
  opts = {
    -- Automatic detection based on these patterns
    detection_methods = { "pattern" },
    patterns = { ".git", "pom.xml", "build.gradle" },
  },
  config = function(_, opts)
    require("project_nvim").setup(opts)
  end,
}
