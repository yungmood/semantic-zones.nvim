-- Plugin entry point.
-- Guards against being loaded twice and lets users call
-- `require('semantic-zones').setup()` explicitly.
if vim.g.loaded_semantic_zones then
  return
end
vim.g.loaded_semantic_zones = true
